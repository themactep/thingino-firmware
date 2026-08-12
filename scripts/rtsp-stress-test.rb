#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
require 'tmpdir'
require 'time'

home_dir = ENV['HOME'] || Dir.home
home_dir = '/tmp' if home_dir.nil? || home_dir.empty?

@options = {
  ssh_user: 'root',
  rtsp_user: 'thingino',
  rtsp_pass: 'thingino',
  channel: 'ch0',
  rtsp_port: '554',
  transport: 'udp',
  sessions: 8,
  duration: 15,
  pause: 2,
  output_dir: "#{home_dir}/rtsp-stress/#{Time.now.strftime('%Y%m%d-%H%M%S')}",
  server_log: nil,
  remote_config: '/etc/prudynt.json',
  remote_update_path: '/tmp/rtsp-stress-update.json',
  boot_timeout: 180,
  stream_timeout: 60,
  start_cmd: nil,
  restore_config: true,
  udp_matrix: false,
  debug: false,
  scenarios: [],
}

def log_info(message)
  puts "[INFO] #{message}"
end

def log_success(message)
  puts "[OK] #{message}"
end

def log_warning(message)
  puts "[WARN] #{message}"
end

def log_error(message)
  warn "[ERR] #{message}"
end

def log_debug(message)
  puts "[DBG] #{message}" if @options[:debug]
end

def sanitize_label(label)
  label = label.to_s.strip.gsub(/\s+/, '-')
  label.gsub(/[^A-Za-z0-9._-]/, '_')
end

def command_exists?(name)
  ENV['PATH'].split(File::PATH_SEPARATOR).any? do |dir|
    path = File.join(dir, name)
    File.executable?(path) && !File.directory?(path)
  end
end

def require_command(name)
  return if command_exists?(name)
  log_error("Missing required command: #{name}")
  exit 1
end

parser = OptionParser.new do |opts|
  opts.banner = <<~BANNER
    Usage: rtsp-stress-test.sh [OPTIONS]

    Host-side RTSP stress test helper for Thingino cameras.
    It can:
      - run repeated ffmpeg sessions over RTSP/UDP or RTSP/TCP
      - optionally apply camera config changes with jct import
      - reboot between scenarios
      - capture per-session client logs and optional server log slices
      - summarize RTP loss and decode/concealment errors
  BANNER

  opts.on('--camera HOST', 'Camera IP or hostname') { |v| @options[:camera_host] = v }
  opts.on('--ssh-user USER', 'SSH user (default: root)') { |v| @options[:ssh_user] = v }
  opts.on('--rtsp-user USER', 'RTSP username (default: thingino)') { |v| @options[:rtsp_user] = v }
  opts.on('--rtsp-pass PASS', 'RTSP password (default: thingino)') { |v| @options[:rtsp_pass] = v }
  opts.on('--channel NAME', 'RTSP channel path (default: ch0)') { |v| @options[:channel] = v }
  opts.on('--rtsp-port PORT', 'RTSP port (default: 554)') { |v| @options[:rtsp_port] = v }
  opts.on('--transport MODE', 'udp or tcp (default: udp)') { |v| @options[:transport] = v }
  opts.on('--sessions N', Integer, 'Sessions per scenario (default: 8)') { |v| @options[:sessions] = v }
  opts.on('--duration SECONDS', Integer, 'session duration in seconds (default: 15)') { |v| @options[:duration] = v }
  opts.on('--pause SECONDS', Integer, 'Pause between sessions (default: 2)') { |v| @options[:pause] = v }
  opts.on('--output-dir DIR', 'Output directory (default: ~/rtsp-stress-YYYYmmdd-HHMMSS)') { |v| @options[:output_dir] = v }
  opts.on('--server-log PATH', 'Optional remote prudynt log to slice per session') { |v| @options[:server_log] = v }
  opts.on('--config PATH', 'Remote prudynt config path (default: /etc/prudynt.json)') { |v| @options[:remote_config] = v }
  opts.on('--remote-update PATH', 'Remote temp json path (default: /tmp/rtsp-stress-update.json)') { |v| @options[:remote_update_path] = v }
  opts.on('--boot-timeout SECONDS', Integer, 'Wait for SSH after reboot (default: 180)') { |v| @options[:boot_timeout] = v }
  opts.on('--stream-timeout SECONDS', Integer, 'Wait for RTSP readiness (default: 60)') { |v| @options[:stream_timeout] = v }
  opts.on('--start-cmd CMD', 'Optional remote command to run after reboot') { |v| @options[:start_cmd] = v }
  opts.on('--scenario SPEC', 'Scenario as label:bitrate:fps:gop:est_bitrate') { |v| @options[:scenarios] << v }
  opts.on('--udp-matrix', 'Add the standard UDP tuning matrix') { @options[:udp_matrix] = true }
  opts.on('--no-restore', 'Do not restore original config after modified scenarios') { @options[:restore_config] = false }
  opts.on('--debug', 'Enable debug output') { @options[:debug] = true }
  opts.on('-h', '--help', 'Show help') do
    puts opts
    exit
  end
end

begin
  parser.parse!(ARGV)
rescue OptionParser::InvalidOption => e
  log_error(e.message)
  puts parser
  exit 1
end

unless @options[:camera_host] && !@options[:camera_host].strip.empty?
  log_error('--camera is required')
  puts parser
  exit 1
end

unless %w[udp tcp].include?(@options[:transport])
  log_error('--transport must be udp or tcp')
  exit 1
end

require_command('ssh')
require_command('ffmpeg')

FileUtils.mkdir_p(@options[:output_dir])
@options[:output_dir] = File.realpath(@options[:output_dir])

if @options[:scenarios].empty?
  @options[:scenarios] << 'current:-:-:-:-'
end

if @options[:udp_matrix]
  @options[:scenarios].concat([
    'current:-:-:-:-',
    'lowbit1500:1500:0:30:1800',
    'bitrate1600:1600:0:30:1920',
    'gop60-1700:1700:0:60:2040',
    'fps20-1700:1700:20:30:2040',
  ])
end

SSH_DEST = "#{@options[:ssh_user]}@#{@options[:camera_host]}"
SSH_CONTROL_DIR = Dir.mktmpdir('rtsp-stress-ssh-', '/tmp')
SSH_OPTS = [
  '-o', 'ConnectTimeout=5',
  '-o', 'ServerAliveInterval=5',
  '-o', 'ServerAliveCountMax=3',
  '-o', 'StrictHostKeyChecking=accept-new',
  '-o', 'ControlMaster=auto',
  '-o', 'ControlPersist=600',
  '-o', 'ControlPath=' + File.join(SSH_CONTROL_DIR, '%C'),
]

at_exit do
  begin
    close_ssh_master
  rescue StandardError => e
    log_warning("SSH cleanup failed: #{e.message}")
  ensure
    FileUtils.rm_rf(SSH_CONTROL_DIR) if Dir.exist?(SSH_CONTROL_DIR)
  end
end

trap('INT') do
  log_warning('Interrupted by user')
  exit 130
end

trap('TERM') do
  log_warning('Terminated')
  exit 143
end

def close_ssh_master
  system('ssh', *SSH_OPTS, '-O', 'exit', SSH_DEST, out: File::NULL, err: File::NULL)
rescue Errno::ENOENT
  # ignore
end

def known_hosts_file
  File.expand_path('~/.ssh/known_hosts')
end

def bad_host_key_error?(stderr)
  stderr.to_s.match?(/Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED|offending key|WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!/i)
end

def remove_stale_known_host
  return unless File.exist?(known_hosts_file)
  if system('ssh-keygen', '-R', @options[:camera_host], '-f', known_hosts_file, out: File::NULL, err: File::NULL)
    log_warning("Removed stale SSH host key for #{@options[:camera_host]} from #{known_hosts_file}")
  end
end

def ssh_capture3_with_retry(cmd)
  log_debug("SSH: #{Shellwords.join(cmd)}")
  stdout, stderr, status = Open3.capture3(*cmd)
  return [stdout, stderr, status] if status.success?
  if bad_host_key_error?(stderr)
    remove_stale_known_host
    stdout, stderr, status = Open3.capture3(*cmd)
  end
  [stdout, stderr, status]
end

def run_local(cmd, timeout: nil, out: :inherit, err: :inherit)
  log_debug("LOCAL: #{Shellwords.join(cmd)}#{timeout ? " (timeout=#{timeout}s)" : ''}")
  pid = nil
  status = nil

  begin
    pid = Process.spawn(*cmd, out: out, err: err)
    if timeout
      deadline = Time.now + timeout
      loop do
        finished = Process.waitpid(pid, Process::WNOHANG)
        if finished
          status = $?.exitstatus
          break
        end
        if Time.now >= deadline
          Process.kill('TERM', pid) rescue nil
          sleep 0.2
          Process.kill('KILL', pid) rescue nil
          status = nil
          break
        end
        sleep 0.1
      end
    else
      _, status = Process.waitpid2(pid)
      status = status.exitstatus
    end
  rescue Interrupt
    if pid
      Process.kill('TERM', pid) rescue nil
      sleep 0.2
      Process.kill('KILL', pid) rescue nil
    end
    raise
  end

  status
end

def run_local_capture(cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  [status.success?, stdout, stderr]
end

def remote_command(command)
  log_debug("REMOTE: #{command}")
  escaped = Shellwords.escape(command)
  full = ['ssh', *SSH_OPTS, SSH_DEST, 'sh', '-c', escaped]
  stdout, stderr, status = ssh_capture3_with_retry(full)
  [status.success?, stdout, stderr]
end

def send_file_to_remote(local_path, remote_path)
  log_debug("UPLOAD: #{local_path} -> #{remote_path} (#{File.size(local_path)} bytes)")
  content = File.binread(local_path)
  cmd = ['ssh', *SSH_OPTS, SSH_DEST, 'cat', '>', remote_path]
  stdout, stderr, status = Open3.capture3(*cmd, stdin_data: content)
  if !status.success? && bad_host_key_error?(stderr)
    remove_stale_known_host
    stdout, stderr, status = Open3.capture3(*cmd, stdin_data: content)
  end
  unless status.success?
    raise "scp-like upload failed: #{stderr.strip}"
  end
end

def build_update_json(path, bitrate, fps, gop, est)
  data = {}
  stream = {}
  stream['bitrate'] = Integer(bitrate) if bitrate != '-'
  stream['fps'] = Integer(fps) if fps != '-'
  stream['gop'] = Integer(gop) if gop != '-'
  data['stream0'] = stream unless stream.empty?
  data['rtsp'] = { 'est_bitrate' => Integer(est) } if est != '-'
  log_debug("UPDATE-JSON: #{path} bitrate=#{bitrate} fps=#{fps} gop=#{gop} est=#{est}")
  log_debug("UPDATE-JSON content: #{JSON.pretty_generate(data).strip}") unless data.empty?
  File.write(path, JSON.pretty_generate(data) + "\n")
end

def apply_json_update(local_path)
  content = File.read(local_path)
  json = JSON.parse(content)
  return if json.empty?

  log_debug("APPLY: #{local_path} -> #{@options[:remote_update_path]}")
  send_file_to_remote(local_path, @options[:remote_update_path])
  success, _stdout, _stderr = remote_command("jct #{Shellwords.escape(@options[:remote_config])} import #{Shellwords.escape(@options[:remote_update_path])} >/dev/null")
  raise 'Remote jct import failed' unless success
end

def wait_for_ssh
  deadline = Time.now + @options[:boot_timeout]
  attempt = 0
  until Time.now >= deadline
    attempt += 1
    log_debug("SSH probe attempt #{attempt}")
    success, _out, _err = remote_command('echo up')
    return true if success
    sleep 5
  end
  false
end

def wait_for_stream
  deadline = Time.now + @options[:stream_timeout]
  attempt = 0
  until Time.now >= deadline
    attempt += 1
    log_debug("STREAM probe attempt #{attempt}: #{rtsp_url}")
    rc = run_local(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-rtsp_transport', @options[:transport], '-i', rtsp_url, '-t', '2', '-f', 'null', '-'], timeout: 10, out: File::NULL, err: File::NULL)
    return true if rc == 0
    sleep 2
  end
  false
end

def rtsp_url
  "rtsp://#{@options[:rtsp_user]}:#{@options[:rtsp_pass]}@#{@options[:camera_host]}:#{@options[:rtsp_port]}/#{@options[:channel]}"
end

def read_remote_key(key)
  success, stdout, _stderr = remote_command("jct #{Shellwords.escape(@options[:remote_config])} get #{Shellwords.escape(key)}")
  raise "Failed to read remote key #{key}" unless success
  stdout.strip
end

def get_server_log_size
  return 0 unless @options[:server_log]
  success, stdout, _stderr = remote_command("test -f #{Shellwords.escape(@options[:server_log])} && wc -c < #{Shellwords.escape(@options[:server_log])}")
  return 0 unless success
  size = stdout.strip.to_i
  log_debug("SERVER-LOG size: #{size}")
  size
end

def write_server_log_slice(start_bytes, end_bytes, output_path)
  return if @options[:server_log].nil? || end_bytes <= start_bytes
  length = end_bytes - start_bytes
  log_debug("SERVER-LOG slice: #{start_bytes}-#{end_bytes} (#{length} bytes) -> #{output_path}")
  File.open(output_path, 'wb') do |fh|
    command = "dd if=#{Shellwords.escape(@options[:server_log])} bs=1 skip=#{start_bytes} count=#{length} 2>/dev/null"
    Open3.popen3('ssh', *SSH_OPTS, SSH_DEST, 'sh', '-c', Shellwords.escape(command)) do |_stdin, stdout, stderr, wait_thr|
      IO.copy_stream(stdout, fh)
      unless wait_thr.value.success?
        log_warning("Failed to capture remote server log slice: #{stderr.read.strip}")
      end
    end
  end
end

def capture_original_config
  {
    bitrate: 'stream0.bitrate',
    fps: 'stream0.fps',
    gop: 'stream0.gop',
    est: 'rtsp.est_bitrate',
  }.each do |key, remote_key|
    @options["orig_#{key}".to_sym] = read_remote_key(remote_key)
    log_debug("ORIG: #{key}=#{@options["orig_#{key}".to_sym]}")
  end
end

def write_metadata
  File.write(File.join(@options[:output_dir], 'metadata.txt'), <<~METADATA)
    camera=#{@options[:camera_host]}
    ssh_user=#{@options[:ssh_user]}
    rtsp_url=#{rtsp_url}
    transport=#{@options[:transport]}
    sessions=#{@options[:sessions]}
    duration=#{@options[:duration]}
    pause=#{@options[:pause]}
    remote_config=#{@options[:remote_config]}
    server_log=#{@options[:server_log] || '<none>'}
    start_cmd=#{@options[:start_cmd] || '<none>'}
    original_stream0.bitrate=#{@options[:orig_bitrate]}
    original_stream0.fps=#{@options[:orig_fps]}
    original_stream0.gop=#{@options[:orig_gop]}
    original_rtsp.est_bitrate=#{@options[:orig_est]}
  METADATA
end

def reboot_and_wait
  log_info("Rebooting camera #{@options[:camera_host]}")
  close_ssh_master
  log_debug("Sending reboot command")
  remote_command('reboot -f')
  sleep 5
  log_debug("Waiting for SSH (timeout=#{@options[:boot_timeout]}s)")
  unless wait_for_ssh
    log_error("Camera did not return to SSH within #{@options[:boot_timeout]}s")
    return false
  end
  log_debug("SSH returned after reboot")

  if @options[:start_cmd]
    log_info('Running post-reboot start command')
    remote_command(@options[:start_cmd])
  end

  log_debug("Waiting for RTSP stream (timeout=#{@options[:stream_timeout]}s)")
  unless wait_for_stream
    log_error("RTSP stream did not become ready within #{@options[:stream_timeout]}s")
    return false
  end
  log_debug("RTSP stream ready after reboot")

  true
end

def restore_original_config
  log_debug("RESTORE: orig_bitrate=#{@options[:orig_bitrate]} orig_fps=#{@options[:orig_fps]} orig_gop=#{@options[:orig_gop]} orig_est=#{@options[:orig_est]}")
  restore_path = File.join(@options[:output_dir], 'restore-original.json')
  build_update_json(restore_path, @options[:orig_bitrate], @options[:orig_fps], @options[:orig_gop], @options[:orig_est])
  apply_json_update(restore_path)
  reboot_and_wait
end

def add_default_scenarios
  return unless @options[:udp_matrix]
  @options[:scenarios].concat([
    'current:-:-:-:-',
    'lowbit1500:1500:0:30:1800',
    'bitrate1600:1600:0:30:1920',
    'gop60-1700:1700:0:60:2040',
    'fps20-1700:1700:20:30:2040',
  ])
end

add_default_scenarios

log_debug("Options: #{@options.inspect}")
log_debug("Scenarios: #{@options[:scenarios].inspect}")
log_debug("Output dir: #{@options[:output_dir]}")
log_debug("SSH control: #{SSH_CONTROL_DIR}")
log_debug("RTSP URL: #{rtsp_url}")

log_info("Connecting to #{@options[:camera_host]}")
unless wait_for_ssh
  log_error('Unable to reach camera over SSH')
  exit 1
end

success, _stdout, _stderr = remote_command('command -v jct >/dev/null 2>&1')
unless success
  log_error('Remote host is missing jct')
  exit 1
end

capture_original_config
write_metadata

overall_summary = File.join(@options[:output_dir], 'overall-summary.txt')
File.write(overall_summary, <<~SUMMARY)
  Run root: #{@options[:output_dir]}
  camera=#{@options[:camera_host]}
  transport=#{@options[:transport]}
  sessions=#{@options[:sessions]}
  duration=#{@options[:duration]}
  original bitrate=#{@options[:orig_bitrate]} fps=#{@options[:orig_fps]} gop=#{@options[:orig_gop]} est_bitrate=#{@options[:orig_est]}
SUMMARY

failed_scenarios = 0
modified_config = false

@options[:scenarios].each do |scenario_spec|
  log_debug("Parsing scenario spec: #{scenario_spec}")
  label, bitrate, fps, gop, est = scenario_spec.split(':', 5)
  label = sanitize_label(label || 'scenario')
  bitrate = bitrate || '-'
  fps = fps || '-'
  gop = gop || '-'
  est = est || '-'

  scenario_dir = File.join(@options[:output_dir], label)
  FileUtils.mkdir_p(scenario_dir)

  log_info("Running scenario #{label}")
  log_debug("Scenario params: bitrate=#{bitrate} fps=#{fps} gop=#{gop} est=#{est}")
  File.write(File.join(scenario_dir, 'scenario.txt'), <<~SCENARIO)
    scenario=#{label}
    bitrate=#{bitrate}
    fps=#{fps}
    gop=#{gop}
    est_bitrate=#{est}
  SCENARIO

  changed = [bitrate, fps, gop, est].any? { |value| value != '-' }
  log_debug("Scenario changed? #{changed}")
  if changed
    modified_config = true
    build_update_json(File.join(scenario_dir, 'update.json'), bitrate, fps, gop, est)
    begin
      apply_json_update(File.join(scenario_dir, 'update.json'))
    rescue StandardError => e
      log_warning("Failed to apply scenario update: #{e.message}")
      failed_scenarios += 1
      next
    end
    unless reboot_and_wait
      failed_scenarios += 1
      next
    end
  else
    unless wait_for_stream
      log_warning("Stream not ready for scenario #{label}")
      failed_scenarios += 1
      next
    end
  end

  total_missed = 0
  total_decode = 0
  total_conceal = 0
  total_maxdelay = 0

  summary_path = File.join(scenario_dir, 'summary.txt')
  File.write(summary_path, '')

  1.upto(@options[:sessions]) do |session|
    log_info("Starting session #{session} for scenario #{label}")
    client_log = File.join(scenario_dir, "client-#{session}.log")
    server_log_file = File.join(scenario_dir, "server-#{session}.log")

    log_debug("Session #{session}: client_log=#{client_log} server_log=#{server_log_file}")
    start_bytes = get_server_log_size
    rc = run_local(
      ['ffmpeg', '-hide_banner', '-loglevel', 'info', '-nostats', '-rtsp_transport', @options[:transport], '-i', rtsp_url, '-t', @options[:duration].to_s, '-f', 'null', '-'],
      timeout: @options[:duration] + 5,
      out: client_log,
      err: client_log
    )
    end_bytes = get_server_log_size
    write_server_log_slice(start_bytes, end_bytes, server_log_file)

    missed = 0
    decode = 0
    conceal = 0
    maxdelay = 0
    if File.exist?(client_log)
      log_debug("Analyzing client log: #{client_log} (#{File.size(client_log)} bytes)")
      log_text = File.read(client_log, mode: 'rb', encoding: 'utf-8', invalid: :replace, undef: :replace)
      missed = log_text.scan(/RTP: missed (\d+) packets/).flatten.map(&:to_i).sum
      decode = log_text.scan(/error while decoding/i).size
      conceal = log_text.scan(/concealing \d+ /i).size
      maxdelay = log_text.scan(/max delay reached/i).size
    end

    total_missed += missed
    total_decode += decode
    total_conceal += conceal
    total_maxdelay += maxdelay

    File.open(summary_path, 'a') do |fh|
      fh.puts "session=#{session} rc=#{rc || 'timeout'} missed_sum=#{missed} decode=#{decode} conceal=#{conceal} maxdelay=#{maxdelay}"
    end

    log_info("Completed session #{session} rc=#{rc || 'timeout'} missed=#{missed} decode=#{decode} conceal=#{conceal} maxdelay=#{maxdelay}")
    sleep @options[:pause]
  end

  File.open(overall_summary, 'a') do |fh|
    fh.puts "RESULT label=#{label} changed=#{changed ? 1 : 0} missed=#{total_missed} decode=#{total_decode} conceal=#{total_conceal} maxdelay=#{total_maxdelay} dir=#{scenario_dir}"
  end
end

if modified_config && @options[:restore_config]
  log_debug("Restoring config: modified=#{modified_config} restore=#{@options[:restore_config]}")
  log_info('Restoring original camera config')
  unless restore_original_config
    log_warning('Failed to verify restored camera config after reboot')
    failed_scenarios += 1
  else
    log_success('Original camera config restored')
  end
end

if failed_scenarios.positive?
  log_warning("Completed with #{failed_scenarios} failed scenario(s). Results are in #{@options[:output_dir]}")
  exit 1
end

log_success("Completed successfully. Results are in #{@options[:output_dir]}")
