# Plugin Feasibility Analysis: Extending Pages by Dynamically Loading DLL/SO

> Conclusion first: **"Page extension" can be done with plugins, but do not take the path of "bare DLL exporting form classes".**
> Under FPC, the DLL and the EXE each carry their own copy of the RTL, and class identity is inevitably broken — tests show
> that even `o is TObject` on the host side is `FALSE`. And lazarusWeb's rendering and event dispatch contain
> **182 lines with `is T...` checks** (`lwdispatch.pas` 72 lines + `lwwriter.pas` 110 lines);
> once broken, controls can be displayed but will not dispatch events or serialize — a "silent failure" rather than an error.
>
> Recommended order: **source-code plugin directory (already implemented) → process-level plugins (when released independently) →
> Lazarus Runtime Package (only when object trees must be mixed on the same page)**.
> Phase 0 has been implemented and passed regression at both the nogui and GUI tiers (`plugins/` + `tools/lwplugins.py` +
> `demos/plugindemo` + `tests/t_plugin.py`), see §5.

## 1. First, break "page extension" down into three granularities

Different granularities have completely different requirements for "class identity consistency", which is the dividing line for technology selection.

| Granularity | Typical need | Requires cross-module shared class identity |
|---|---|---|
| A. Add a standalone page | Add an "Order Management" form, entered through an independent URL | **No** (only need to register the form name) |
| B. Embed new controls in a page | New LCL control class that must participate in event dispatch and HTML serialization | **Mandatory** |
| C. Extend existing page behavior | Add `/lw/ajax/xxx` endpoints, scheduled tasks, exports | **No** (pure functions suffice) |

In the current situation, A and C account for the vast majority of requirements, while B is rare — this directly determines that there is no need to take the risk of using bare DLLs.

## 2. Current facts (verified against source)

| Item | Fact | Location |
|---|---|---|
| Form registry | `TStringList` stores `TFormClass`, process-global, registered at compile time | `lwapp.pas:164-170` |
| Form creation | `cls.Create(nil)`, then mounted into the session component tree by name | `lwapp.pas:139-145` |
| Registration syntax | One line: `TLWApp.Register(TAwareForm)` | `demos/dbaware/dbaware.lpr:16` |
| Linking method | demo directly references the source `OtherUnitFiles=../../src/core`, statically compiled | `demos/dbaware/dbaware.lpi` |
| Packages | `src/lwcore.lpk`, `src/lwserver.lpk` already exist (RunAndDesignTime) | `src/*.lpk` |
| Routing | Single process, single application: `/` renders the default form, `/lw/api/*` framework APIs, `/lw/ajax/*` business endpoints | `lwhttp.pas:2146-2319` |
| Multi-process | `lwhyper` already has worker startup / health checks / rolling hot updates / WS pass-through, but **only launches multiple copies of the same exe**, with no routing by path | `lwhyper.pas:8-26` |
| Session | Pure in-process `TStringList`, sid = first 8 characters of the GUID + counter | `lwsession.pas:1247-1253` |

Key implication: the registration action itself is extremely lightweight (one line), so the threshold for "pluginization" does not lie in registration, but in **whether the form objects inside the plugin can be correctly recognized by the main framework**.

## 3. Experiments: what actually happens across the FPC DLL boundary

Experiment code: `tmp/lwpoc/` (`lwpoclib.pas` compiled as the DLL, `pocmain.pas` as the host),
FPC 3.3.1 / Win64, with the RTL statically linked on both sides.

### 3.1 Class identity — broken (fatal)

```
DLL returned object address      : 22410592
EXE: o is TObject        = FALSE      <-- does not even recognize TObject
EXE: o is TPocExeObj     = FALSE
DLL: o is TObject        = TRUE
DLL: o is TPocObj        = TRUE
EXE: o.ClassName         = TPocObj    <-- looks completely normal on the surface
DLL: o.ClassName         = TPocObj
EXE: o.ClassType = TObject? FALSE
DLL: Kind (virtual method across modules)  = 42   <-- method calls work
```

Reason: `is` compares the "class reference", which is a module-local address constant. The EXE's `TObject` and the DLL's `TObject` are two different addresses; the DLL object's VMT inheritance chain never contains the EXE's class reference, so even traversing to the top yields no match.

**The danger**: `ClassName`, field access, and virtual method calls all work normally — only `is` silently returns `FALSE`. When the framework encounters such a control, it does not crash but "treats it as nonexistent" — no rendering, no event dispatch.

### 3.2 Memory manager — two implementations, but the same underlying heap

```
EXE GetMem implementation address : 4295009552
DLL GetMem implementation address : 4563427952
Same heap implementation?         : FALSE
Block allocated by DLL, freed by EXE... freed successfully (no crash)
```

The two modules each have their own `MemoryManager` record, but on Windows both ultimately go through the process heap, so "cross-module allocation, cross-module deallocation" **happens not to crash**. This is luck, not a contract: on Linux, if one side uses `cmem` and the other does not, or either side installs a custom memory manager, it immediately becomes heap corruption.

### 3.3 Managed strings — likewise "by luck"

```
EXE received              : hello-from-dll-heap
length                    : 19
EXE after concatenation   : hello-from-dll-heap!
```

The reference count and length header live on the DLL heap, and the EXE side uses its own heap management code when rewriting the reference count; it only fails to explode because the underlying heap is the same. **This cannot be used as a design basis**.

### 3.4 Experiment conclusions

| Boundary | Result | Can rely on |
|---|---|---|
| Object / class references | `is` all False | **Absolutely not** |
| Virtual method calls | Normal | Yes (but meaningless, since the type cannot be recognized) |
| Raw memory allocation / deallocation | Does not crash on Windows | Not portable, not reliable |
| Managed string / dynamic array | Does not crash on Windows | Not reliable, must switch to PChar |
| PChar / Integer / record | Normal | **Safe boundary** |

## 4. Comparison of four approaches

| Dimension | ① Bare DLL/SO exporting form classes | ② Process-level plugins (multiple exes + routing) | ③ Lazarus Runtime Package | ④ Source-code plugins + hot update |
|---|---|---|---|---|
| Page granularity A (new page) | Superficially feasible, actually fails to render | **Feasible** | **Feasible** | **Feasible** |
| Page granularity B (new control in a page) | Infeasible | Infeasible (no object tree across processes) | **Feasible** | **Feasible** |
| Page granularity C (AJAX / backend) | Feasible (C ABI) | Feasible | Feasible | Feasible |
| Class identity risk | **Broken** | None (process isolation) | None (shared RTL) | None (same module) |
| Fault isolation | Poor (same process) | **Best** (crashing one does not affect the others) | Poor (same process) | Poor (same process) |
| Independent release / upgrade | Good (swap the DLL) | **Good** (swap the exe, rolling hot update already available) | Medium (bpl must match the toolchain version) | Poor (must recompile the main exe) |
| Deployment complexity | Low | Medium (multi-process + ports + routing) | **High** (bpl distributed with the package, separate sets for nogui and win32) | Low |
| Existing code changes | Small | Medium (new routing + session sharing) | **Large** (all projects switch to package mode) | **Very small** (add a directory + one registration line) |
| Toolchain binding | Weak | Weak | **Strong (any FPC/LCL version change requires a full rebuild)** | Weak |

### Why approach ① does not work

Even if `TFormClass` is stuffed into the registry as a `Pointer` and `cls.Create(nil)` successfully builds a form inside the DLL, every subsequent step fails:

- `lwwriter` serialization: all 110 `is T...` checks are False → controls are skipped, the page is blank;
- `lwdispatch` dispatch: all 72 `is T...` checks are False → clicks have no effect;
- If the plugin DLL uses `uses lwserver` to call `TLWApp.Register`, it pulls in a **second copy of the framework's global state** (`GRegistry`, `GCfg`, `IsMultiThread`, widgetset), escalating the problem from "types not recognized" to "two frameworks each running on their own".

### The real cost of approach ③

A Runtime Package is the only mechanism that lets two modules share the same copy of the RTL/LCL (the IDE itself is a bundle of bpls), so granularity B can only be done this way. The price is:

- All demo / user projects must be changed to reference packages rather than source paths;
- Windows requires distributing `.bpl`, Linux requires distributing `.so`, and **the nogui and win32 widgetsets each need a separate build**;
- bpls are strongly bound to the compiler version; an FPC upgrade requires a full rebuild (especially painful when shipping an SDK externally).

## 5. Recommended route

### Phase 0: Source-code plugin directory (already implemented)

> Operation steps (run the demo, five steps to add a page, integrate into your own project, `.lfm` notes, FAQ)
> are in `PLUGIN_GUIDE_en.md`; this section only covers structure and principles.

The main program contains no business forms; all pages and AJAX come from `plugins/`:

```
plugins/
  umod_dashboard.pas   dashboard page + /lw/ajax/dashboard_stats (pure-code form-building example)
  umod_notes.pas       notes page      + /lw/ajax/notes_export (.lfm designed-form example)
  umod_notes.lfm       the UI for the unit above, controls can be dragged directly in the IDE
  template/            new plugin template (subdirectories are not scanned by the generator)
  lwmodules.pas        auto-generated, do not edit by hand
src/core/lwpluginutil.pas   JSON escaping (JsonEscape); "opening a page by name" is framework API
                            TLWApp.OpenForm, no helper unit needed
```

The module contract has only one rule — declare `procedure RegisterModule;` in the unit's interface section:

```pascal
procedure RegisterModule;
begin
  TLWApp.RegisterForm('Dashboard', TDashboardForm);      { page }
  TLWApp.AddAjax('dashboard_stats', @GAjax.Stats);        { optional: endpoint }
end;
```

#### How to write the UI: `.lfm` (recommended) or pure code, both work

A plugin form is no different from an ordinary LCL form — **using `.lfm` to design the UI is recommended**, as this is the customary practice for Lazarus users:

```pascal
type
  TNotesForm = class(TLWForm)
    edTitle: TEdit;                  { field with the same name as the component in the .lfm }
    btnSave: TButton;
    procedure btnSaveClick(Sender: TObject);   { the event method is declared here too }
  end;

implementation
{$R *.lfm}                           { embed the .lfm in the same directory into the exe resource section }
```

Three points to note:

- **No need to register the resource in `.lpi`**. `.lpi` only registers `.pas` units; the `.lfm` is compiled into the executable's resource section by `{$R *.lfm}` in the unit, and `TForm.Create` looks up that resource by **class name**. As long as the plugin unit is uses'd by `lwmodules.pas` (i.e., within the link scope), the UI can be loaded.
- **Fields and event methods must be placed in the default visibility section of the class declaration** (after `class(TLWForm)` and before `private`, equivalent to published). LCL's `TReader` relies on RTTI to connect the components in the `.lfm` and `OnClick = btnSaveClick` to these members; putting them in `private` prevents the connection.
- **Multiple concurrent sessions are safe**. When LCL encounters forms with the same name in a process, it appends `_1/_2` suffixes to the instance name; the framework's `TLWForm.Loaded` already restores it to the design-time name, and `lwapp.TLWFormProvider.CreateForm` has an empty-name fallback. Tests show that with three sessions open simultaneously, the form names are all `Notes`.

To modify the UI in the IDE: open `demos/plugindemo/plugindemo.lpi` (its `OtherUnitFiles` includes `../../plugins`), open `umod_notes.pas` in the project inspector, and press **F12** to enter the designer. After changing the `.lfm` you must rebuild with **`-B`** — `lazbuild` does not record `.lfm` files in the dependency table (this is also a general caution for all demos in this project).

If you do not want to use `.lfm`, you can also build the form in pure code (`umod_dashboard.pas` is the example), suitable for cases where the UI is generated dynamically from data or where you do not want to introduce design-time files. Both styles can be mixed in the same project.

The main program (`demos/plugindemo/plugindemo.lpr`) is reduced to just two lines:

```pascal
RegisterAllModules;
TLWApp.Run;
```

Adding a feature: add `plugins/umod_xxx.pas` → `python tools/lwplugins.py` → recompile. The generator scans the directory, recognizes `RegisterModule`, skips helper units, and does not write to disk when the content is unchanged (avoiding unnecessary recompiles); neither the main program nor the `.lpi` needs to be modified. For production, reuse `lwhyper`'s rolling hot update (rename/repackage + restart workers one by one) for zero downtime.

#### Verified: 16 items pass at each of the nogui and GUI tiers

```bash
python tools/lwplugins.py --lpi demos/plugindemo/plugindemo.lpi --lpi demos/plugindemo/plugindemo_gui.lpi
lazbuild --ws=nogui demos/plugindemo/plugindemo.lpi     # -> plugindemo.exe
lazbuild demos/plugindemo/plugindemo_gui.lpi            # -> plugindemo_gui.exe

./plugindemo.exe --port=8877 --form=Dashboard
python tests/t_plugin.py                                 # 16 items

LW_BASE=http://127.0.0.1:8878 python tests/t_plugin.py \
    --expect-cls TNotesForm --expect-form Notes           # second module
```

Assertion coverage: plugin forms are instantiated and appear in the node tree (`TDashboardForm` 16 nodes, `TNotesForm` 13 nodes), button clicks are dispatched through the framework and write back server-side state (including form value return, and comparing that the text actually grows before and after the click to avoid false positives from the initial text), `TLWApp.OpenForm` page-switch round trips (dashboard -> notes -> back, the target page appears and the source page is removed from the tree), the AJAX endpoints of both plugins respond independently, and `--form=` matches the registered name. The bare DLL approach would silently fail at all of these points, so this set of assertions also serves as a guard test for "whether the plugin implementation has regressed".

### Phase 1: Process-level plugins (independent exe + routing) — implemented (2026-11-18)

`lwroute.pas`: the main framework reverse-proxies `/p/<plugin name>/...` to an independent exe upstream. Each plugin is a complete lazarusWeb service (listening on its own port), registered in the host ini as `plugin.<name>=host:port`. See `demos/procdemo/` for the demo (host + three plugin exes for notes/dashboard/reports, with plugin module sources collected in `demos/procdemo/modules/`), and `tests/t_route.py` for the regression.

Implementation points:

- Calling a plugin **does not go through lwhyper**: `lwroute.pas` has its own independent reverse proxy (directly using `fphttpclient`, with header/body pass-through, hop-by-hop stripping, and raw byte upload), sharing the same origin as `lwhyper.ProxyHTTP` only in terms of coding style; the plugin exe does not link lwhyper either — it is just a plain `TLWApp.Run` service;
- Forwarding injects `X-Forwarded-Prefix: /p/<name>/`, based on which the plugin shell HTML generates `/lw/...` resource URLs under the proxy prefix; client JS derives BASE from the page path, so API calls automatically fall back to the proxy — the entire session (create session / events / long polling / upload / AJAX) goes through the proxy back to the plugin; **the proxy must re-append the original query string to the upstream URL** (`ProxyTo` takes the `?...` from `ARequest.URL`): `Route` first strips the query for path matching, while poll/tree/ajax all rely on the query to pass `sid/t/after/form` — once lost, the upstream `Find('')=nil` returns `gone`, and the frontend `forgetSid+boot` repeatedly rebuilds, appearing as an infinite "session expired" flicker (`t_route.py` has a dedicated assertion guarding this);
- **Non-business functions are handled by the main program; plugins only handle business**: framework static resources (`lw.js` / `lw.css` / `lw-alpine.js` / `lw-alpine.css` / `alpine.min.js`, `favicon.ico`, `/ext/` resources) are served **directly by the host** when passing through the proxy (`lwroute.LWRouteStaticLocal` rewrites local paths via a whitelist), and are not forwarded to the plugin — upgrading the client runtime only requires changing one place, the host, and plugin deployment does not need to carry these files; session-bound endpoints (`/lw/api/*`, `/lw/ajax/*`, captcha, `/lw/tpl/` templates) keep their state in the plugin session and are still proxied back to the plugin. Current templates come in two copies: desktop `<runtime root>\tpl\<form name>.html` + mobile `<form name>.m.html`, with the file header `lw-tpl-mode:window|flat` (flat takes priority; a background decoration layer that does not reflow controls), see `PLUGIN_GUIDE_en.md` for usage. When a plugin connects directly to its own port, behavior is unchanged (`LWFindClientFile` serves as normal), and proxy-layer interception does not affect direct-connection debugging;
- A missing trailing slash on `/p/<name>` gets a 301 to add the slash; an unregistered plugin name returns 404 with a hint;
- Push uses long polling (`/lw/api/poll` is the only push channel); **WebSocket is not yet passed through the proxy**, and when the frontend WS cannot connect it automatically falls back to POST events + long polling (retrying every 2 seconds, with no functional loss); WS tunneling is on the list for future enhancement;
- Plugin exe deployment can carry only the exe (framework static resources are served directly by the host, see above).

New framework API: `TLWForm.RunJS(ajs)` (the server pushes JS, analogous to uniGUI's UniSession.AddJS); the host navigation page uses it to jump in the current tab with `location.href='/p/<name>/'` (use `window.open(..., '_blank')` only when a new tab is needed).

`OpenForm` navigation between plugin pages is routed by form (module source code unchanged): at compile time, two forms in the same process switch pages directly; with independent exes, each process only has its own forms, and when the target form cannot be found in the current process, `OpenForm` looks up the ini's `page.<registered name>=<URL>` mapping and, on a hit, pushes JS to jump to the other plugin's page (a full-page jump in the same tab, not coexistence). `t_route.py` has bidirectional assertions (dash↔notes) guarding this.

The change that must be made first: **session sharing**. Currently the sid only exists in each process's memory; a user jumping from `/p/notes/` to `/p/dash/` has two independent sessions (no login drop, because login was not implemented in the first place; between a host and plugins with login enabled, login would drop). Two paths:

- Short term: each module has an independent session (implemented this way, with zero changes required);
- Medium term: change the sid to an HMAC-signed self-contained token (carrying user identity + expiration time), and each module verifies the signature and then creates a local session. The work is concentrated in `lwsession`.

### Phase 2: Runtime Package (only when object trees must be mixed on the same page)

Only when the requirement truly becomes "the plugin provides new controls to be embedded into an existing page of the main framework" is it worth paying the cost of approach ③. At that point, set `lwcore/lwserver` as runtime packages and have the plugin write its own `.lpk` depending on them.

### Not recommended: bare DLL exporting form classes

See §3 and §4. Technically it can load and build objects, but rendering and events will silently fail, and the failure points are scattered across 182 checks, making troubleshooting extremely costly.

## 6. If you really must use a bare DLL: the only safe boundary

Restrict the plugin to "**UI-less functional extensions**" using the C ABI:

```pascal
{ Plugin export, use only PChar / Integer / records, pass no objects and no string }
function LwPluginInit(const AHost: PLWHostApi): Integer; cdecl;
function LwPluginCall(const AAction, APayloadJson: PChar;
                      AOut: PChar; AOutLen: Integer): Integer; cdecl;
```

On the host side, convert the return value to its own `string` and then expose it as `/lw/ajax/<name>` through `TLWApp.AddAjax`. Applicable scenarios: interfacing with hardware SDKs, adapting specific protocols, encryption/algorithms, and file conversion. It **cannot** be used to provide forms or controls.

## 7. Verification still needed before Phase 1/2 implementation (does not affect the conclusion of this round)

Phase 0 does not depend on any item in the table below; Phase 1 (process-level) and Phase 2 (Runtime Package) must complete them before starting work.

| Item | Why it must be verified |
|---|---|
| Lazarus Runtime Package dual-module class identity | Determines whether approach ③ really holds (this article only did the bare DLL experiment) |
| `.lfm` resource location for forms inside packages | Under multiple modules, `HInstance`/`FindResource` may fail to find resources |
| nogui and win32 bpl coexistence | One plugin needs two builds; verify that loading does not cross-contaminate |
| Linux `.so` boundary | If one side uses `cmem`, the heaps differ, and the "luck" in §3.2 immediately fails |
| ~~Static resources under process-level routing~~ | **Verified and upgraded**: framework static resources are now served directly by the host (`lwroute.LWRouteStaticLocal` whitelist), so plugin deployment can carry only the exe; when a plugin connects directly to its own port, `LWFindClientFile` serves as normal |

(Phase 1 is already implemented; the remaining items only affect Phase 2.)

## 8. Acceptance criteria (by phase)

- Phase 0: after adding a `plugins/umod_x.pas`, only a rebuild + release is needed; the page is accessible, events can be dispatched, and AJAX can be called; zero changes to the main framework source.
- Phase 1: `/order/` and `/report/` land in different processes; kill one and the other continues to serve normally; upgrading a single module does not interrupt the others.
- Phase 2: new controls provided by the plugin package can appear on main framework pages and write back correctly.

## 9. Appendix: reproducing the experiment

```bash
cd tmp/lwpoc
C:/111/fpc/bin/x86_64-win64/fpc.exe -O- lwpoclib.pas   # -> lwpoclib.dll
C:/111/fpc/bin/x86_64-win64/fpc.exe -O- pocmain.pas    # -> pocmain.exe
./pocmain.exe class    # class identity
./pocmain.exe mem      # heap
./pocmain.exe str      # managed strings
```
