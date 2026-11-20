# lwhyper Load Balancing in Detail

> This article explains **"how a request is assigned to a certain worker, and how it falls back when something goes wrong"** — namely
> the routing and distribution mechanism of `src/core/lwhyper.pas`.
>
> Division of labor: **parameter table / command line / GUI panel / hot-update usage** are in `WHYPER_en.md`;
> this article only covers mechanisms and trade-offs. Measured data is in `BENCH_en.md` §7–§9, capacity roadmap in `SCALE_en.md`.

lwhyper is lazarusWeb's built-in **application-layer** load balancer (the counterpart of uniGUI Hyper Server):
one process hosts N business workers (multiple instances of the same business exe), listening on a single external port,
doing its own HTTP reverse proxy, session affinity, WebSocket passthrough, health probing and crash restart.

## 1. Why Load Balancing Must Be at the "Application Layer"

Ordinary HTTP is stateless, so nginx can just round-robin. lazarusWeb is not: **session state literally lives
in the LCL control tree of one worker process** (what the form currently looks like, which modal is hanging,
which row the DataSet cursor is on). If a request with the same sid lands on a different worker, that worker
knows nothing about the session and can only reply 410 to make the browser rebuild it — what the user sees is "suddenly back at the login page".

So the affinity key must be recognized. The trouble is where this key is located:

| Request type | Where the sid is | Can nginx get it? |
|---|---|---|
| AJAX calls within a page | URL query `?sid=xxx` | ❌ `$arg_sid` can only use `map`, no conditional hashing |
| Some clients / direct API | Request header `X-LW-Sid` | ❌ unless openresty/lua |
| Event frames (`POST /lw/api/event`) | **`sid` field of the JSON body** | ❌ reverse proxy doesn't look at the body |
| WebSocket `/lw/ws` | query or `X-LW-Sid` | ⚠️ needs `hash` + upgrade support |

`ip_hash` looks usable, but when a whole room of users sits behind the same NAT / same egress IP they all pile onto
one worker, making scaling pointless. Conclusion: **only a proxy that can parse query/header/body can route correctly
by sid** — that's the reason lwhyper exists, and why it fits this framework better than nginx.

## 2. Process and Port Model

```
Browser ──► lwhyper.exe :8080 (single process, the only external entry point)
           │
           ├─ main thread: accept loop; one handler thread per connection (fphttpserver tmThread)
           ├─ FMonitor: probes each worker's /lw/healthz every 2s, restarts a process if it's gone
           ├─ FUpdater: hot update (swap exe + rolling restart one by one, see WHYPER_en.md §5.2)
           │
           └─ worker pool: multiple instances of the same business exe, listening only on 127.0.0.1
              ├─ #1  :8081  business exe --port=8081 --nogui --log=worker1.log
              ├─ #2  :8082  business exe --port=8082 --nogui --log=worker2.log
              └─ #N  :808N  ...
```

- **Port planning**: worker port = `--base-port` + index, `--base-port` defaults to
  `--port + 1`. `--workers=4 --port=8080` → 8081/8082/8083/8084.
- **Workers are multiple instances of the same exe**, business code needs zero changes and doesn't know it's a worker.
  lwhyper injects at launch:
  ```
  --port=<its own port>  --nogui  [--root=..] [--theme=..]
  [--shutdown-token=<32 hex digits>]  --log=<logdir>/workerN.log  <--worker-args appended verbatim>
  ```
  `--port`/`--nogui`/`--log` are exclusively owned by lwhyper, don't write them on the business side again (duplicates collide on ports,
  see NOTES pitfall 106).
- **On Windows `poNoConsole` is used**: N workers won't each pop up a black console window.
- **No shared memory, no IPC**: workers don't communicate at all, sessions are invisible to each other. This determines
  all the later design (affinity, 410 fallback, hot update losing sessions).

## 3. The Complete Round Trip of a Request

```
Browser ──► lwhyper:8080
             │
             ├─ ① sid extraction: ?sid= → X-LW-Sid → JSON body.sid
             │
             ├─ ② own-endpoint short circuit (doesn't enter the proxy)
             │     /lw/healthz        aggregate health
             │     /lw/hyper/status   worker details
             │     /favicon.ico       root/favicon.ico, 204 if absent
             │
             ├─ ③ PickWorker(sid):
             │     hit in affinity table and that worker Alive ──► use it
             │     otherwise round-robin cursor FRR to find an Alive one
             │     none alive ──► 502 {"err":"hyper: no alive worker"}
             │
             ├─ ④ ProxyHTTP: fphttpclient forwards to 127.0.0.1:<worker port>
             │     failure ──► mark that worker dead on the spot, return 502,
             │                 then PickWorker('') to switch to another and retry once
             │
             └─ ⑤ affinity write-back: when response is 2xx bind sid to that worker
                   new session (POST /lw/api/session without sid) learns sid from the response JSON
```

### 3.1 Three-Way sid Extraction

```pascal
sid := RequestSid(ARequest);      // ?sid= first, then X-LW-Sid
if sid = '' then
  sid := BodySid(ARequest);       // application/json and body contains sid
```

`BodySid` is not a nice-to-have: event frames can send only the body without the query (server-side tests and direct
clients do this). Missing this step, such requests fall back to round-robin and get forwarded to another worker,
which replies 410 — the real front-end is unaffected because its URL always carries `?sid=`, but any body-based
client is missed by affinity (NOTES has a record of this).

### 3.2 Forwarding Details

`ProxyHTTP` is **byte moving**, no protocol rewriting:

| Item | Handling |
|---|---|
| Request headers | All passed through, stripping hop-by-hop (`Connection`/`Keep-Alive`/`TE`/`Trailer`/`Transfer-Encoding`/`Upgrade`/`Expect`) |
| `X-Forwarded-For` | Rewritten with `ARequest.RemoteAddress` (worker only trusts it with `--trust-proxy`) |
| Request body | Raw bytes into a memory stream, multipart boundaries/binary untouched; no parsing, no re-encoding |
| Response headers | Passed through, stripping hop-by-hop + `server`/`date`/`content-type`/`content-length` (these are generated by the response object itself) |
| Response body | Memory stream handed to the response object, automatically freed by `FreeContentStream` |
| 204/304/empty body | Reply empty content directly, no stream attached |
| Timeouts | `ConnectTimeout=1000`, `IOTimeout=30000` |

The `ConnectTimeout` line is written specifically for Windows: fphttpclient treats
"connection refused" as a timeout; with the default value **every request hitting a dead worker would waste 3 seconds**.
Local forwarding connects take milliseconds, so 1 second is plenty, and a dead worker can be identified immediately.

### 3.3 Retry Semantics: At Most Once

```
ProxyHTTP(idx) fails → that worker Alive=False (removed on the spot, no wait for next probe)
                     → PickWorker('') to switch → ProxyHTTP retries once
```

Retry only once, because: **POST/event frames are not idempotent**, unlimited retries would re-execute business logic when "the worker actually processed it but the reply was lost".
One retry covers the most common transient failure "process just died" without amplifying the risk of duplicate submission. If both attempts fail, hand 502 to the browser (the front-end
handles 502 by prompting + retrying, not silently).

## 4. Session Affinity

### 4.1 Data Structure

`FMap: TStringList` (`sid → worker index`, index stored in `Objects`),
protected by an `FMapLock`. Choosing `TStringList` over a hash table: the session scale is "hundreds to thousands",
and `IndexOf`'s linear lookup is nanoseconds at that magnitude, while `Sorted + Find` requires maintaining order and
concurrent inserts are more troublesome. Switch when it really reaches tens of thousands of sessions.

### 4.2 Binding Timing

```pascal
if (AResponse.Code div 100) = 2 then      // only accept 2xx
  if sid <> '' then BindSid(sid, idx)
  else if p = '/lw/api/session' then BindSid(LearnSessionSid(AResponse), idx);
```

Three design points:

1. **Bind only 2xx**. 502 (worker down) / 410 (session not on this worker) / 500 (business exception)
   must not overwrite the binding, otherwise one failure would permanently pin the session to the wrong worker.
2. **New sessions are "learned"**. The browser's first `POST /lw/api/session` carries no sid; the sid is
   generated by the worker and placed in the response JSON. lwhyper reads the response stream (after reading, resets `Position`
   to zero and sends it verbatim to the browser), extracts the `sid` and binds it to that worker. **Without learning,
   the new session's next request would go round-robin to another worker and get a direct 410**.
3. **Rebinding allowed**. When the same sid again lands on a different worker with 2xx (`BindSid` overwrites
   the old value) it means the session really migrated there (typical case: the front-end reused the old sid string after the session was rebuilt),
   and the latest fact wins.

### 4.3 Unbinding Timing

| Scenario | Action | Reason |
|---|---|---|
| Worker process exits abnormally | `ClearWorkerSids(i)` clears all of that worker's entries | Sessions vanished with the process; keeping them only routes requests to a dead end |
| Proactive restart (hot update/manual) | Same, clear before restarting | Same, and avoid new requests landing during the restart window |
| lwhyper itself restarts | The whole table disappears | No persistence, see §7 |

Clear rather than "migrate": a session is an in-process LCL control tree, **it can't be moved**. After clearing, when these sids
request again they go round-robin; whichever worker they land on will reply 410 because it can't find the session, and the browser
rebuilds the session and returns to the login page via the framework's existing chain — this is a designed fallback, not a failure.

### 4.4 Fallback on a Miss

`PickWorker`'s complete logic (by priority):

```
1. sid non-empty → look up table
     hit and FWorkers[idx].Alive      → return idx (affinity)
     hit but worker is dead           → fall to 2
2. round-robin: starting at FRR, try at most N times, take the first Alive one
3. all dead → -1 → upper layer returns 502
```

Note the `tries < Length(FWorkers)` in step 2: **at most one cycle**. If written as
`while True`, it would become a busy loop when everything is dead; one cycle is enough to judge "nobody can take it".

## 5. Assignment Algorithm: Round-Robin + Skip Dead

**New sessions** (no sid / unknown sid) are assigned round-robin, with the cursor `FRR` globally incremented modulo N.
Reasons for not choosing "least connections" or "least sessions":

- The session count (`sessions`) is an **observation sampled by the probe every 2 seconds**; using it as a scheduling basis means
  up to 2 seconds of decision latency, and sampling jitter would cause jittery migrations;
- More importantly, **affinity already determines that assignment happens only at the "new session" instant**, and thereafter the whole session
  lifetime stays on the same worker. This kind of "one-time decision" most needs **even distribution** rather than
  "real-time load balancing"; round-robin is the optimal approximation of even distribution (and needs no extra state);
- The real source of imbalance isn't the algorithm, it's **session lifetime**: one worker has 3 long-polling
  sessions hanging while another has only ones that leave in tens of seconds, so session counts are naturally uneven — unrelated to the algorithm.

Dead workers are skipped using the `Alive` flag, which is maintained jointly by the monitor thread and the forwarding-failure path.

## 6. Failure Detection and Self-Healing

### 6.1 Probes

- Every `POLL_MS = 2000ms` one probe round, hitting `GET /lw/healthz` on each worker;
- Probe `IOTimeout = 3000ms`: **a hung worker must not hold up the whole probe round**;
- The worker-side `/lw/healthz` is a pure in-memory read (no session creation, no disk access), returning
  `{ok, sessions, ...}`;
- Only `ok=true` counts as alive; `sessions` is also cached on that worker's record,
  and reported in aggregate by `/lw/healthz` and `/lw/hyper/status`.

### 6.2 Warm-Up Gate (BootGuard)

A restarted worker has a dangerous window: the process is up and `/lw/healthz` responds, but page initialization
(first form construction, data source connection) hasn't finished. Sending traffic in at this point gives users several seconds of slow requests
or even timeouts. So **after restart `BootGuard := 2`**: only after two consecutive probe rounds (about 4 seconds) pass is `Alive`
set true and the worker re-opened to traffic. The first startup is unaffected (`BootGuard=0`), otherwise a cold start would waste 4 seconds.

### 6.3 Two Independent Failure Paths

| Path | Trigger | Effect |
|---|---|---|
| Slow path | Probe finds `not ok` or process gone | `Alive=False`, clear sid table and restart the process (`Restarts+1`) |
| Fast path | connect/IO error during forwarding | `Alive=False` **on the spot**, return 502 and switch worker to retry |

The fast path is necessary: the probe interval is 2 seconds, during which every request stuck to a dead worker would hit it again;
marking it dead on the spot lets the next `PickWorker` skip it immediately.

### 6.4 Protection for Concurrent Start/Stop

Now **two threads** Kill/Launch the same set of `TProcess` objects: the monitor thread (crash restart) and
the hot-update thread (rolling version swap). So:

- `FWorkerLock`: all start/stop and reads of `Proc` are inside the lock (`Proc` may be
  `Free`d by the other party; reading `Proc.Running` raw would AV);
- `FUpdating`: during a version swap the monitor thread **only probes, doesn't interfere with start/stop** — otherwise both sides
  Launching at once would create duplicate processes and port contention.

## 7. Single-Point Semantics: When lwhyper Itself Goes Down

This must be spelled out, because it's the easiest thing to overlook when choosing:

- **lwhyper is a single process on a single machine**; if it goes down, everything is unavailable externally (workers are still alive but nobody forwards);
- **Restarting it loses the `sid → worker` table**: all in-flight sessions become "unknown sid"; after round-robin forwarding the
  worker replies 410 and the browser returns to the login page. In other words **restarting lwhyper ≈ all users log in again**;
- Its restart is much more costly than a worker restart. Therefore: **for operations like changing `--worker-args` or changing the worker
  count, use hot update rather than restarting lwhyper** (hot update only loses sessions on the swapped worker).

To truly achieve high availability, you need another layer in front of lwhyper (see §9), and must guarantee **the same sid
always lands on the same lwhyper** — because the sid table is in lwhyper's memory. This can't be done with a pure HTTP reverse proxy
(it also can't get the sid from the body); in practice you rely on L4 four-tuple affinity or simply a shared entry point. So the framework's positioning is:
**squeeze all cores on a single machine**, not cross-machine high availability.

## 8. WebSocket Passthrough

`/lw/ws` is a long-lived connection; you can't just "forward one request and be done" as with HTTP. What lwhyper does is
**bidirectional passthrough at the TCP level** — the handshake is also completed at the worker; it only moves bytes:

```
Browser ──GET /lw/ws?sid=.. Upgrade──► lwhyper
                                      │
                                      ├─ ① PickWorker(sid): hit in affinity table → use it; all dead → 502
                                      ├─ ② rebuild the handshake request to the worker (Host rewritten to 127.0.0.1:port)
                                      ├─ ③ read the worker's 101 response headers, forward verbatim to the browser
                                      └─ ④ bidirectional pumps (8KB each), teardown when either end disconnects

Afterwards: Browser ◄── frame bytes ──► worker (lwhyper only moves bytes, doesn't change the protocol)
```

Key points:

- **The handshake must be completed by the worker**: `Sec-WebSocket-Accept` is computed by the worker using the key;
  if lwhyper recomputed it, it would have to implement the protocol all over again and handle subprotocol negotiation;
- **Affinity is also by sid** (query or `X-LW-Sid`), otherwise WS connects to A while HTTP lands on B,
  and the sessions don't match;
- **One WS exclusively occupies one connection thread** (3.3.1 uses the connection-upgrade mechanism, 3.2.2 takes over synchronously in the request callback until the tunnel ends) — this is an inherent cost of WS, related to tuning `MaxLiveConnectionCount`
  and `QueueSize` (BENCH_en §5);
- The teardown order `shutdown → pump thread wakes → single close in destructor` must not be disturbed:
  `TSocketStream.Close` is not idempotent; a repeated close, after the handle is reused by the OS, may close someone else's
  connection by mistake. Observe with `wsopen` (current count, should return to 0) / `wsdone` (cumulative teardowns).

## 9. Division of Labor Between Layers

```
Public network
 └─► nginx / Caddy (optional): TLS termination, static resources, rate limiting, multi-machine entry
     └─► lwhyper: sid affinity + worker pool + probes + hot update
         │    (the same sid must land on the same lwhyper — the sid table is in its memory)
         └─► worker × N: business service (LCL control tree + sessions), plaintext HTTP / 127.0.0.1
```

- **HTTP scenarios don't need nginx**: lwhyper has built-in `--ssl`, TLS is terminated only at this layer
  (workers use plaintext, local loopback, doesn't leave the NIC);
- **Scenarios that need nginx**: multi-machine entry, gzip/caching static resources, centralized rate limiting, unified certificate management.
  In that case nginx should **not** do `ip_hash` or round-robin — it only hands traffic to some lwhyper,
  affinity is guaranteed by lwhyper's internal sid table (prerequisite: the same sid goes to the same machine, see §7);
- **Don't share the sid table between two lwhyper instances** — it's not implemented and not planned (see §11).

## 10. Capacity and Tuning

| Knob | Default | Description |
|---|---|---|
| `--workers=N` | 2 | Recommend starting at ≈ physical cores / 2, tune by measurement; each worker is a full business process (independent DB connection pool, independent form memory) |
| `QueueSize` | 128 | fphttpserver's accept queue; when 503 appears at 40+ concurrent, look here first (BENCH_en §5) |
| Thread mode | One thread per connection | WS and long polling occupy threads long-term; pure AJAX scenarios cycle threads quickly |
| `--worker-args="--patch=1"` | — | Incremental patch, 156 events/sec per session vs 63; throughput gain far exceeds any scheduling optimization |
| `--verbose` | off | One log line per request, troubleshooting only (I/O significantly affects throughput) |

Rules of thumb (`BENCH_en.md` §7–§9, gallery demo, 4C8T):

- Single worker ≈ 160 events/sec (`--patch=1`);
- 8-way concurrent against 2 workers ≈ 151 events/sec;
- 503 starts appearing above 40 concurrent — the bottleneck is lwhyper's own accept threads and the workers'
  LCL gate, not the scheduling algorithm. **Add workers first, then add a front-end reverse proxy to offload static resources**.

**The real ceiling is usually not CPU but database writes**: N workers means N writers,
sqlite's single writer gives `database is locked`; multi-process + sqlite writes must first switch to WAL or
a server-class database (see `SCALE_en.md` §1).

## 11. Observation and Troubleshooting

### 11.1 `/lw/hyper/status` Field by Field

```json
{
  "ok": true,
  "listen": 8080,          // lwhyper listening port
  "exe": "C:/app/MyApp.exe",
  "hotupdate": true,       // whether hot update is enabled
  "updating": false,       // whether a rolling version swap is in progress
  "updates": 3,            // cumulative successful version swaps
  "workers": [
    {"n":1,"port":8081,"pid":19828,"alive":true,
     "sessions":7,"restarts":0,"updates":3}
  ],
  "sticky": 12,            // number of sid→worker entries (≈ online sessions, aggregated across workers)
  "wsopen": 2,             // WS tunnels currently being passed through, should return to 0 normally
  "wsdone": 481,           // cumulative tunnels cleanly torn down
  "heap": 12345678         // current FPC heap usage (bytes)
}
```

### 11.2 Symptom → Cause

| Symptom | Most likely cause | Fix |
|---|---|---|
| `alive:false` but pid still there | Probe 3-second timeout: worker stuck in a long transaction/infinite loop, LCL gate not released | Check that worker's log; restart the worker if necessary |
| `sticky` much larger than Σ`sessions` | Entries not cleaned (worker died without clearing / session expired without unbinding) | Restarting that worker clears its entries; if it keeps growing, check the `ClearWorkerSids` call path |
| `wsopen` monotonically rising | WS tunnel teardown leak (one leaked per connection) | Reproduce with `tests/t_ws_churn.py`, check whether `heap` rises in sync |
| Session randomly returns to login page | Affinity missed: sid not extracted (sid in body? custom client?) | Enable `--verbose` to see whether `sid=` is empty |
| Lots of 503 at 40+ concurrent | accept queue / thread count maxed out | Add `--workers`, tune `QueueSize`, add a front-end reverse proxy |
| Every request slow by 3 seconds | Hit a dead worker and `ConnectTimeout` not in effect (old version) | Confirm `ConnectTimeout=1000` in the code |
| Worker restarts infinitely, log shows `Binding of socket failed` | `--port` collides with lwhyper's listening port (pitfall 106) | Check the `[hyper] launch #N ... args=` line |

### 11.3 Regression Tests

```bash
# End-to-end: healthz / details / affinity / crash restart / 410 fallback / byte-level response comparison
python tests/t_hyper.py

# Concurrent load test: affinity check + long-polling interference + QPS/P50/P95/P99 (exit code 0 = all passed)
python tests/t_hyper_load.py --port=8099 --clients=32 --rounds=8

# WebSocket tunnel (handshake passthrough + bidirectional round trip)
python tests/t_hyper_ws.py

# Repeated WS connect/disconnect to verify no leak (check wsopen returns to 0, heap stable)
python tests/t_ws_churn.py
```

## 12. Known Boundaries (Must Know When Choosing)

1. **Sessions live in the worker process memory**: a worker restart/version swap = sessions on that worker are lost.
   Not a bug, but the direct cost of the decision "no external session store like Redis" — serializing the
   LCL control tree + hanging modals out would cost far more than the benefit.
2. **Restarting lwhyper loses the sid table**: all users return to the login page (§7). Use hot update rather than restarting it when possible.
3. **Request bodies pass entirely through memory**: uploading large files incurs one full memory copy (`ProxyHTTP` uses
   `TMemoryStream` as an intermediary), so leave memory headroom for concurrent large-file uploads.
4. **Schedules only, doesn't queue**: lwhyper does no request queuing, rate limiting, or circuit breaking; on overload it relies on
   503/502 returned directly to the client. Do rate limiting at the front-end reverse proxy.
5. **Single machine**: cross-machine is not its goal (§7/§9); for multiple machines use an outer LB + guarantee the same sid on the same machine.
6. **Hot update only swaps the exe itself**: DLL/resource files in the same directory aren't handled (see `WHYPER_en.md` §5.2).

## 13. Code Map (`src/core/lwhyper.pas`)

| Concern | Function/Class |
|---|---|
| Request entry, WS takeover in 3.2.2 | `TLWHyperServer.HandleRequest` |
| Master routing gate (own endpoint → pick worker → proxy → affinity) | `TLWHyperServer.Route` |
| sid extraction | `RequestSid` / `BodySid` |
| Pick worker (affinity + round-robin + skip dead) | `TLWHyperServer.PickWorker` |
| Affinity table maintenance | `BindSid` / `ClearWorkerSids` / `LearnSessionSid` |
| Forwarding (headers/body/timeouts/mark dead on failure) | `TLWHyperServer.ProxyHTTP` |
| Probe | `ProbeWorkerHealth` / `TLWHyperMonitor.Execute` |
| Start/stop and graceful shutdown | `TLWWorker.Launch` / `Kill` / `ShutdownWorker` / `RelaunchWorker` |
| WS passthrough | `WSHandlesUpgrade` / `WSTunnel` / `TLWWSTunnel` / `TLWWSPump` |
| Observation | `ApiHealth` / `StatusJSON` |
| Hot update | `TLWHyperUpdater` (see `WHYPER_en.md` §5.1–§5.2) |
