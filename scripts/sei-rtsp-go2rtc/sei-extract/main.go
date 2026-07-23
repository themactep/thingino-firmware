/*
Thingino SEI Extractor for go2rtc
=================================
Reads raw H.264 Annex‑B from a piped ffmpeg process (or stdin),
extracts Thingino SEI user-data-registered-itut-t35 payloads,
and writes per‑element OSD text files for go2rtc's ffmpeg drawtext
filter to consume with reload=1.

Usage:
    ffmpeg -i rtsp://cam:554/stream -c:v copy -bsf:v h264_mp4toannexb -f h264 pipe:1 |
    sei-extract [flags]

Flags:
    --dir PATH       Directory for OSD text files (default: /tmp/sei-osd)
    --max-elements N Max OSD element files (default: 8)
    --interval MS    Update interval in ms (default: 100)
    --position       Position mode: top-left|top-right|bottom-left|bottom-right|
                     top-center|middle-center (default: top-left)
    --font-size N    For virtual spacing offset in stacked lines (not used yet)
    --only-print     Print SEI JSON as it arrives, don't write text files
    --verbose        Verbose logging to stderr

Output files:
    --dir/sei_osd_0.txt, sei_osd_1.txt, ... sei_osd_N.txt
    Each file contains the text for one OSD line element.
    The SEI rotation value and canvas size are also written to
    --dir/sei_meta.json (rotation, sw, sh) for optional downstream use.

The companion go2rtc config uses these files with:
    drawtext=textfile='/tmp/sei-osd/sei_osd_0.txt':reload=1:...
*/

package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

// ── Constants ────────────────────────────────────────────────────────────────

// Thingino SEI UUID (16 bytes) as registered in user_data_unregistered SEI payloads.
var thinginoSEIUUID = [16]byte{
	0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x47, 0x80,
	0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90,
}

// SEI types that carry a wall‑clock timestamp → interpolate in real time.
var interpolatedTypes = map[string]bool{
	"timestamp": true,
}

// ── SEI element JSON structure ───────────────────────────────────────────────

type SEIElement struct {
	Type string `json:"t"`
	Text string `json:"text"`
	X    int    `json:"x"`
	Y    int    `json:"y"`
}

type SEIPayload struct {
	Rotation int          `json:"rotation,omitempty"`
	SW       int          `json:"sw,omitempty"`
	SH       int          `json:"sh,omitempty"`
	Elements []SEIElement `json:"elements,omitempty"`
}

type SEIMeta struct {
	Rotation int `json:"rotation"`
	SW       int `json:"sw"`
	SH       int `json:"sh"`
}

// SEIPosition records one element's drawtext expression coordinates.
type SEIPosition struct {
	Index int    `json:"index"`
	X     int    `json:"x"`
	Y     int    `json:"y"`
	XExpr string `json:"x_expr"`
	YExpr string `json:"y_expr"`
}

// ── State ────────────────────────────────────────────────────────────────────

type state struct {
	mu           sync.Mutex
	lastSEI      *SEIPayload
	anchorWall   time.Time
	anchorText   map[string]string // key → base text for interpolated elements
	rotation     int
	sw, sh       int
	hasData      bool
	positions    []SEIPosition // persisted to sei_positions.json on first SEI
	posWritten   bool
}

func (s *state) update(sei *SEIPayload) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.lastSEI = sei
	s.hasData = true
	s.rotation = sei.Rotation
	s.sw = sei.SW
	s.sh = sei.SH
	s.anchorWall = time.Now()
	s.anchorText = make(map[string]string)

	// Capture element positions on first SEI (they don't change per stream)
	if !s.posWritten && len(sei.Elements) > 0 {
		s.positions = make([]SEIPosition, 0, len(sei.Elements))
		for i, el := range sei.Elements {
			xExpr, yExpr := seiPosToDrawtext(el.X, el.Y)
			s.positions = append(s.positions, SEIPosition{
				Index: i,
				X:     el.X,
				Y:     el.Y,
				XExpr: xExpr,
				YExpr: yExpr,
			})
		}
	}

	for _, el := range sei.Elements {
		if interpolatedTypes[el.Type] {
			key := fmt.Sprintf("%s:%d:%d", el.Type, el.X, el.Y)
			s.anchorText[key] = el.Text
		}
	}
}

type displayLine struct {
	Text  string
	XExpr string
	YExpr string
}

// getDisplayLines returns the current OSD lines with interpolated timestamps.
// positionMode: "top-left", "top-right", "bottom-left", "bottom-right",
// "top-center", "middle-center"
func (s *state) getDisplayLines(positionMode string) []displayLine {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.lastSEI == nil {
		return nil
	}

	elapsed := time.Since(s.anchorWall)
	lines := make([]displayLine, 0, len(s.lastSEI.Elements))

	for _, el := range s.lastSEI.Elements {
		text := el.Text
		if interpolatedTypes[el.Type] {
			key := fmt.Sprintf("%s:%d:%d", el.Type, el.X, el.Y)
			if base, ok := s.anchorText[key]; ok {
				if t, err := time.Parse("2006-01-02 15:04:05", base); err == nil {
					text = t.Add(elapsed).Format("2006-01-02 15:04:05")
				}
			}
		}

		xExpr, yExpr := seiPosToDrawtext(el.X, el.Y)
		lines = append(lines, displayLine{Text: text, XExpr: xExpr, YExpr: yExpr})
	}
	return lines
}

func seiPosToDrawtext(x, y int) (string, string) {
	var xExpr, yExpr string

	switch {
	case x > 0:
		xExpr = fmt.Sprintf("%d", x)
	case x < 0:
		xExpr = fmt.Sprintf("w-text_w-%d", -x)
	default:
		xExpr = "(w-text_w)/2"
	}

	switch {
	case y > 0:
		yExpr = fmt.Sprintf("%d", y)
	case y < 0:
		yExpr = fmt.Sprintf("h-text_h-%d", -y)
	default:
		yExpr = "(h-text_h)/2"
	}

	return xExpr, yExpr
}

// ── NAL parser ───────────────────────────────────────────────────────────────

type nalParser struct {
	buf     []byte
	onSEI   func(*SEIPayload)
	verbose bool
}

func newNALParser(onSEI func(*SEIPayload), verbose bool) *nalParser {
	return &nalParser{onSEI: onSEI, verbose: verbose}
}

func (p *nalParser) feed(chunk []byte) {
	p.buf = append(p.buf, chunk...)
	for {
		start, startLen := p.findStartCode(0)
		if start < 0 {
			break
		}
		end, _ := p.findStartCode(start + startLen)
		if end < 0 {
			break
		}
		nal := p.buf[start+startLen : end]
		if len(nal) > 0 {
			nalType := nal[0] & 0x1F
			if nalType == 6 { // SEI
				rbsp := removeEPB(nal)
				payload := parseThinginoSEI(rbsp)
				if payload != nil {
					p.onSEI(payload)
				}
			}
		}
		p.buf = p.buf[end:]
	}
}

func (p *nalParser) findStartCode(offset int) (idx int, codeLen int) {
	data := p.buf
	for i := offset; i < len(data)-2; i++ {
		if data[i] == 0 && data[i+1] == 0 {
			if data[i+2] == 1 {
				return i, 3
			}
			if i+3 < len(data) && data[i+2] == 0 && data[i+3] == 1 {
				return i, 4
			}
		}
	}
	return -1, 0
}

func removeEPB(data []byte) []byte {
	result := make([]byte, 0, len(data))
	zeroCount := 0
	for _, b := range data {
		if zeroCount == 2 && b == 0x03 {
			zeroCount = 0
			continue
		}
		result = append(result, b)
		if b == 0 {
			zeroCount++
		} else {
			zeroCount = 0
		}
	}
	return result
}

func parseThinginoSEI(rbsp []byte) *SEIPayload {
	pos := 1 // skip NAL header
	length := len(rbsp)

	for pos < length-1 {
		payloadType := 0
		for pos < length && rbsp[pos] == 0xFF {
			payloadType += 255
			pos++
		}
		if pos >= length {
			break
		}
		payloadType += int(rbsp[pos])
		pos++

		payloadSize := 0
		for pos < length && rbsp[pos] == 0xFF {
			payloadSize += 255
			pos++
		}
		if pos >= length {
			break
		}
		payloadSize += int(rbsp[pos])
		pos++

		if pos+payloadSize > length {
			break
		}
		payloadData := rbsp[pos : pos+payloadSize]
		pos += payloadSize

		if payloadType == 5 && len(payloadData) >= 16 {
			match := true
			for i := 0; i < 16; i++ {
				if payloadData[i] != thinginoSEIUUID[i] {
					match = false
					break
				}
			}
			if match {
				var sei SEIPayload
				if err := json.Unmarshal(payloadData[16:], &sei); err == nil {
					return &sei
				}
			}
		}
		// type 0x80 terminates
		if payloadType == 0x80 {
			break
		}
	}
	return nil
}

// ── OSD file writer ──────────────────────────────────────────────────────────

type osdWriter struct {
	state     *state
	dir       string
	maxElem   int
	interval  time.Duration
	verbose   bool

	stopCh chan struct{}
	wg     sync.WaitGroup
}

func newOSDWriter(state *state, dir string, maxElem int, interval time.Duration, verbose bool) *osdWriter {
	return &osdWriter{
		state:    state,
		dir:      dir,
		maxElem:  maxElem,
		interval: interval,
		verbose:  verbose,
		stopCh:   make(chan struct{}),
	}
}

func (w *osdWriter) start() error {
	if err := os.MkdirAll(w.dir, 0755); err != nil {
		return fmt.Errorf("creating osd dir %s: %w", w.dir, err)
	}
	w.wg.Add(1)
	go w.loop()
	return nil
}

func (w *osdWriter) stop() {
	close(w.stopCh)
	w.wg.Wait()
}

func (w *osdWriter) loop() {
	defer w.wg.Done()
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	for {
		select {
		case <-w.stopCh:
			return
		case <-ticker.C:
			w.writeFiles()
		}
	}
}

func (w *osdWriter) writeFiles() {
	lines := w.state.getDisplayLines("top-left") // position handled by drawtext

	// Write SEI metadata for downstream consumers (rotation, canvas size)
	w.state.mu.Lock()
	meta := SEIMeta{
		Rotation: w.state.rotation,
		SW:       w.state.sw,
		SH:       w.state.sh,
	}
	positions := w.state.positions
	posWritten := w.state.posWritten
	w.state.mu.Unlock()

	metaPath := filepath.Join(w.dir, "sei_meta.json")
	metaJSON, _ := json.Marshal(meta)
	existingMeta, _ := os.ReadFile(metaPath)
	if string(existingMeta) != string(metaJSON) {
		os.WriteFile(metaPath, metaJSON, 0644)
	}

	// Write per-element drawtext positions (once, on first SEI)
	if !posWritten && len(positions) > 0 {
		posPath := filepath.Join(w.dir, "sei_positions.json")
		posJSON, _ := json.Marshal(positions)
		if err := os.WriteFile(posPath, posJSON, 0644); err != nil && w.verbose {
			fmt.Fprintf(os.Stderr, "sei-extract: write %s: %v\n", posPath, err)
		}
		w.state.mu.Lock()
		w.state.posWritten = true
		w.state.mu.Unlock()
	}

	for i := 0; i < w.maxElem; i++ {
		fpath := filepath.Join(w.dir, fmt.Sprintf("sei_osd_%d.txt", i))
		var text string
		if i < len(lines) {
			text = lines[i].Text
		}
		// Only write if content changed (reduce filesystem churn)
		existing, err := os.ReadFile(fpath)
		if err == nil && string(existing) == text {
			continue
		}
		if err := os.WriteFile(fpath, []byte(text), 0644); err != nil && w.verbose {
			fmt.Fprintf(os.Stderr, "sei-extract: write %s: %v\n", fpath, err)
		}
	}
}

// ── Main ─────────────────────────────────────────────────────────────────────

func main() {
	dir := flag.String("dir", "/tmp/sei-osd", "Directory for OSD text files")
	maxElements := flag.Int("max-elements", 8, "Max OSD element files")
	intervalMs := flag.Int("interval", 100, "Update interval in ms")
	onlyPrint := flag.Bool("only-print", false, "Print SEI JSON as it arrives, don't write files")
	verbose := flag.Bool("verbose", false, "Verbose logging to stderr")
	flag.Parse()

	if *verbose {
		fmt.Fprintf(os.Stderr, "sei-extract: starting, output dir=%s, max-elements=%d, interval=%dms\n",
			*dir, *maxElements, *intervalMs)
	}

	state := &state{}

	if *onlyPrint {
		// Print-only mode: dump each SEI as JSON line
		parser := newNALParser(func(sei *SEIPayload) {
			data, _ := json.Marshal(sei)
			fmt.Println(string(data))
		}, *verbose)

		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

		go func() {
			reader := bufio.NewReaderSize(os.Stdin, 65536)
			for {
				chunk, err := reader.ReadBytes(0) // won't find 0 in H.264, use read chunk
				if err != nil {
					if err != io.EOF {
						fmt.Fprintf(os.Stderr, "sei-extract: read error: %v\n", err)
					}
					return
				}
				parser.feed(chunk)
			}
		}()
		<-sigCh
		return
	}

	// Normal mode: write OSD text files
	parser := newNALParser(func(sei *SEIPayload) {
		if *verbose {
			fmt.Fprintf(os.Stderr, "sei-extract: got SEI rotation=%d canvas=%dx%d elements=%d\n",
				sei.Rotation, sei.SW, sei.SH, len(sei.Elements))
		}
		state.update(sei)
	}, *verbose)

	writer := newOSDWriter(state, *dir, *maxElements, time.Duration(*intervalMs)*time.Millisecond, *verbose)
	if err := writer.start(); err != nil {
		fmt.Fprintf(os.Stderr, "sei-extract: %v\n", err)
		os.Exit(1)
	}

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// Read stdin in a goroutine
	go func() {
		reader := bufio.NewReaderSize(os.Stdin, 65536)
		buf := make([]byte, 65536)
		for {
			n, err := reader.Read(buf)
			if n > 0 {
				// Copy to a new slice since parser.feed may retain
				chunk := make([]byte, n)
				copy(chunk, buf[:n])
				parser.feed(chunk)
			}
			if err != nil {
				if err != io.EOF && *verbose {
					fmt.Fprintf(os.Stderr, "sei-extract: read error: %v\n", err)
				}
				return
			}
		}
	}()

	if *verbose {
		fmt.Fprintf(os.Stderr, "sei-extract: waiting for SEI data...\n")
	}

	<-sigCh
	if *verbose {
		fmt.Fprintf(os.Stderr, "sei-extract: shutting down\n")
	}
	writer.stop()
}
