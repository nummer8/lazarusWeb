# lazarusWeb Features & Highlights

> Version 0.9.6 · 2026-11-18
>
> **One sentence**: Move Lazarus/FPC desktop applications to the browser by changing only the base class; the controls are still real
> LCL controls, business logic always stays on the server, and the frontend requires zero build and zero external network dependencies.
>
> This document answers three questions: **what it is, where it is strong, and where its boundaries are**. For mechanism details, see
> `ARCHITECTURE.md` / `HOW_IT_WORKS.md`; for usage, see `MANUAL.md`; for an item-by-item comparison with uniGUI,
> see `COMPARISON_unigui.md`.
>
> Note on figures: numbers marked "measured" come from local stress tests/real-browser regressions; the control and DB matrices are
> automatically generated snapshots (dates are marked); volatile numbers such as lines of code and script counts are marked "as of 2026-11-18".

---

## 0. At a Glance

The original desktop application (forms, events, and `.lfm` files all unchanged):

```pascal
TMainForm = class(TLWForm)   // originally class(TForm)
```

Change the build target:

```
lazbuild -B --ws=nogui MyApp.lpi
```

Open `http://127.0.0.1:8090/` in a browser — that is your application.

**It is not "compiling Pascal to JS", nor "rewriting everything with a frontend framework".** It gives LCL
a "display adapter without a screen" (the nogui widgetset), lets the real control tree run on the server,
then serializes the control tree into JSON, which the browser renders into corresponding DOM.

---

## 1. Trade-offs of Three Approaches

| Approach | Cost | Result |
|---|---|---|
| Rewrite frontend with Vue/React + REST backend | Business logic rewritten, desktop code discarded, two states to synchronize | Best frontend experience, existing assets discarded |
| uniGUI-style commercial framework (Delphi) | Commercial license; controls are "shadow classes" rather than real `TForm`; limited designer capabilities; tied to the Delphi ecosystem | Mature, but locks the project into another commercial stack |
| **Real LCL control tree + server-authoritative rendering (this approach)** | Must handle every implicit assumption LCL makes about "having a screen" (cost is on the framework side, not the business side) | **100% Pascal business reuse; MIT; same source code on Windows/Linux/macOS** |

All the benefits of this approach (zero business changes, designer works as usual, RTTI naturally available) and all the troubles
(fake GDI, DPI, nogui crash points) come from the same decision: **use real LCL controls, not
shadow controls**. The framework has already absorbed these troubles into 32 core units such as `lwws.pas`
(23,037 lines as of 2026-11-18).

---

## 2. Features: Eleven Practical Capabilities

### 2.1 Migration Cost: One Base Class, Plus an Automated Conversion Pipeline

- Change `class(TForm)` to `class(TLWForm)` in business forms; `.lfm`, event methods, properties,
  anchors, and `TabOrder` all remain unchanged;
- Existing projects can be **automatically converted** with `tools/lwconvert.exe`: change the base class, rewrite `.lpr`
  startup code, regenerate `.lpi` (nogui target), and output a per-control support report;
  end-to-end regression is in `tests/t_convert.py`;
- New projects have an IDE wizard: after installing the design-time package `lwdesign`, **File → New → Project**
  gains one `lazarusWeb` template with three dialogs: (1/3) normal application / **service (daemon) mode**,
  (2/3) `lazarusWeb project` (GUI debug build) / `lazarusWeb project(nogui)` (deployment build),
  (3/3) normal / plugin template. Service mode additionally generates `uDaemon.pas` / `uMapper.pas` / `lazarusWeb.ini`
  so the same exe can also be registered as a Windows service (see `WINDOWS_SERVICE_en.md`);
  save timing matches Lazarus's built-in templates (virtual project first, written to disk only on Ctrl+S),
  and the saved project includes `build.bat/build.sh/favicon.ico` and `lw/` frontend resources;
- Also included: **New Form** (`TLWForm`), a `lazarusWeb` page in the component palette,
  and a Tools menu item "generate one `<form name>.html` skeleton from the current .lfm; choose window or flat mode first".

> Why this matters most: the real cost of webification is never "can it run", but "does it require a rewrite".
> Here the rewrite is 1 line (add one `uses`).

### 2.2 Real Controls, Real Designer: What You See at Design Time Is What You See in the Browser

`TLWForm` is a **true `TForm` descendant**, not a proxy class or wrapper. So in the IDE:

- A `TButton`/`TEdit` dragged onto it is LCL's own control; the property panel, event page,
  alignment tools, and anchor editor all work as usual;
- `.lfm` loads unchanged, and the layout in the form designer **is** the layout in the browser (same coordinate system).

By contrast, shadow-control systems can only provide something that "looks like a designer"; third-party controls,
custom controls, and runtime-created controls all hit walls. There is no such wall here — **any
LCL control placed on it is genuinely running on the server**.

### 2.3 Server Authority: Business Code and State Never Enter the Browser

The browser receives only two things: **JSON control tree snapshots** and **event triples `{id, ev, val}`**.
Control instances, business state, SQL, permission checks, and session data all live in server memory.

This yields three practical benefits:

1. **Source code and rules are not delivered downstream**. The frontend cannot see your Pascal, SQL, or business branches
   — a natural weakness of the "rewrite the frontend" approach, and a hard requirement in government/enterprise/intranet scenarios;
2. **No "two states"**. There is no frontend store that can disagree with a backend model,
   and no REST API needs to be designed;
3. **Multi-client consistency**. Desktop, mobile, and explicitly shared tabs see mirrors of the same tree,
   without relying on frontend/backend synchronization protocols.

The cost must also be stated clearly: **every interaction is a server round trip** (latency and throughput see 2.8),
and the browser cannot work offline.

### 2.4 Desktop Semantics Are Complete, Not Merely "Able to Display"

This is where many webification approaches truly fall apart, and here each item is matched:

| Desktop semantics | How it is handled here |
|---|---|
| Synchronous modal `if f.ShowModal = mrOk then` | Push instruction, then **suspend the request thread** (`TEvent.WaitFor`); continue only when the browser closes the window; business code unchanged |
| `ShowMessage` / `MessageDlg` / `InputQuery` / `QuestionDlg` / `Application.MessageBox` | Redirected at runtime to browser modal dialogs, **without changing a single line of code** (`lwdlg`, attached to `lwcore`) |
| `TOpenDialog` / `TSaveDialog` | Browser file picker → upload to session temp directory; `FileName` gives the server path; `TFileStream` can read it directly |
| Accelerator keys (`&` in Caption) | Rendered as underlined letters per LCL rules; `&&` is a literal `&` |
| `TStatusBar` panels / `TLWDBGrid` multi-level headers | Drawn according to `.lfm` panel widths, alignment, and header grouping |
| High-DPI design (`DesignTimePPI=120/144`) | Normalized to 96 DPI at creation (geometry + fonts together), matching desktop appearance |
| `TLabeledEdit` label fitting | Server-side positioning + browser refinement based on actual rendered rectangle; spacing equals `LabelSpacing` |

### 2.5 Extremely Simple Delivery: Alpine.js by Default, Zero Build, Zero External Network

- The default rendering layer is `lw-alpine.js` + `alpine.min.js` + `lw-alpine.css`,
  **three static files bundled with the package** (45KB + 215KB + 59KB), no CDN, no
  node/npm/bundler required;
- Ext JS is an **optional** rendering layer (`--client=ext` + your own `ext-<version>/`);
  both layers share the same JSON protocol, the same events, and the same push channel — switching rendering layers does not change business code;
- Deployment is: exe + a few static files. Runtime does not depend on any framework installation
  (the only optional dependencies are `sqlite3.dll` and OpenSSL DLLs for HTTPS);
- **7 color schemes + follow system**: light schemes `light`/`paper`/`mint`/`contrast`,
  dark schemes `dark`/`midnight`/`forest`; switchable from the title bar button, remembered in `localStorage`,
  and settable at design time via the form property `LWTheme`;
- Site icon, `favicon.ico`, HTTPS self-signed certificate, and INI configuration all work out of the box.

### 2.6 Full-Stack Capabilities Out of the Box, No Need to Assemble Wheels Yourself

| Capability | Ready-made component |
|---|---|
| Upload | `TLWFileUpload`: progress percentage, `Filter`/`Multiple`/`MaxSizeKB`, filename sanitization, saved to `%TEMP%\lw_uploads\<session>\<control>\` (changeable via `TargetFolder`) |
| Download | `SendFile` / `SendText` (optional BOM); URLs **do not expose server paths** (one-time token, expires after 30 minutes or first use) |
| Camera | `TLWCamera`: mobile directly invokes the **system camera** (works over LAN http); desktop uses `getUserMedia` in-page preview; automatically uploads and previews locally after capture |
| Database | `TLWDBGrid` (paging/filtering/summary/multi-level headers/cell editing) + `TDBEdit`/`TDBMemo`/`TDBCheckBox`/`TDBListBox`/`TDBRadioGroup`/`TDBLookup*`/`TDBText`/`TDBImage`/`TLWDBNavigator` |
| Reporting | `lwreport`: printable HTML (A4 `@page`, repeating `thead`, total rows), CSV (BOM), XLSX (real OOXML, built-in zipper, no third-party library dependency) |
| Charts | `TLWChart` → built-in SVG rendering (bar/line/pie), automatically recolors with theme |
| Login & permissions | `TLWLoginForm` (designable, `RequireAuth`, rejects all events when unauthenticated) + `TLWCaptcha` (self-drawn dot-matrix PNG, zero font dependency) + `TLWSideMenu` (design-time is the IDE's native menu editor) |
| Interaction feedback | Toast, global busy overlay, tooltips, client APIs `LW.theme`/`LW.layout`/`LW.stats`/`LW.resync` |
| Third-party integration | `TLWApp.AddAjax('items/price', handler)` registers custom endpoints; third-party JS can directly `fetch('/lw/ajax/...')`; add `--ajax-cors` for cross-origin |
| Rich content | `TLWHTMLFrame` (HTML: TStrings), `TLWPDFFrame` (iframe + view token) |

### 2.7 Mobile: Zero Business Changes, Optional Templates

- Detection is entirely frontend: viewport ≤834px enters mobile, ≥1100px exits (hysteresis prevents jitter);
  touch capability is detected separately; the server never knows what the device is;
- **Works without templates**: desktop keeps design-time absolute layout; mobile enters "pan mode"
  (design size unchanged, font size not scaled, whole page scrollable);
- **With a template, a background decoration layer**: a single `<root>\tpl\<form name>.html`; its header
  `lw-tpl-mode:window|flat` selects a movable/resizable window or a full-page flat view (flat wins if both
  markers appear). Templates **do not reflow controls** — controls keep their design-time `Left/Top` absolute
  positions, with events, Alpine state and incremental patches untouched; changes take effect on refresh;
- IDE Tools menu **generates one file** from `.lfm`: choose window or flat first, then get one `<form name>.html`
  with a mode marker, design-coordinate list and self-check report.

### 2.8 Performance Is Measured, Not "Theoretically Fast"

| Fact | Number (Ryzen 5 7520U / 4C8T / 15.3GB, gallery demo) |
|---|---|
| Full payload per event | 73–78KB (157 nodes) |
| With incremental patches (`--patch=1`) | **2–4KB** (1/30–1/70) |
| Server cost per event | 6.3ms → **4.3ms** |
| Single-process event throughput | 57.9 → **150–163 events/sec** |
| Idle sessions | **200+** without crashing (about 1MB/session, 2 threads/session) |
| Horizontal scaling | N workers ≈ N × 150 events/sec |

Even more valuable is that **the optimization process itself is documented** (`SCALE.md`): the framework tried "node signatures + node
caching", measured it as a loss (signature ≈ 60% of rebuild cost; cache hits did not pay off), and deleted it; profiling found the real bottleneck
was not "reading properties", but `TLWDBGrid` computing cell text for rows that were not sent downstream — fixing that yielded far more benefit than adding caching.
**Documentation willing to say "tried it, did not help, removed it" is more credible than numbers that only report successes.**

### 2.9 Clustering & Operations: A Built-in "Hyper Server" Layer

- **`lwhyper` dedicated load balancer**: one process launches N workers (multiple instances of the same exe),
  automatic restart on crash via a 2-second probe, single external port reverse proxy, **application-layer stickiness** by sid,
  TCP-level WebSocket passthrough, built-in `/lw/healthz` and `/lw/hyper/status`;
- **Hot update (zero-downtime version switch)**: copy the new exe to `<business exe>.new`; after about 4 seconds of validation,
  swap and **rolling-restart one by one** (at least N-1 serving at any moment); if the new version fails to start, automatically
  roll back and keep `.bad-<time>`; workers exit gracefully (`POST /lw/shutdown` + token), not killed;
- **Two HTTPS paths**: `--ssl` directly (built into FPC; self-signed if no certificate supplied), or
  nginx/Caddy front termination (ready-made configs in `deploy/`, including `Upgrade` headers and `ip_hash`);
- **GUI server panel**: menu, scrolling logs, online session count/uptime, system tray resident
  (clicking X only hides), comparable to the uniGUI standalone server window; console version for CI/containers;
- Behind a reverse proxy, add `--trust-proxy` so logs show real client IPs.

### 2.10 Cross-Platform, Including Domestic Hardware Environments

- The same source code runs on Windows / Linux / macOS: core units contain no platform-specific units such as `Windows`, `winsock`,
  or `ShellExecute`; differences are isolated with `{$IFDEF MSWINDOWS/LCLGTK2/LCLQT5}` and all have non-Windows branches;
- Measured cross-compilation: **x86_64-linux**, **mips64el-linux (actually run on Loongson 3A)**;
  the repository also contains aarch64 artifacts;
- The same source supports both **FPC 3.2.2 and 3.3.1**: new capabilities are wrapped with capability detection + dual branches;
  under 3.2.2 equivalent shims are used (self-implemented `LWCanRead`, bundled status code table, etc.), with consistent behavior.

### 2.11 Engineering Credibility: Inspectable, Runnable, Reproducible

| Dimension | Status (as of 2026-11-18) |
|---|---|
| Control support | `CONTROL_MATRIX.md` is **auto-generated** by `tools/lwaudit`: 66 visual controls are **actually created + attached to a form + serialized once**; snapshot 49 ok (74.2%); since then 6 high-frequency placeholders have been upgraded to ok (list in README roadmap) |
| DB controls | `DB_AWARE_MATRIX.md` generated by `tools/lwdbcheck`: 12 data-aware controls attached to a real SQLite dataset, verifying binding/display/synchronization/value changes/serialization/frontend branches item by item (details: 9 complete + 3 read-only; the summary line at the top of the file is still the old number before the `TDBNavigator` fix) |
| Automated tests | 87 Python scripts in `tests/` (including fixtures/tools), of which **23 are HTTP-level regressions** (controls/db/dialog/files/login/multitab/ws/hyper_ws/patch_e2e…, hundreds of assertions) + **55 CDP real-browser probes** (connect to headless Edge, check first paint/screenshots/console errors) |
| Documentation | `README` + `docs/*.md` totaling **about 13,000 lines**; `NOTES.md` is an append-only record (numbering through pitfall 194, 153 entries recorded, with gaps; overturned conclusions carry strikethroughs and pointers) |
| Examples | 20 demos: hello, grid, multi, db, dbaware, files, dialogs, login, gallery (13 pages, 60+ controls, including the report page), mobile_demo… |
| License | This project is MIT; Alpine.js (MIT) is bundled with license notice; **Ext JS is not bundled** (license compliance is the user's responsibility; README states this plainly) |

> One passage worth calling out separately: `NOTES.md` records not "what I did", but "what went wrong,
> why it went wrong, how it was found, and what the lesson was". Records like pitfall 172 — "my previous fix broke saving" —
> are kept as-is. **This kind of documentation is the signal of long-term maintainability.**

---

## 3. Highlights: Seven Decisions Done Right

### 3.1 Use the nogui Widgetset as a "Virtual Display" Instead of Rewriting Controls

This saves the work of rewriting hundreds of controls; the cost is supplying LCL with a set of "fake GDI":
`CreateCompatibleDC` returns a constant, `GetTextExtentPoint32` estimates as `character count × font height × 0.55`,
and the virtual display is fixed at 96 DPI.

**The cost must be stated honestly**: this estimation uses an average character-width coefficient for Western text; Chinese/full-width characters are actually about 1.0× the font height, so **`AutoSize` labels containing Chinese may be computed too narrow on the server**.
The framework therefore insists that "layout is authoritative at design-time coordinates and does not rely on server-side reflow" — which is also why
web layout cannot be left to server-side calculation.

### 3.2 Whitelist Serialization, Not Full RTTI Dump

`lwwriter` outputs properties according to a mapping table, rather than reflecting over all published properties of a control.
Benefits: small and stable payloads, frontend recognizes only known fields, internal implementation details are not leaked to the browser;
cost: new controls/new properties require explicit mapping additions (`MAPPING.md` is that table).

### 3.3 Reconcile by ID, Not Redraw

When a new tree arrives, diff by node id; unchanged DOM instances stay in place — input focus, cursor position,
and scrollbar position are not interrupted (this is what "full-page redraw" approaches most easily destroy). Incremental patches
(`--patch=1`) push this idea further: the server returns only changed ops.

### 3.4 Events Over WebSocket, Pushes Over Long-Polling Cursors

Responsibilities are cleanly separated:

- **Events** (click/input) need low-latency bidirectional communication → use WS frames when connected; automatically fall back to
  `POST /lw/api/event` when disconnected;
- **Pushes** (modal/message box/overlay/download instructions) need "each tab gets its own" → all enter the session
  queue with sequence numbers; each tab uses `/lw/api/poll?after=N` to get its own cursor, without consuming each other's messages.

### 3.5 Templates = Background Layer, Not String Re-rendering

Window/flat templates are decoration layers mounted in front of the form client area (`pointer-events:none`);
control DOM nodes are neither relocated into placeholders nor rebuilt. Event bindings, Alpine state and
incremental patch mechanisms **are completely unaffected** — this is the premise for "works when configured, falls back when not".

### 3.6 Session Lifecycle Designed as "Closing the Tab Means Exit"

By default sid is stored in `sessionStorage`: refresh does not lose login, **closing the tab requires logging in again** —
the same mental model as a desktop application where "closing the window = exit".

The details are carefully handled: browser "restore last opened pages" restores sessionStorage along with sid,
so the client leaves a tombstone on `pagehide` and uses `performance.timeOrigin` minus the tombstone time
to determine "is this a refresh or was the window closed" (threshold 3 seconds). For "remember me", explicitly enable
`localStorage['lw.persist'] = '1'`.

### 3.7 Dual FPC Versions from a Single Source, Not Two Branches

3.3.1's new capabilities (`RegisterUpdateHandler`/`ThreadMode`/`ConnectionHandler`…)
are wrapped with `{$IF FPC_FULLVERSION >= 30301}`, and equivalent shims are used under 3.2.2. Merging is not
"copy one and modify it", but a five-layer audit of **symbol level + literal level + conditional expansion + compilation + regression**
(`MERGE_AUDIT.md` / `MERGE_AUDIT_FULL.md`).

---

## 4. Numbers at a Glance

| Item | Number | Basis |
|---|---|---|
| Server core | 32 units / 23,037 lines | As of 2026-11-18, `src/core` |
| Default rendering layer | `lw-alpine.js` 215KB + `lw-alpine.css` 59KB + `alpine.min.js` 45KB | File sizes |
| Optional Ext layer | `lw.js` 154KB + `lw.css` 9KB + your own `ext-<version>/` | File sizes |
| Visual control audit | 66 controls, 49 ok (74.2%) | Snapshot 2026-11-09; 6 added since |
| Data-aware controls | 12: 9 fully usable + 3 read-only | Detail snapshot 2026-11-08 |
| Event throughput | 150–163 events/sec/process (`--patch=1`) | Local measurement |
| Event payload | 73–78KB → 2–4KB (patches) | Local measurement |
| Idle sessions | 200+ (about 1MB/session) | Local measurement |
| Mobile breakpoints | ≤834px enter / ≥1100px exit (hysteresis) | Design parameters |
| Modal timeout | 180 seconds | Constant `LW_MODAL_TIMEOUT_MS` |
| Color schemes | 7 + follow system | Alpine layer |
| Test scripts | 87 (23 HTTP-level + 55 CDP browser probes) | As of 2026-11-18 |
| Documentation | About 13,000 lines; `NOTES.md` numbering through pitfall 194 (153 entries recorded) | Reviewed 2026-11-20 |
| Examples | 20 demos (including mobile_demo) | Reviewed 2026-11-20 |

---

## 5. Comparison with uniGUI (Selected)

For the complete item-by-item comparison, see `COMPARISON_unigui.md` (including 🟡/❌ gaps).

| Dimension | uniGUI | lazarusWeb |
|---|---|---|
| Control system | Shadow controls (not real `TForm`) | **Real LCL controls**; `TForm` base class changed directly |
| Migration cost | Must switch to uni control family | Change 1 base class line; existing projects can use `lwconvert` for automated conversion |
| Frontend delivery | Depends on Ext JS (commercial license) | **Alpine.js built in by default**, zero external network; Ext optional |
| License | Commercial license | **MIT** (Alpine MIT bundled; Ext not bundled) |
| Synchronous modal / dialog redirection | Yes | Yes, and `TOpenDialog`/`TSaveDialog` are also connected |
| Reporting/export | uniPrint / uniGridExcelExport | `lwreport`: printable HTML / CSV / XLSX (real OOXML) |
| Clustering | Commercial Hyper Server | **Open-source equivalent `lwhyper`** + hot update + health probes |
| Cross-tab sharing | No | **Yes** (sid reuse + cursor push + targeted dialogs, optionally enabled) |
| Mobile | Separate `uniMobile` control family | Frontend responsive + form templates (no separate control family) |
| Cross-platform | Mainly Windows | **Windows / Linux / macOS, including measured Loongson mips64el** |
| Multilingual RTL | Supported | Not implemented |

**Conclusion**: uniGUI is more mature, has more controls, and offers commercial support; lazarusWeb's advantages are
**open source, real controls, cross-platform, zero frontend build**, and a migration path where "business code does not change a single line".

---

## 6. Boundaries: When Not to Use It

This section is as important as the highlights — **selection failures mostly come from "using it in the wrong place", not from "the thing being bad"**.

- **Not for high-concurrency internet frontends**. The comfort zone is 10–20 active users per process (40 upper limit);
  for more, run more workers and scale horizontally. For public-facing flash sales/feed homepages, use conventional frontend/backend separation;
- **Not suitable for millisecond-level interaction**. Every interaction is a server round trip (4–6ms computation + network);
  drawing boards, games, and real-time collaborative editing are not suitable;
- **Sessions live in process memory**. If a process crashes, sessions on that worker are lost (external Redis not implemented);
  `lwhyper` stickiness + `410` automatic rebuild provide fallback;
- **Not implemented**: RTL/multilingual; no separate mobile control family. (`TSplitter` dragging is now supported, pit 186)
  Right-click context menus (`TPopupMenu`), dashboard gauges, color picker, and
  `TProgressBar`/`TTrackBar` write-back are all supported (see 2.4 / 2.6);
- **nogui text measurement is estimation**. Interfaces that rely heavily on `AutoSize` for precise layout must be reviewed;
  Chinese labels may be too narrow;
- **One session can have only one modal at a time**; other requests in the same session queue during the modal
  (consistent with desktop modal semantics);
- **The frontend is still custom JS** (Alpine layer 215KB). For business developers it is "zero JS",
  but the statement "the framework has zero JS" is not true; do not say that externally.

---

## 7. Five-Minute Self-Proof

No need to listen to an introduction; run a few ready-made examples to judge whether it fits:

```bat
:: 1) Build all demos (--ws=nogui)
build.bat

:: 2) Full-featured gallery: 13 pages, 60+ controls; standard controls/grid (save/load + unsaved-close prompt)/chart/upload/dialog/DB paging/report all included
demos\gallery\gallery_nogui-x86_64-win64.exe --port=8090

:: 3) Data-aware full set + report center (87 objects laid out on one page)
demos\dbaware\dbaware.exe --port=8110

:: 4) Mobile: open the address shown on the LAN: line in the banner with your phone browser (remember the port)
demos\mobile_demo\mobile_demo.exe --port=8106

:: 5) Clustering and hot update
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\dbaware\dbaware.exe
```

Automated regression (automatically starts/stops the server):

```bat
python tests\run_with_server.py demos\gallery\gallery_nogui-x86_64-win64.exe tests\t_gallery.py
python tests\run_with_server.py demos\dialogs\dlgdemo.exe tests\t_dialog.py
```

---

## 8. Further Reading

| To learn about | Read |
|---|---|
| Architecture and module responsibilities | `ARCHITECTURE.md` |
| The complete loop of one click; why full RTTI dump is not used | `HOW_IT_WORKS.md` |
| Getting started and development guide | `MANUAL.md` (usage + development) |
| Control/property mapping details | `MAPPING.md` + `CONTROL_MATRIX.md` |
| Performance and capacity | `BENCH.md` (measured) → `SCALE.md` (optimization roadmap) |
| Load balancing and hot update | `WHYPER.md` → `LOADBALANCE.md` |
| Mobile principles and measurements | `MOBILE.md` |
| Pitfalls encountered (numbering through 194, 153 entries recorded) | `NOTES.md` |
| Troubleshooting methodology | `DEBUGGING.md` |
| Deployment (HTTPS/reverse proxy/systemd) | `deploy/README.md` |
| Find documentation by scenario | `INDEX.md` |