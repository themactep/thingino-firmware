# Real-Time Scheduling for Embedded Network Services

*How a single `chrt` call cut API latency from 8 seconds to 60ms on a loaded MIPS camera.*

---

## Background

Thingino cameras run on single-core MIPS SoCs (T31, T21, T10, etc.) where the ISP firmware
and video encoder run continuously in kernel space, burning close to 100% of the available CPU.
Any user-space service competing for CPU time under the default `SCHED_OTHER` policy will be
starved for seconds at a time, even if its actual work takes only a few milliseconds.

This document describes the diagnosis and fix for the Thingino agent API suffering 8–10 second
response times, and gives general guidance for applying the same technique to other services.

---

## Symptoms

- API requests to the camera agent took 8–10 seconds to return from the hub.
- Locally on the camera (loopback), the same requests returned in under 10ms.
- `top` showed load averages of 5–6 on a single-core device, 0% idle, 75% sys.
- Camera was reachable; stream was live; no packet loss on the network.

---

## Diagnosis

### Step 1 — Isolate the layer

Timing the same endpoint through each layer showed the latency growing at the TLS proxy boundary:

| Path | Latency |
|------|---------|
| `curl http://127.0.0.1:2998/state` (inner HTTP, loopback) | 9ms |
| `curl https://localhost:1998/state` (TLS, localhost) | 6ms |
| `curl https://192.168.88.x:1998/state` (TLS, external) | 8–10s |

The data was already inside the kernel TCP receive buffer. The delay was not network or computation.

### Step 2 — Packet capture

`tcpdump` on the hub's network interface captured the full conversation:

```
t=0.000  [hub]    SYN  →  camera
t=0.041  [camera] SYN-ACK  →  hub
t=0.842  [hub]    HTTP GET /state  →  camera
t=0.843  [camera] ACK  (data received)
                   ← 2+ seconds of silence →
t=2.987  [camera] TLS response begins
```

The camera acknowledged the HTTP request at t=0.843s, then went silent for over two seconds.
The TLS proxy had the data but was not being scheduled to read and respond to it.

### Step 3 — Identify the scheduler competition

`ps` and `/proc/<pid>/status` confirmed:

- `prudynt` (video encoder): `SCHED_OTHER`, ~28% wall-clock CPU
- `isp_fw_process` (kernel ISP thread): `SCHED_OTHER`, ~70% sys time (unkillable kernel loop)
- `thingino-agent-tls-proxy`: `SCHED_OTHER` — lowest-priority process on a fully-loaded CPU

With every runnable thread at `SCHED_OTHER`, the Linux CFS scheduler distributes time based on
nice values. The ISP kernel thread and encoder had effectively run all their time slices; the TLS
proxy sat in the run queue for 2–3 seconds before getting a turn.

---

## Contributing Factors

### S99heartbeat — The CPU tax

The heartbeat init script ran `prudyntctl json -` once per second to check streamer status.
Each invocation was a `fork`+`exec`+`fork`+`exec` chain (shell → prudyntctl → streamer socket).
At 1 Hz on a loaded single-core system this consumed measurable scheduler budget and added
jitter to everything else. It was disabled as part of this investigation.

**Lesson**: Do not poll from init scripts at high frequency on embedded systems. Use inotify,
signals, sockets, or long-poll instead.

### Fork depth in the API handler

The `/state` endpoint is handled by a shell adapter script (`thingino-agent-adapter-prudynt`).
The `all` resource handler constructs a JSON document by calling ~50 subshell `$(...)` forks:

```sh
# Each $(...) is a fork+exec — 14 in this function alone
printf '"uptime_seconds":%s,' "$(thingino_agent_uptime_seconds)"
printf '"hostname":%s,'       "$(thingino_agent_json_string "$(thingino_agent_hostname)")"
printf '"streamer_running":%s,' "$(thingino_agent_prudynt_streamer_running)"
...
```

Each fork is a new process that inherits the parent's scheduling class. With `SCHED_OTHER`, each
one must wait its turn on a loaded CPU. With `SCHED_RR`, each one runs as soon as it is ready.

---

## The Fix

### One line

```sh
chrt -r -p 10 $$ 2>/dev/null || true
```

Added at the top of the TLS-mode execution path in `thingino-agentd`, before launching any
child processes.

### Why this works

`chrt -r -p 10 $$` changes the scheduling policy of the current process (the agentd shell) to
`SCHED_RR` (real-time round-robin) at priority 10.

Linux propagates scheduling class and priority through `fork()` and `execve()`. This means:

```
thingino-agentd  (SCHED_RR/10)
  └─ thingino-agentd-native  (SCHED_RR/10, inherited)
       └─ [fork per request]  (SCHED_RR/10, inherited)
            └─ thingino-agentctl  (SCHED_RR/10, inherited via exec)
                 └─ $(subshell)   (SCHED_RR/10, inherited)
                      └─ $(subshell)  (SCHED_RR/10, inherited)
  └─ thingino-agent-tls-proxy  (SCHED_RR/10, inherited)
       └─ [worker fork ×5]  (SCHED_RR/10, inherited)
```

Every process in the chain gets real-time scheduling with no extra effort. The `2>/dev/null || true`
makes the call safe on systems where `chrt` is unavailable or the caller lacks `CAP_SYS_NICE`
(the agent service drops to root which has this capability on Thingino).

### Why not `nice -n -10`?

`nice` lowers the `SCHED_OTHER` nice value, giving the process more CFS weight. This helps when
the competition is also `SCHED_OTHER`. But:

- Kernel threads (isp_fw_process) are not affected by user-space nice values.
- CFS still has minimum scheduling latency; the process can still wait hundreds of milliseconds.
- `nice -n -10` reduced /state from 8s → 3s. `SCHED_RR` reduced it to 200ms (and later 60ms).

`SCHED_RR` bypasses CFS entirely. A runnable `SCHED_RR` task preempts all `SCHED_OTHER` tasks
and runs until it blocks or its time slice expires. On a camera where responsiveness to network
requests is more important than encoder throughput, this is the right trade-off.

### Why not `SCHED_FIFO`?

`SCHED_FIFO` (non-preemptive real-time) would also work but is riskier: a runaway `SCHED_FIFO`
process can starve the entire system, including the network stack and kernel threads. `SCHED_RR`
at priority 10 gives the service real-time preemption over SCHED_OTHER tasks while still yielding
to higher-priority real-time tasks, and its time-slicing prevents any single runaway fork from
locking the system.

---

## Results

Measured from a remote host over a local Ethernet network:

| Endpoint | Before | After |
|----------|--------|-------|
| `GET /device` | 1.5s | 59ms |
| `GET /capabilities` | 1.3s | 59ms |
| `GET /state` | 8–10s | 57ms |
| TLS handshake | ~300ms | ~48ms |

The hub's `probe()` function calls all three sequentially; total probe time went from 11–13s
to under 200ms.

---

## Pairing TLS Proxy Spike

After the real-time scheduling fix, a separate pairing-time regression showed up on rebuilt
firmware with BusyBox 1.37 and the in-package TLS proxy enabled.

### Symptoms

- A hub-initiated `Pair` action could briefly pin `tls-proxy` near 100% CPU.
- `top` on the camera showed samples like:

```text
PID   PPID USER  STAT  VSZ  %VSZ CPU %CPU COMMAND
3746  3715 root  R     2020 2.1   0 94.9 /usr/libexec/thingino-agent/tls-proxy --listen 0.0.0.0 --port 1998 ...
```

- The spike happened during remote HTTPS pairing on `:1998`, not during loopback access to the
     native backend listener on `127.0.0.1:2998`.
- Pairing still often completed, but the proxy consumed far more CPU than expected on a single-core
     MIPS camera.

### Diagnosis

There turned out to be two contributing factors:

1. **Hub-side pairing confirmation was heavier than necessary.**
      The confirmation path reused the full native API probe sequence (`/device`, `/capabilities`,
      `/state`) instead of a single cheap request, and successful pairing could immediately trigger
      more follow-up API refreshes.

2. **The TLS proxy handshake loop could busy-spin.**
      In `thingino-agent-tls-event.c`, new TLS connections in handshake state were always registered
      in both the read and write `select()` sets. On a TCP socket, writability is usually ready
      immediately, so the loop could wake continuously and call `mbedtls_ssl_handshake()` again even
      when mbedTLS was returning `MBEDTLS_ERR_SSL_WANT_READ`. On a loaded single-core device this
      manifested as `tls-proxy` consuming nearly all available user-space CPU for the duration of the
      handshake burst.

### Mitigation

The validated mitigation was:

- **Reduce hub-side confirmation load**
     Change pairing confirmation to use a single lightweight `GET /device` call instead of the full
     three-request probe sequence.

- **Reduce TLS proxy worker fan-out**
     Lower the default `THINGINO_AGENT_TLS_WORKERS` from `5` to `1` for this embedded target.

- **Fix the handshake event loop**
     Track whether mbedTLS wants read or write progress and only place the socket in the matching
     `select()` set during handshake. Do not unconditionally watch both directions for every pending
     TLS handshake.

### Live Validation

After applying those changes and rebuilding the firmware:

- A controlled hub-triggered `Pair` action completed successfully.
- The camera-side monitor showed one stable external `1998` connection and one loopback proxied
     `2998` connection.
- The earlier `tls-proxy` near-100% CPU sample did not reproduce during the monitored pairing run.

### If It Reappears

1. Watch the camera during pairing with `ps`, `netstat`, and a bounded `top` sample loop.
2. Check whether `tls-proxy` is pegged during handshake or only after the connection is established.
3. Confirm how many live `1998 -> 2998` flows exist; one stable proxied flow is expected.
4. Re-check the hub confirmation path before assuming the proxy is at fault; repeated short-lived
      HTTPS connections from the hub can still amplify load on constrained hardware.

---

## General Guidance

Apply this pattern to any embedded service that must respond to network requests on a loaded
single-core system:

### 1. Use `chrt` for network-facing daemons

```sh
# In an init script or daemon launcher:
chrt -r -p 10 /usr/sbin/mydaemon --args
# or, to change priority of the current shell and inherit to children:
chrt -r -p 10 $$
exec /usr/sbin/mydaemon --args
```

### 2. Choose priority carefully

| Priority | Suitable for |
|----------|-------------|
| 1–5 | Background real-time work (logging daemons, watchdogs) |
| 10 | Network-facing services (API servers, TLS proxies) |
| 20–50 | Latency-critical control loops (motor control, sensor sampling) |
| 90–99 | Kernel driver helpers (avoid in most cases) |

Do not set network service priorities above 50; you risk starving the kernel's own real-time
threads (`ksoftirqd`, `kworker`).

### 3. Profile before assuming it's the network

A 2-second silence after a TCP ACK is almost never the network. Capture at the receiver with
`tcpdump` and look at the gap between ACK and the first response byte. If that gap is large,
the process received the data but wasn't scheduled to handle it.

### 4. Minimize fork depth in hot paths

Shell scripts are convenient but spawn a new process for every `$(...)` substitution. On a
desktop this is negligible. On a loaded MIPS camera, 50 forks × 20ms scheduling latency each
= 1 second of unnecessary waiting (even with SCHED_RR, fork overhead adds up).

For performance-critical paths, prefer:
- Reading `/proc` files directly with `read` and here-strings (no fork)
- Combining multiple `awk` queries into one invocation
- Using a compiled helper that reads all needed values in one pass

### 5. Disable polling scripts

Init scripts that run in a tight loop (heartbeat checkers, watchdogs that poll every second)
add fork+exec load that compounds the scheduler starvation problem. Replace them with:
- `inotifyd` for file changes
- Socket-based health checks (let the service answer its own health queries)
- `kill -0 $PID` with a long sleep interval (10s+) if polling is unavoidable

---

## Files Changed

| File | Change |
|------|--------|
| `package/thingino-agent/files/thingino-agentd` | Added `chrt -r -p 10 $$` before launching agent processes |
| `package/thingino-agent/files/S95thingino-agent` | Disable and stop heartbeat service on agent start |
| `hub/app/main.py` | Pairing confirmation reduced from a full probe sequence to a single `GET /device` request |
| `package/thingino-agent/files/thingino-agentd` | Reduced default `THINGINO_AGENT_TLS_WORKERS` from `5` to `1` |
| `package/thingino-agent/files/thingino-agent-tls-event.c` | Handshake loop now waits only on the socket direction requested by mbedTLS |

Commits: `9496c8d72`, `a5442b958`
