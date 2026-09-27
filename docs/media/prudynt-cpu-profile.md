# prudynt CPU profile (T31, open stack)

Scope: what consumes `prudynt` CPU on a T31 camera running the open stack
(`open-tx-isp` kernel driver + OpenIMP `libimp.so`). Baseline measured on
`vanhua_s37i_t31l_imx307_eth` (T31L, imx307), 192.168.88.31, wired, OpenIMP +
open-tx-isp, `stream0` = 1080p15 H.264, 4200 kbps.

## Method

Per-thread CPU comes from `/proc/<pid>/task/<tid>/stat` (fields 14 and 15,
utime + stime, in clock ticks). Two snapshots six seconds apart give a rate.
Threads are not named by prudynt, so most show `comm = prudynt`.

Attribution uses a controllable RTSP client (start/stop `ffmpeg`), not runtime
config changes. That matters: `set<T>()` by way of the API only marks the value
dirty in the config, it does not reconfigure the running encoder. Changing
`stream0.fps` or `stream0.enabled` over `prudyntctl` does nothing until a
restart, so an "I lowered fps and CPU did not move" reading is meaningless
without one.

Snapshots:

```sh
# live instance only; a prior instance can linger as a zombie
for p in $(pidof prudynt); do
  s=$(awk '{print $3}' /proc/$p/stat 2>/dev/null)
  [ "$s" != Z ] && live=$p
done
for t in /proc/$live/task/*; do
  tid=${t##*/}
  q=$(awk '{print $14+$15}' $t/stat 2>/dev/null)
  c=$(cat $t/comm)
  echo "$tid|$q|$c"
done
```

## Measurements

| Condition | Top thread | Box |
|---|---|---|
| no clients | ~1.8% | mostly idle |
| one RTSP client on ch0 | 26.3% (one thread) | 0% idle, 30% usr / 70% sys |
| user viewer(s) attached | 63% + 21% (two threads) | 0% idle, load ~5 |

The thread that climbs is the per-channel video worker (`start_video()` in
`main.cpp`, `VideoWorker::run`). With no clients the worker sleeps on a
condition variable (`VideoWorker.cpp`, `should_grab_frames.wait`), which is why
idle CPU is near zero. With a client attached it runs the per-frame path:

- `IMP_Encoder_PollingStream` + `IMP_Encoder_GetStream` / `ReleaseStream` (the
  encoder is hardware, via `/dev/avpu`; the wrapper lives in OpenIMP).
- NAL/slice handling (`hal::encoder::get_pack_slices`), SEI/SPS work.
- `MsgChannel` fan-out to RTSP / HTTP-MJPEG / WebSocket / recorder taps.

Kernel time dominates under load (sys ~70%). That is the encoder ioctls plus
the RTP socket writes, not userspace arithmetic. So the cost is per-frame
delivery, and it scales with the number of streams and clients, not with the
languages or the allocation churn that `prudynt-optimization-roadmap.md`
targets (though those still matter for jitter).

## Ruled out

| Path | Why not |
|---|---|
| OSD / burn-in | OpenIMP implements only OSD group/region creation; `IMP_OSD_SetRgnAttr` / `ShowRgn` / rendering are stubs, so `osd.burnin` does no per-frame work. The OSD thread sleeps 100 ms. |
| audio mic | turning the mic off drops a different thread by ~1.8%, not the worker. |
| audio output | speaker off does not move the worker. |
| WebSocket | `lws_service(context, 50)` blocks up to 50 ms per call. |
| framesource pooling | `FS(n)-tick` blocks in `select()` with a 25 ms timeout; steady-state CPU is a fraction of a percent. |
| AVPU IRQ | `WaitInterruptThread` blocks on `AL_CMD_IP_WAIT_IRQ`. |
| ISP tuning worker | `tseries_tuning_worker` sleeps 1 s per iteration. |
| module observer thread | `module_thread` waits on a semaphore. |
| RTSP accept loop | `usleep(100000)`. |
| GOT watchdog | `start_got_watchdog()` bails on non-`ET_EXEC`; the build is PIE (`ET_DYN`), so it never runs. |

## Levers

1. Fewer or smaller streams. The encoder is hardware; the CPU is the per-frame
   delivery in the worker and the kernel. Cutting fps, resolution, or the
   number of enabled streams cuts it proportionally.
2. Fewer clients per stream. `allow_shared` and the tap fan-out mean each new
   consumer costs another copy plus socket send in the same worker thread.
3. Reduce syscall pressure on the TX path: larger RTP writes (avoid one `send`
   per small NAL), and check UDP vs TCP for the clients that support it.

## Caveats

- A previous prudynt instance can stay as a zombie and keep showing in `pidof`;
  pick the live pid before profiling.
- Runtime `set<>` does not reconfigure the encoder. Bisect features with a
  restart, or with a client, not with a bare `prudyntctl json`.
- prudynt names its worker threads (`signal`, `videoN`, `jpegN`, `audio-in`,
  `audio-out`, `backchan`, `osd`, `motion`, `ws`, `rtsp`) through
  `WorkerUtils::setCurrentThreadName`, so `top -H` and `/proc/<tid>/comm` are
  self-explanatory. OpenIMP's framesource threads are already named
  `FS(n)-tick`; its AVPU IRQ and ISP tuning threads are not.
