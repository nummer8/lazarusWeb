# lwhyper Usage Guide

lwhyper is lazarusWeb's dedicated load balancer (the counterpart of uniGUI Hyper Server): a single process
hosts N business workers, listening on a single external port, with a built-in HTTP reverse proxy + sid session affinity +
WebSocket TCP passthrough. For HTTP scenarios **nginx is no longer needed**; for HTTPS just add
`--ssl` to lwhyper (FPC has built-in TLS, workers still communicate over HTTP, see `NOTES.md` pitfall 160).

- Console version: `tools\lwhyper.exe` (script/service deployment)
- GUI version: `tools\lwhyper_gui.exe` (double-click to use, no black console window)

> This article is the **usage guide**: parameters, CLI/GUI, own endpoints, hot-update usage and implementation, troubleshooting.
> The **distribution mechanism** (why application-layer affinity is needed, how the sid table is maintained, routing/skipping dead workers/warm-up gate,
> WebSocket passthrough, single point of failure boundaries) is in `LOADBALANCE_en.md`.

## 1. Architecture Overview

```
                    ┌─ worker #1  business exe --port=8091 --nogui --log=worker1.log
Browser ──► lwhyper ─┼─ worker #2  business exe --port=8092 --nogui --log=worker2.log
  :8080             └─ worker #N  ...
        │
        ├ HTTP reverse proxy (forwards by sid affinity)
        ├ WebSocket TCP passthrough (ws://:8080 → worker's ws port)
        ├ healthz probing + automatic crash restart (with warm-up gate)
        ├ /lw/healthz, /lw/hyper/status  two own endpoints
        └ hot update: swap in new-version exe + rolling restart one by one (see §5.1/§5.2)
```

Key semantics:

- **Workers are multiple instances of the same business exe**: `--port`, `--nogui`, `--log` are injected by lwhyper,
  the business exe doesn't need to know whether it is a worker;
- **Sessions live in the worker process memory**: a worker restart = all sessions on that worker are lost;
- **Restarting lwhyper loses the sid→worker table**: requests with an unknown sid fall back to round-robin forwarding (the client
  automatically rebuilds the session);
- **Affinity takes sid from three places**: URL `?sid=` → `X-LW-Sid` header → the `sid` field of the JSON body
  (for why application-layer affinity is mandatory and the full mechanism of routing/skipping dead/failover, see `LOADBALANCE_en.md`);
- **Version changes don't interrupt service**: when a new version of the business exe is released it is automatically replaced in a rolling fashion, with at least N-1
  workers serving at any moment (see §5.1, implementation in §5.2).

## 2. Quick Start (Console Version)

```bash
cd C:\lazarusWeb
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos/gallery/gallery.exe --worker-args="--patch=1"
```

Open `http://127.0.0.1:8080/` in a browser. Verify:

```bash
curl --noproxy '*' http://127.0.0.1:8080/lw/healthz
curl --noproxy '*' http://127.0.0.1:8080/lw/hyper/status
```

> ⚠️ When testing locally, curl must include `--noproxy '*'`: if the environment variable `HTTP_PROXY` points to a local
> proxy, requests to port 8080 will be hijacked elsewhere (returning "upstream connect failed").

## 3. Command-Line Parameters

| Parameter | Default | Description |
|---|---|---|
| `--port=N` | 8080 | Port lwhyper listens on externally |
| `--workers=N` | 2 | Number of worker processes |
| `--exe=path` | (required) | Business executable; no extension on Linux/macOS |
| `--base-port=N` | port+1 | Port of the first worker, then +1 sequentially |
| `--root=path` | — | Forwarded to the worker as `--root=` (project root, containing default rendering resources such as `src/client/alpine.min.js`; `ext-<version>/` is needed only for the optional Ext layer) |
| `--theme=name` | — | Forwarded to the worker as `--theme=` |
| `--worker-args="..."` | — | **Appended verbatim** to the worker command line, multiple arguments separated by spaces |
| `--logdir=directory` | `<TEMP>\lwhyper` | Worker log directory (worker1.log…) |
| `--hot-update` | **on** | Hot update: watches for new-version files of the business exe, swaps the shell then restarts workers one by one (see §5.1). Does nothing when there is no new-version file |
| `--no-hot-update` | — | Turn off hot update |
| `--update-dir=directory` | — | Drop directory for new versions (place a file with the **same name** as the business exe here); by default looks for `<business exe>.new` |
| `--verbose` | off | Print every proxied request |
| `--ssl` | off | **Enable HTTPS (built into FPC)**: terminated only at the outer layer, workers still use plaintext; self-signed certificates work with zero configuration |
| `--ssl-host=name` | — | Certificate hostname (the domain/IP the browser visits, must match the certificate SAN; leave empty to auto-generate a self-signed certificate) |
| `--ssl-cert=file` / `--ssl-key=file` | — | Specify PEM certificate and private key, must be given as a pair; relative paths are based on the `lwhyper.exe` directory |
| `--help` | — | Help |

`--ssl` requires shipping `libssl-3-x64.dll` + `libcrypto-3-x64.dll` (placed in the same
directory as `lwhyper.exe`). The Listen / Status / Health addresses in the startup banner automatically display as `https://`.

How to use a non-self-signed certificate from a formal CA / private CA:

```bash
lwhyper.exe --port=8443 --ssl --ssl-host=app.example.com ^
  --ssl-cert=cert\app.example.com.pem --ssl-key=cert\app.example.com.key
```

`--ssl-host` is not the listening port, nor the Windows computer name; the client must access it using a name
from the certificate SAN, e.g. `https://app.example.com:8443/`. For LAN IP/private CA
certificate generation and full instructions see `deploy/README.md` §1.1. In a cluster, HTTPS is
terminated only at the outer lwhyper layer; workers still use plaintext.

Workers also automatically get `--nogui` (no server-side panel pops up) and `--log=<logdir>\workerN.log`.

### 3.1 `--worker-args` in Detail (Important)

`--worker-args` is the lwhyper → worker **parameter pass-through channel**: its contents are appended verbatim
to the end of each worker's command line (space-separated, multiple arguments allowed). After receiving them, the worker processes them according to
the standard argument parsing in `src/core/lwapp.pas` — that is, **every parameter the business exe supports when run standalone
can be obtained by the worker through it**.

**Most common: `--patch=1` (incremental patch, strongly recommended)**

```bash
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos/gallery/gallery.exe ^
  --worker-args="--patch=1"
```

- The worker serializes form state and diffs it against the last snapshot, **returning only the changed ops for each event**,
  rather than the whole form tree;
- Effect: 156 events/sec per session vs 63 events/sec for full, payload 1.5KB vs 71KB
  (97% traffic reduction, BENCH_en §7/§8);
- Compatibility: when an older front-end rendering layer doesn't support the incremental protocol, it **automatically falls back to full**, functionality isn't broken,
  it just misses the benefit — so it's safe to leave on all the time;
- Troubleshooting tip: "fell back to full N times" in the pipe_bench output means the client didn't have incremental capability at that time,
  not that the worker errored.

**Other worker parameters that can be passed through** (same as worker `--help`):

| Parameter | Description | Typical scenario |
|---|---|---|
| `--config=path` | Specify the business ini; by default automatically finds `<exe name>.ini` in the exe's directory | Switching between multiple configuration sets |
| `--root=path` | Project root directory (default Alpine resources in `src/client/`; `ext-<version>/` needed only for optional Ext); can also be forwarded via lwhyper's `--root=` | Deployment directory is not in the default location |
| `--form=Name` | Default form name (the form presented when opening the home page) | One exe with multiple entry points |
| `--client=alpine\|ext` | Browser rendering layer: `alpine` is the default (built-in); `ext` is optional and requires your own ext directory; when unspecified, auto-detection prefers alpine | Debugging rendering layer differences |
| `--ext=x.x.x` / `--extdir=directory` | Ext version / ext-js directory | Multiple Ext versions coexisting |
| `--theme=crisp` | classic/crisp/gray/material/neptune/graphite, overridable via URL `?theme=` | Can also be forwarded via lwhyper's `--theme=` |
| `--title=title` | Browser tab title | Branding customization |
| `--timeout=20` | Session idle timeout (minutes) | Increase for long-running attended businesses |
| `--verbose` | Worker prints every request (into workerN.log) | Troubleshooting |
| `--ajax-cors` | `/lw/ajax/*` returns CORS headers | Third-party sites directly calling ajax |
| `--trust-proxy` | Behind an nginx/Caddy reverse proxy, take X-Forwarded-For as the client IP | HTTPS front-end reverse proxy scenario |

Note that `--port`, `--nogui`, `--log` are **injected** by lwhyper; don't write them into
`--worker-args` again (doing so conflicts/duplicates with the injected values).

**Combination examples**:

```bash
# Production: incremental patch + real IP behind reverse proxy + 60-minute sessions
tools\lwhyper.exe --port=8080 --workers=4 --exe=demos\gallery\gallery.exe ^
  --worker-args="--patch=1 --trust-proxy --timeout=60"

# Troubleshooting: worker logs every request
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\gallery\gallery.exe ^
  --worker-args="--patch=1 --verbose"

# GUI version: write the same content in extra= of lwhyper_gui.cfg
#   extra=--patch=1 --trust-proxy --timeout=60
```

**Escaping and notes**:

- In cmd.exe wrap the whole string in double quotes: `--worker-args="--patch=1 --verbose"`; in bash
  use double quotes as well;
- Separate multiple arguments with spaces, no commas/semicolons;
- Historical pitfall 106 (`--port` being erased when appending arguments, worker colliding on 8090 and restarting infinitely) has been fixed;
  the first step in troubleshooting is always to look at the `[hyper] launch #N ... args=...` log line to verify the command line
  the worker actually received;
- Each change to `--worker-args` takes effect only after restarting lwhyper (the worker command line is fixed at launch time).

## 4. GUI Version (lwhyper_gui.exe)

The configuration is always placed in the **exe directory**: `tools\lwhyper_gui.cfg` (deployed alongside the exe, intuitive to inspect):

```ini
[hyper]
exe=C:\lazarusWeb\demos\gallery\gallery.exe
port=8080
workers=2
baseport=0
root=
theme=
logdir=
extra=--patch=1
autostart=0
hotupdate=1
ssl=0
sslhost=
sslcert=
sslkey=
```

**HTTPS**: a new row has been added to the panel's "Configuration" area with an `Enable HTTPS (TLS)` checkbox + certificate hostname +
PEM certificate / private key (each with a "Browse..." button). Check the checkbox to start HTTPS with a self-signed certificate;
leaving both PEM fields empty means self-signed; to specify your own certificate, both fields must be filled **at the same time** (filling only one will be
blocked when you click "Start", reporting "certificate and private key must be specified together"), and the files must exist.
After checking it, the "Open Browser" button and status bar address automatically change to `https://`. The PEM certificate and private key
are placed together in the `cert\` directory at the same level as the exe; both "Browse..." buttons open from that directory by default.

For "Certificate hostname" enter the domain or IP from the browser address bar, which must match the certificate SAN (e.g.
`app.example.com` or `192.168.1.90`); it is not the listening address. With a formal CA certificate,
fill in the certificate domain; with an internal private CA, fill in the IP/internal domain from the certificate. It can be left empty when using only self-signed.
For OpenSSL generation and startup examples of non-self-signed certificates see `deploy/README.md` §1.1.

The corresponding cfg keys (one-to-one with the UI; UI changes are written back automatically; below is an HTTPS example,
for daily HTTP keep `ssl=0` and the three certificate fields empty):

```ini
ssl=1
sslhost=app.example.com     ; domain/IP in the certificate SAN; empty = auto-generate self-signed certificate
sslcert=C:/app/cert/cert.pem ; specified as a pair with sslkey; both empty means use self-signed
sslkey=C:/app/cert/key.pem
```

Likewise, `libssl-3-x64.dll` + `libcrypto-3-x64.dll` must be shipped (placed in the exe's directory).
The GUI version and console version share `src/core/lwhyper.pas`; TLS is terminated only at the outer lwhyper layer,
workers still use HTTP between themselves.

- `extra` is equivalent to the console version's `--worker-args`;
- `autostart=1`: automatically clicks "Start" on launch, bringing up the service (for headless deployment/CI smoke tests);
- The UI log window shows the startup banner and errors; each worker writes its own log file;
- The GUI version and console version share the same core code (src/core/lwhyper.pas), with measured throughput/latency
  completely identical (BENCH_en §8), so it can be confidently used as the daily deployment entry point.

## 5. Own Endpoints

| Endpoint | Purpose |
|---|---|
| `/lw/healthz` | Aggregate health: `{ ok, role:"hyper", workers, alive, sessions, uptime }`, usable directly as an LB/k8s probe |
| `/lw/hyper/status` | Worker details: port/pid/alive/session count/restart count; plus `wsopen` (number of WS tunnels currently being passed through, must return to 0 when teardown is correct)/`wsdone` (cumulative clean teardowns)/`heap` (current FPC heap usage) — to investigate "object leaked per connection", first check whether `wsopen` is monotonically increasing (pitfall 122). Hot-update related fields: `hotupdate` (whether enabled), `updating` (whether a version swap is in progress), `updates` (cumulative successful version swaps, each worker also has one) |

On the worker side there is another endpoint that **exists only when launched by lwhyper**:

| Endpoint | Purpose |
|---|---|
| `POST /lw/shutdown` | Graceful shutdown. Accepts only loopback addresses + an `X-LW-Shutdown` header equal to the token; the token is randomly generated by lwhyper at startup and injected into the worker command line via `--shutdown-token=`. When not injected, this path doesn't exist at all |

## 5.1 Hot Update (Zero-Downtime Version Swap)

**What it does**: when a new version of the business exe is released, put the new file in place and lwhyper automatically switches the N workers
to the new version one by one — at least N-1 workers are serving externally at any moment, the browser doesn't need to refresh,
sessions don't need to be rebuilt (only sessions on the swapped worker are lost, an inherent cost of in-process sessions).

**Key fact on Windows**: a running exe cannot be overwritten, but it **can be renamed**. So
the shell swap is a "two-step rename":

```
hello.exe  --rename-->  hello.exe.old-<time>     (each worker process keeps running the already-mapped old image)
hello.exe.new --rename--> hello.exe              (shell swap complete, this step has zero downtime)
worker #1 stop -> start (load new image) -> ready
worker #2 stop -> start (load new image) -> ready
```

Throughout, only each worker's own restart window swaps images; the listening port (lwhyper) keeps accepting requests.

**How to use**:

```bash
# 1) Wait for lwhyper to come up (hot update is on by default, the banner prints the watched file)
tools\lwhyper.exe --port=8080 --workers=2 --exe=C:\app\MyApp.exe

# 2) Compile to a temporary name, then rename and drop it in place (direct overwrite fails to link on Windows)
#    Output MyApp.exe.new when recompiling, or compile elsewhere then copy as .new
copy /y C:\build\MyApp.exe C:\app\MyApp.exe.new

# 3) The rest happens automatically; watch the log:
#    [hyper] hot-update found new version: MyApp.exe.new (12345678 bytes)
#    [hyper] hot-update swapped in new exe (old version kept as MyApp.exe.old-20261117-185510), starting rolling restart one by one
#    [hyper] hot-update worker #1 is running the new version
#    [hyper] hot-update worker #2 is running the new version
#    [hyper] hot-update complete: all 2 workers switched to the new version
```

To use a separate drop directory (such as mounting a CI artifacts directory): `--update-dir=D:\drop`, just put a file
with the **same name as the business exe** into `D:\drop\` (not a `.new` suffix).

**Settling check**: a file counts as "fully written" only if its size and modification time stay unchanged for two consecutive probes (about 4 seconds) and it can be opened
exclusively — a half-written file being copied/linked won't be swapped in.

**Graceful shutdown**: stopping a worker for a version swap follows the worker's own shutdown flow, not a forced kill:

```
lwhyper --POST /lw/shutdown--> worker (with token header)
worker: reply 200 -> close listener -> drop residual connections -> release sessions -> process exits
lwhyper: wait for process exit (max 10 seconds) -> start new version
```

The line `[lw] /lw/shutdown accepted, gracefully shutting down` in the worker log means this path was taken.
In-flight requests can finish, logs can be flushed, and the framework's own teardown cleanup can run.

- This endpoint requires the worker to be **recompiled with a core that includes this feature** (the `ShutdownToken` newly added in `src/core/lwhttp.pas`).
  Old workers don't have this endpoint, lwhyper will get 403/404 and automatically fall back to a forced kill — functionality is unaffected, just without graceful teardown;
- Security design: the endpoint exists only when lwhyper injected a token (ordinary applications don't have it), it accepts only loopback addresses,
  and the token is placed in a custom header rather than the URL (browser pages cannot add custom headers cross-origin, so clicking a malicious link can't shut down your service).

**Automatic rollback on failure**: if a worker fails to come up after switching to the new version (missing DLL, crashes on startup,
not ready within 30 seconds), the whole thing rolls back to the old version and all already-swapped workers are restarted back to the old version:

```
[hyper] hot-update failed to start new version: EProcess: Failed to execute, rolling back
[hyper] hot-update rolled back to old version, bad version kept as MyApp.exe.bad-20261117-185630
```

The bad exe is deliberately kept (`.bad-<time>`) for later verification; the old-version backup (`.old-<time>`) is
deleted automatically on success; if it can't be deleted (still mapped by a process), it's kept and a note is logged.

**Observation**: `updating` (version swap in progress) and `updates` (success count) in `/lw/hyper/status`;
the GUI version's log window displays these lines in sync. To temporarily turn off hot update: add
`--no-hot-update` to the console version, or write `hotupdate=0` in `lwhyper_gui.cfg` for the GUI version.

**Boundaries**:

- Sessions live in the worker process memory — sessions on the swapped worker are lost (the browser automatically
  rebuilds and returns to the login page); the whole service isn't interrupted but that's not "lossless sessions";
- Only the exe itself is swapped; DLL/resource files in the same directory aren't handled; if there are extra dependencies, swap them together with the exe,
  or switch to whole-directory deployment + restart;
- During a version swap the monitor thread doesn't interfere with worker start/stop (exclusively owned by the update thread); if **another**
  worker crashes at this time, it won't be brought back up until the current swap round finishes (window up to about 30 seconds).

## 5.2 Hot Update Implementation Mechanism (Internal)

The previous section explained "how to use"; this section explains "what actually happens behind the scenes". Skip it if you only care about the release process.

### 5.2.1 Threads and Coordination

There are two background threads inside the lwhyper process, both touching the same set of workers:

```
TLWHyperUpdater (polls the watched path every 2s)
  └─ settling check → shell swap → restart workers one by one

TLWHyperMonitor (probes each worker's /lw/healthz every 2s)
  └─ maintains Alive / sessions; restarts a process if it's gone
```

Both threads Kill/Launch the same set of workers, so three protections are needed:

| Mechanism | Effect |
|---|---|
| `FWorkerLock` | All start/stop and reads of `Proc` are inside the lock (`Proc` may be `Free`d by the other party; reading `Running` raw would AV) |
| `FUpdating` | During a version swap, the monitor thread **only checks, doesn't act**: no more Kill/Launch, avoiding duplicate process launches and port contention |
| Wait for port outside the lock | stop → wait for port release (≤5s) → start, where the "wait" is done outside the lock so the monitor thread isn't held up here |

Cost: if a worker crashes on its own during a version swap, it won't be brought up until the current swap round finishes (window ≈ one
swap round, usually a few seconds). This is a deliberate trade-off — to keep the swap flow from being disrupted by concurrent start/stop.

### 5.2.2 Candidate Settling: Why Not "Swap as Soon as Seen"

A file being copied/linked is half-written; swapping it in would bring down the whole cluster. So three conditions must hold simultaneously:

1. The file exists;
2. **Size + modification time unchanged for two consecutive probes (≈4 seconds)**;
3. Can be **opened exclusively** with `fmShareExclusive` — a file being written can't get an exclusive handle.

If any condition fails, the counter is reset. The extra 4 seconds buys "a half-written compiler/copy tool output won't be
mistaken for a new version". If the same file failed to swap last time (exe occupied, etc.), remember its size and
timestamp, and **retry only when the file changes** — otherwise the same error would be spammed into the log every 4 seconds.

### 5.2.3 Shell Swap: Two-Step Rename

```
exe          --rename-->  exe.old-<time>    ① old image steps aside; running workers keep running their already-mapped copy
new          --rename-->  exe              ② new file in place; this step stops no processes
```

- **No byte-by-byte copy**: copying an exe that is being executed is slow and error-prone; a same-volume rename is atomic.
  When a cross-volume rename fails, `LWMoveFile` automatically degrades to "copy + delete source".
- **The exe path briefly doesn't exist between the two steps** (microseconds). Normally, if the monitor thread restarted a worker at this moment
  the `Launch` would fail — but during a version swap the monitor doesn't interfere with start/stop (§5.2.1), so this window is closed.
- If ① fails (old exe occupied) → give up immediately, don't touch any file; if ② fails → **rename ① back**,
  and the cluster keeps running the old version. Neither branch leaves the cluster in a state of "exe gone, all workers dead".

### 5.2.4 Rolling: Swap One Worker at a Time

```
for i := 0 to N-1:
    ClearWorkerSids(i)                 // sessions vanish with the process; unbind first, don't route requests to it
    Alive[i] := False                  // immediately remove from the routing pool (don't wait for the next probe)
    graceful shutdown (POST /lw/shutdown) → wait for process exit (≤10s) → force-kill if still alive
    wait for port release (≤5s)
    Launch(i) load new image; BootGuard := 2   // warm-up gate: only re-open to traffic after two consecutive probes
    wait for Alive[i] to become true (≤30s)
        process absent for 6s straight (missing DLL, crash on init) → fail immediately, don't wait the full 30s
```

At any moment only 1 worker is in the restart window, the other N-1 serve normally. With `--workers=1` this
degrades to "brief 502 for the whole site" — a single worker has no redundancy, which is inevitable, not a bug.

**Why we must wait for it to be ready before touching the next one**: restarting all N at once equals a full site outage; and if the new version is bad,
all workers go down simultaneously, leaving no foothold for rollback. Serial rolling guarantees "even in the worst case there's still a batch of
workers running a usable version".

### 5.2.5 Failure Rollback

Trigger conditions (any one):

| Condition | Typical cause |
|---|---|
| Not ready within 30 seconds | Extremely slow startup, stuck in initialization |
| Process disappears within 6 seconds of starting | Missing DLL, bad config, crash on startup |
| `Launch` throws an exception directly | File is not a valid PE at all (text masquerading as exe, etc.) |

Rollback actions:

```
exe → exe.bad-<time>        // keep bad version for later diff / forensics
old → exe                   // restore old version
workers 0..i all restart to old version   // already-swapped ones must also revert (they're running the bad version)
```

- **The bad version is deliberately not deleted**: `<exe>.bad-<time>` is kept for verification and can be deleted after manual confirmation;
- Restarts during rollback may also fail — a single failure doesn't abort the flow, the rest is left to the monitor as a fallback;
- After a successful swap the old `.old-<time>` is deleted automatically; if it can't be deleted (still mapped by a process), it's kept and noted in the log,
  and can be cleaned up manually later.

### 5.2.6 Timing Parameters at a Glance

| Parameter | Value | Meaning |
|---|---|---|
| `HU_POLL_MS` | 2000ms | New-version file polling interval |
| Settling rounds | 2 rounds (≈4s) | Size + time unchanged, and can be opened exclusively |
| `HU_READY_MS` | 30000ms | Upper limit for waiting for a single worker to be ready after swap |
| Startup-exit detection | Process absent for 6s straight | Fail early, no need to wait the full 30s |
| Graceful shutdown wait | 10000ms | Wait for the process to exit on its own after `POST /lw/shutdown` |
| Port release wait | 5000ms | Confirm the old process has released the listening port before restart |
| Probe interval | 2000ms | `BootGuard=2` means "two consecutive rounds" (≈4s) |

Rough estimate: a single worker's swap window ≈ 1–2 seconds (restart + two probe rounds); measured with `--workers=2`
a whole round from dropping the file to all-ready is about 6 seconds (including the 4-second settling check).

### 5.2.7 Graceful Shutdown: The Worker-Side Chain

Hot update stops a worker by **letting it exit on its own**, not by force-killing it (`TProcess.Terminate` on Windows
kills outright: in-flight requests are cut off midway, log buffers are lost, and the framework's own teardown is all skipped):

```
1) lwhyper → worker: POST /lw/shutdown with header X-LW-Shutdown: <token> (source must be loopback)
2) worker validates three gates → sets stop flag, replies 200 (shutdown action handed to the watchdog thread)
3) watchdog thread Stop: close listener → wait for in-flight connections to finish (≤3s) → flush logs → process exits
4) lwhyper waits for process exit (≤10s); if not exited → force-kill fallback
```

- The request callback only sets the flag + replies 200; **the actual shutdown is done in another thread**: calling
  `Stop` directly in the request thread would tear down the very connection being answered, so the client wouldn't get 200 and would be misjudged as "refusing to exit";
- The token is randomly generated on each start (32 hex digits) and exists only in lwhyper memory and the worker command line;
- The token is placed in a **custom header** rather than the URL: browser pages can't add custom headers cross-origin, so a malicious link can't shut down the service;
- **Old workers (cores without this feature) reply 403/404**, lwhyper logs a line and falls back to a force-kill —
  no functional degradation, just without graceful teardown.

### 5.2.8 Operations Runbook

**Standard release**

```bash
# 1) Compile to a temporary name (don't overwrite directly in the location lwhyper watches)
lazbuild -B --ws=nogui MyApp.lpi

# 2) Drop it in (.new is the default watched name; move is fastest on the same partition)
copy /y MyApp.exe C:\app\MyApp.exe.new

# 3) Confirm: updating goes from true back to false, updates increments, and each worker's updates also +1
curl --noproxy '*' http://127.0.0.1:8080/lw/hyper/status
```

**Emergency rollback** (automatic rollback didn't trigger, but the new version has a business problem)

Just copy the last known-good exe to `.new` and drop it again — hot update treats it the same and will roll once more.
So **keeping the previous version's exe before releasing** is a hard requirement (or take it directly from the build artifacts).

**Temporary disable**

```bash
lwhyper ... --no-hot-update        # console version
# GUI version: hotupdate=0 in lwhyper_gui.cfg (unchecking in the panel has the same effect)
```

Once turned off, a `.new` left in place won't be processed (no accidental swap, no error).

**CI integration** (use the artifacts directory directly as the drop directory; the file name must be the same as the business exe)

```bash
lwhyper ... --update-dir=D:\build\out
```

**Note**: choose either `--update-dir` or `<exe>.new`; the watched path **must not be the exe itself**
(otherwise the running image would be swapped in as a new version) — this case is explicitly blocked in code; at startup it prints
`[hyper] hot-update disabled: watched path is the same as the business exe` and stops watching.

## 6. Monitoring and Self-Healing

- Probe: each worker is checked via its `/lw/healthz`, IO timeout 3 seconds (the probe won't be held up by a hung worker);
- Crash restart: when a worker exits abnormally, clear the sid table entries stuck to it and restart, logging
  `[hyper] worker #N (port) exited abnormally, restarting (attempt X)`;
- **Warm-up gate**: a restarted worker must pass 2 consecutive probe rounds before traffic is sent to it again
  (early after restart the process is still starting, don't rush requests to it); the first startup is unaffected;
- A not-ready worker is marked dead by the probe, and the proxy returns 502 for it;
- Shutdown: lwhyper receives an exit signal → closes the listener (≤250ms) → kills all workers, with the full process
  recorded in the log directory.

## 7. Logging

- **lwhyper's own log**: printed to the console (in the GUI version it goes to the log window); the GUI version also writes a copy to
  `<logdir>\hyper.log`; worker startup line format:
  `[hyper] launch #N port=XXXX exe=... args=...` (the first step in troubleshooting is to look at this line to verify the
  command line the worker received);
- **Worker logs**: `<logdir>\workerN.log`, only request lines and session events (the startup banner goes to
  the backlog/console, not here), flushed line by line.

## 8. Performance and Capacity (see BENCH_en §7/§8)

- Single-worker ceiling ≈ 160 events/sec (gallery demo, 4C8T); 2 workers with 4 sessions measured 225/sec;
- **Recommended `--workers` = physical cores / 2**, beyond that returns diminish (CPU is the bottleneck, not the architecture);
- `--patch=1` (incremental patch) 156/sec per session vs 63/sec for full, 97% traffic reduction, **strongly recommended**;
- Usable with p50 < 300ms within 20 concurrent; p95 over 1s from 40 concurrent; 80 concurrent triggers
  the `MaxLiveConnectionCount=128` 503 flood (503 comes from the active-connection limit,
  `QueueSize=64` is an earlier listen backlog, exceeding it rejects the connection outright without a 503,
  see BENCH_en §5) — add more workers or put a front-end buffer in place.

## 9. Troubleshooting Quick Reference (see NOTES pitfalls 106/107/108 for details)

| Symptom | Cause | Fix |
|---|---|---|
| Worker restarts infinitely, `Binding of socket failed: 8090` | `--port` erased when `--worker-args` appends arguments (pitfall 106, fixed) | Upgrade to a version with the pitfall 106 fix; check the `[hyper] launch` line to verify args |
| Worker throws FPImageException then becomes unresponsive | Exception dialog minefield on the headless widgetset, original exception swallowed (pitfall 107) | Three-layer fix is built in (OnException takeover / WriteControl degradation / DDL one-time); check `unhandled` lines in the worker log for the real culprit |
| Process "exits right after startup", no crash record | Terminal tool's Job Object kills the process tree when the command ends (pitfall 108, a test-environment artifact) | Start long-running services via a background task/system service; real user terminals are unaffected |
| curl requests hijacked to another service | Environment variable HTTP_PROXY points to a local proxy | Add `--noproxy '*'` to curl |
| Lots of 503 above 40 concurrent | fphttpserver MaxLiveConnectionCount=128 (active connection limit) flood | Add more workers; or put nginx/Caddy in front as a buffer |
