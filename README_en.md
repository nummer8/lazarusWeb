# lazarusWeb

Quickly turn a Lazarus desktop application into a web app that runs in the browser. It serializes the **real LCL control tree** directly into the UI; the **default rendering layer is Alpine.js** (built-in dependency, zero extra deployment), while Ext JS is an optional rendering layer (you must provide the `ext` directory yourself and explicitly enable it with `--client=ext`). Business programs only need to change the form base class from `TForm` to `TLWForm`; all other code (events, properties, `.lfm`) stays unchanged, and the app can run in the browser as a service program.

Browser (Alpine.js by default / Ext JS optional) — Server (Lazarus, nogui widgetset)

| Browser side (Alpine.js by default, Ext JS optional) | Communication | Server side (Lazarus, nogui widgetset) |
| :--- | :---: | :--- |
| `lw-alpine.js` + `alpine.min.js` renderer/coordinator<br>（Optional: `lw.js` + `ext-<version>/`）<br><br>Native DOM/CSS (optional: Ext.window/panel/grid/...)<br><br>`WS sends events / long-polling cursor receives pushes` | <br>**HTTP←→JSON**<br><br> | `lwhttp` fcl-web multithreaded server<br>`lwsession` one LCL control tree per tab<br>`lwwriter` LCL tree → JSON<br>`lwdispatch` event → RTTI call into business code<br>`lwws` nogui patch (virtual display/canvas) |

## Requirements

- FPC 3.3.1/3.2.2 + Lazarus
- Alpine.js (built-in dependency)
- Ext JS 7.0.0 (GPLv3 edition, **optional**: not included in the release package; obtain it from Sencha's official channel and place it in `ext-7.0.0\`; if absent, the built-in Alpine.js rendering layer is used by default)
- **Ext support is optional. ext-js files must be obtained by the user, and the user is responsible for license compliance.**

## Control Installation (Lazarus IDE design-time packages)

To open forms containing lazarusWeb controls in the IDE designer, use the "New Project Wizard", and use the "Generate lazarusWeb Form Template" Tools menu, you must first process three packages in a **fixed order**. The order cannot be changed: `lwserver` depends on `lwcore`, and `lwdesign` (the design-time package) depends on the first two. Skipping steps will cause `Can't find unit lwcore / lwserver` during Install.

| Order | Package | Type | Depends on | What to do in the IDE |
|---|---|---|---|---|
| 1 | `src\lwcore.lpk` | RunAndDesignTime | LCL / FCL / fcl-image | **Compile only**, do not Install |
| 2 | `src\lwserver.lpk` | RunAndDesignTime | LCL / FCL / **lwcore** | **Compile only**, do not Install |
| 3 | `src\design\lwdesign.lpk` | DesignTime | LCL / IDEIntf / **lwcore** / **lwserver** | **Compile → Install** (rebuilds `lazarus.exe`, then restart the IDE) |

Detailed steps:

1. Register the three packages from the command line first (so the IDE knows them; otherwise creating a new project reports "package not found"):

   ```
   tools\install_design.bat
   ```
   Equivalent manual commands (replace `C:/111/lazarus` with your Lazarus directory):
   ```
   lazbuild --add-package-link=src\lwcore.lpk
   lazbuild --add-package-link=src\lwserver.lpk
   lazbuild --add-package-link=src\design\lwdesign.lpk
   ```
   Note that `--add-package-link` only "registers/recently opens"; **it does not mean install**.
   The `--add-package` argument form reports `does not allow an argument` on this local Lazarus; this is normal.

2. Open Lazarus and process the packages in the order above via `Package → Open Package File → <package>.lpk`.
   For the first two, click **Compile** (only compile ppu, do not Install); for the third, `lwdesign.lpk`,
   click **Compile → Use → Install**, choose "Yes" when asked whether to rebuild the IDE, wait for the rebuild to finish,
   then **restart Lazarus**.

3. After restart, verify: `File → New → Project` shows two lazarusWeb templates,
   the component palette shows the **lazarusWeb** page, and the Tools menu shows "Generate lazarusWeb Form Template".

> After switching to a new framework version or modifying design-time package source code, you must redo step 2 for `lwdesign.lpk`:
> Compile → Install → restart the IDE; otherwise the designer and Tools menu still run old code.
> Do not compile `lwserver.lpk` in the IDE (the nogui widgetset unit is not in the IDE search path,
> and it will report `Can't find unit noguiint`). Leave that package to command-line `lazbuild` or a new project.
> See `docs/NOTES.md` Pitfall 15 / Pitfall 16 for the complete troubleshooting record.

## Cross-platform build matrix (host → target)

All source code (`src/`, `tools/`, `demos/`) is cross-platform: platform differences in core units
(timestamp precision / critical section reentrancy / path style, etc.) are isolated with
`$IFDEF MSWINDOWS/LCLGTK2/LCLQT5` and all have non-Windows branches. No Windows-specific units are referenced.
All `.lpi`/`.lpk` paths use forward slashes and do not hard-code target CPU/OS (artifact names use
`$(TargetCPU)-$(TargetOS)` variables).

**FPC version**: the same source supports both **FPC 3.2.2 and 3.3.1**. Capabilities newly added in 3.3.1
(`RegisterUpdateHandler` / `ThreadMode` / `ConnectionHandler` in `fphttpserver`, `SetTextAutoFlush`,
`GetHTTPStatusText`, etc.) are wrapped in dual branches with `{$IF FPC_FULLVERSION >= 30301}`.
Under 3.2.2, equivalent shims are used (OnRequest manually handles upgrade, `select` implements
`LWCanRead`, built-in status code table, 1-byte text buffering); under 3.3.1 the native path is used, with identical behavior.

Tested cross-compilation combinations (Windows host, nogui widgetset):

| Target | Command highlights | Artifact |
|---|---|---|
| x86_64-linux | `--os=linux --cpu=x86_64 --ws=nogui --compiler=...ppcrossx64.exe` | `gallery_nogui-x86_64-linux` (ELF x86-64) |
| mips64el-linux | `--os=linux --cpu=mips64el --ws=nogui --compiler=...ppcrossmips64el.exe` | `gallery_nogui-mips64el-linux` (ELF MIPS, tested on Loongson 3A) |

```
lazbuild --os=linux --cpu=mips64el --ws=nogui \
         --compiler=/c/111/fpc/bin/x86_64-win64/ppcrossmips64el.exe \
         demos/gallery/gallery.lpi
# → gallery_nogui-mips64el-linux (ELF, about 6.5MB text segment; ld's abicalls
#   mixed-link warning can be ignored)
```

On a Linux host, simply run `lazbuild` on each demo `.lpi`; `build.sh` and
`build.bat` are functionally equivalent. Directory/file names are case-sensitive on Unix; see the next section.

## Directory structure

| Path | Contents |
|---|---|
| `src/core/lwbase.pas` | Common types, utilities, threadvar session pointer |
| `src/core/lwws.pas` | nogui widgetset patch (**required**, see below) |
| `src/core/lwform.pas` | `TLWForm` business form base class (includes `SendFile` / `SendText`) |
| `src/core/lwwriter.pas` | LCL control tree → JSON |
| `src/core/lwsession.pas` | Sessions, form list, synchronous modal |
| `src/core/lwdispatch.pas` | Browser events → real LCL control events |
| `src/core/lwhttp.pas` | HTTP service, static resources, API routing, upload/download |
| `src/core/lwapp.pas` | Application facade (registration/command line/startup) |
| `src/core/lwconfig.pas` | Server configuration file (INI: Port / Theme / ExtDir) |
| `src/core/lwfileupload.pas` | `TLWFileUpload` upload button control |
| `src/core/lwcamera.pas` | `TLWCamera` camera control (mobile invokes system camera / desktop in-page preview) |
| `src/core/lwdlg.pas` | **LCL dialogs redirected to browser** (ShowMessage / MessageDlg / InputQuery / TOpenDialog ...) |
| `src/core/lwupload.pas` | multipart parsing and saving to disk |
| `src/core/lwdownload.pas` | Download token table (paths are not exposed in URLs) |
| `src/core/lwnewproject.pas` | Project skeleton template (shared by wizard and `lwnew`) |
| `src/client/lw.js` | Browser-side rendering and incremental reconciliation |
| `src/client/lw.css` | Base styles |
| `src/lwcore.lpk` | Runtime package (does not depend on widgetset; used by design-time package) |
| `src/lwserver.lpk` | Runtime package (server side; automatically applies widgetset patch under nogui) |
| `src/design/lwdesign.lpk` | **Design-time package**: new project wizard / New Form / component palette |
| `demos/hello` | Minimal example |
| `demos/grid` | Grid example (load/filter/edit/status bar) |
| `demos/multi` | Comprehensive example (menu/multiple tabs/toolbar/**synchronous modal**) |
| `demos/db` | **SQLite database example** (TDBGrid/TDBEdit/TDBMemo CRUD, sorting, filtering, category statistics) |
| `demos/files` | **File upload/download example** (TLWFileUpload, SendFile, SendText export CSV) |
| `demos/dbaware` | **DB-aware control suite** (TDBText/TDBListBox/TDBRadioGroup/TDBLookup*/TDBImage data-aware tests; main form has 87 objects, `uAwareMain.lfm` is 866 lines) |
| `demos/dialogs` | **Dialog example** (ShowMessage/MessageDlg/InputQuery/QuestionDlg/MessageBox/OpenDialog/SaveDialog) |
| `demos/gallery` | **Full-feature gallery** (benchmarking uniGUI full-feature demo: 12 pages, 60+ controls — standard controls/buttons/extended inputs/containers/grids/toolbars/charts/HTML·PDF·upload/dialogs/timers/DB-aware/large table paging, `tests/t_gallery.py` 50 regression items) |
| `docs/MAPPING.md` | Control/property mapping table |
| `docs/CONTROL_MATRIX.md` | **Tested support matrix for 66 visual controls** (auto-generated) |
| `docs/DB_AWARE_MATRIX.md` | **Tested matrix for 12 DB-aware controls** (binding/display/sync/write-back, auto-generated) |
| `docs/SECURITY.md` | **Security notes**: SQL injection and trust boundaries (framework has no SQL channel, demo parameterized examples, business code self-check list) |
| `docs/NOTES.md` | nogui porting troubleshooting notes, Pitfalls 1–108 accumulated over time (important; old conclusions such as Pitfalls 23/66 have been revised by later pitfalls; refer to annotations) |
| `docs/HOW_IT_WORKS.md` | **How it works** (for first-time code readers: complete loop of one click, why full RTTI dump is not possible) |
| `docs/MANUAL.md` | **User manual** (usage + development) |
| `docs/FEATURES.md` | **Features and highlights** (one page to see strengths and boundaries: eleven capabilities / seven decisions done right / numbers at a glance / comparison with uniGUI) |
| `docs/INDEX.md` | Documentation navigation index (find docs by scenario) |

## Quick start

```
cd c:\LazarusWeb
build.bat                 :: build all demos (lazbuild -B --ws=nogui)
build.bat grid            :: build only demos\grid (project name auto-detected; db→dbdemo, files→filedemo)
demos\multi\multi.exe --port=8090
demos\db\dbdemo.exe --port=8095      :: SQLite CRUD example (requires demos\db\sqlite3.dll)
demos\files\filedemo.exe --port=8096 :: upload/download example
demos\dbaware\dbaware.exe --port=8110 :: DB-aware control suite
start-gui.bat           :: double-click to start GUI version (dbaware_gui.exe, see next section)
                           Linux/macOS: ./start-gui.sh
```

Open `http://127.0.0.1:8090/` in the browser. Command-line options:

```
--config=path         Specify configuration file (by default auto-find <exe name>.ini / lazarusWeb.ini, see next section)
--port=8090           Listen port
--root=C:\LazarusWeb  Project root directory (contains src/client; ext-<version> only needed for optional Ext layer); defaults to current directory
--form=Name           Default form name
--client=alpine       Browser rendering layer: alpine (default, built-in) | ext (optional, requires ext directory); auto-detect when unspecified (if both exist, alpine is preferred)
--ext=7.0.0           Default Ext version (URL can also use ?ext=<version> to switch temporarily)
--extdir=directory    ext-js directory (equivalent to config item ExtDir)
--theme=crisp         Default theme (Ext rendering layer: classic/crisp/gray/material/neptune/graphite;
                      Alpine layer colors are not here, see below)
--title=title         Browser tab title (defaults to Application.Title)
--timeout=20          Session idle timeout (minutes)
--trust-proxy         Add when behind nginx/Caddy: client IP in logs comes from X-Forwarded-For
--ssl                 Enable HTTPS (FPC built-in; auto-generate self-signed certificate if none given)
--ssl-host=name       Certificate hostname/SAN domain or IP, not the listen address
--ssl-cert=file       Specify PEM certificate (paired with --ssl-key; relative paths resolved against exe directory)
                      Giving certificate/private key automatically enables HTTPS; no need to also write --ssl
--ssl-key=file        Specify PEM private key (paired with --ssl-cert)
--tls-cert= / --tls-key=  Aliases for the above two (also automatically enable HTTPS when given)
--ajax-cors           Allow cross-origin calls to /lw/ajax/* (for third-party page integration)
--verbose             Print every request and exception stack
--nogui               Do not show server panel even in GUI build (for service deployment)
--patch=1             Incremental patch (events return only changed ops, default off; old frontend automatically falls back to full)
--log=path            Append server logs to file
--help                Help
```

The parameter table matches the `--help` output of `src/core/lwapp.pas`; source code is authoritative.

### Configuration file (INI)

If you do not want to type a long command line every time, place an INI next to the exe (template:
[`lazarusWeb.ini.sample`](lazarusWeb.ini.sample)):

```ini
[lazarusWeb]
Port=8090
Theme=crisp
ExtDir=ext-7.0.0
;Patch=0
;Client=ext
```

| Item | Meaning | When empty/invalid |
|---|---|---|
| `Port` | Listen port | Use default **8090** (warning if out of range) |
| `Theme` | Default theme (Ext rendering layer only, `?theme=` can still temporarily override); Alpine layer colors are selected in the title bar buttons, see `docs/MANUAL.md` §5.1 | Use `crisp` |
| `ExtDir` | ext-js directory, absolute or relative path | Auto-find `<root>\ext-<version>` |
| `Patch` | Incremental patch switch, `1` = events return only changed ops | Default `0` (off) |
| `Client` | Browser rendering layer: `ext` / `alpine` (auto-detect if omitted) | Auto-detect |
| `SSL` | Enable HTTPS: `1` / `true` / `yes` | Default `0` (HTTP) |
| `SSLHost` | Certificate hostname/SAN domain or IP; not listen address | Use self-signed certificate when empty |
| `SSLCert` | PEM certificate path (paired with `SSLKey`, relative path resolved against exe directory) | Use self-signed certificate when empty |
| `SSLKey` | PEM private key path (paired with `SSLCert`) | Use self-signed certificate when empty |

Details (decided after hitting issues):

- **Priority**: built-in defaults < configuration file < command line. `--port=9000` always wins over `Port=8090`,
  so "copy one exe ten times, one ini each" and "temporarily change port for debugging" can coexist;
- **Where to place it**: `--config=<path>` explicitly specifies; otherwise search in order:
  `<exe directory>\<exe name>.ini` → `<exe directory>\lazarusWeb.ini` →
  `<current directory>\<exe name>.ini` → `<current directory>\lazarusWeb.ini`;
  relative `--config=` paths are also allowed relative to the exe directory (cwd is often System32 when started as a service);
- **Very tolerant format**: section names may be written or omitted (`[lazarusWeb]` / `[server]` / none are accepted),
  key names are case-insensitive and ignore `-`/`_` (`ext-dir` = `ExtDir`), values may be quoted,
  lines starting with `;` and `#` are comments. Save file as UTF-8 or pure ASCII (ANSI Chinese paths will be garbled);
- **`ExtDir` is a "directory", not a "version number"**: if given, `/ext/<any version>/...` is served from this directory
  (one deployment usually carries one ext version); if it points to a nonexistent or empty directory, a warning is logged
  and it automatically falls back to `<root>\ext-<version>`, without preventing the service from starting;
- The startup banner prints the actual configuration file path and ext directory; check these two lines first when troubleshooting.

Writing your own web program (the total server-side code is just this much):

```pascal
program myapp;
uses Interfaces, Forms, lwapp, uMain;
begin
  Application.Initialize;
  TLWApp.Register(TMainForm);   // class name without T is the form name in the browser
  TLWApp.Run;                   // automatically calls LWInstallWidgetSet
end.
```

The only line to change in the form unit:

```pascal
uses ..., lwform;
TMainForm = class(TLWForm)   // originally class(TForm)
```

> **Important**: compilation must include `-B` (`lazbuild` does not record `.lfm` in the dependency table;
> if only the UI changes and `.pas` does not, old `.o` files continue to be used).
> `build.bat` already adds it.

## Deployment (running from a standalone directory)

The framework **supports** copying the `ext-<version>` directory into the application's own directory for self-contained deployment. When `--root=` is not passed, the root directory (Root) is determined in the following order:

1. **Current working directory** — as long as this directory contains an `ext-<version>` directory, it is considered
   the root. Use whichever directory you start from; this is most intuitive.
2. **Up to 5 levels upward from the executable directory** — find a directory where both "`ext-<version>` + `src/client/lw.js`"
   exist (fallback for double-click running or starting from elsewhere).
3. If none found → `C://LazarusWeb`.
4. Explicit `--root=<path>` has highest priority and overrides the above three.

`/lw/lw.js`, `/lw/lw.css` (and Alpine's `/lw/lw-alpine.js`, `/lw/lw-alpine.css`,
`/lw/alpine.min.js`) lookups all have multiple fallbacks; the following layouts all work:

| Layout | Required files (choose one set according to rendering layer) |
|---|---|
| Standard repository layout (recommended) | `<root>/src/client/lw.js`, `lw.css`; or `lw-alpine.js`, `lw-alpine.css`, `alpine.min.js` |
| Flat deployment | The above files in the same directory as the exe |
| Semi-flat | Put the above files under `<exe directory>/lw/` or `<root>/lw/` (old deployment's `<root>/client/` still compatible) |
| Fallback | Search upward from root level by level for files with the same names under `src/client/` |

Minimal self-contained deployment directory (**default Alpine.js rendering layer, no ext directory needed**):

```
MyApp/
  MyApp.exe
  src/client/alpine.min.js   44 KB   Alpine.js itself (defer loaded, not from CDN)
  src/client/lw-alpine.js    205 KB  renderer/coordinator (adaptive only for this layer; templates shared by both layers)
  src/client/lw-alpine.css    59 KB  styles: CSS variables for 7 color schemes (light/beige/eye-care green/high contrast/dark/dark blue/ink green) are all here
  tpl/                              optional: form templates; read by both Alpine/Ext layers, silently fall back to design-time layout when missing
  favicon.ico                       optional: browser tab icon (put in exe directory or --root directory)
  ext-<version>/                    optional: Ext JS rendering layer (~75MB, requires --client=ext to explicitly switch)
  cert/                             optional: place server.crt/server.key/ca.crt here when SSL is enabled and using your own PEM
  libssl-3-x64.dll + libcrypto-3-x64.dll  optional: required in exe directory when SSL is enabled
```

(When using the Ext rendering layer, replace with `src/client/lw.js` + `lw.css` + `ext-<version>/`;
all three Alpine files are required — without `alpine.min.js`, auto-detection judges Alpine unavailable and
falls back to Ext; without CSS the page runs but has no styling at all.)

Verification: after startup, check the banner's `Root :` and `Client :` lines (default should be alpine), or
`curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8090/lw/lw-alpine.js` (should be 200).

### Starting demos

```bat
start-demo.bat            :: default 8092, double-click to run
start-demo.bat 8095       :: specify port
```

```bash
./start-demo.sh           # Linux / macOS, default 8092
./start-demo.sh 8095
```

The service runs in the foreground; open the printed address in the browser. Press `Ctrl+C` or close the window to stop.
(If the port is occupied, use another one: after a process is forcibly killed, an orphan socket with `LISTENING PID 0`
may remain; it is visible in `netstat` but cannot be killed, so changing port is easiest.)

## Cross-platform (Linux / macOS)

Core units use only general FPC/LCL facilities: `fphttpserver`, `SysUtils`'s
`DirectoryExists`/`FileExists`/`ExtractFileDir`, and `PathDelim` /
`IncludeTrailingPathDelimiter` to build paths — **no** platform units such as `Windows`, `winsock`,
`ShellExecute` (`grep -rn "Windows" src/core/*.pas` only hits comments). `lwws.pas` degenerates to an empty implementation
under non-nogui widgetsets, so it can also compile under win32/gtk2/qt5/carbon (running under `--ws=nogui` is still recommended).

Build:

```bash
./build.sh                        # all demos
./build.sh dbaware                # single
LAZBUILD=/opt/lazarus/lazbuild ./build.sh

tools/build.sh                    # all tools (convert/hyper/audit/dbcheck/hyper_gui/convert_gui)
tools/build.sh convert            # single tool (direct fpc compile, no LCL)
tools/build.sh hyper_gui          # GUI tools compile with host widgetset
```

`.lpi` does not fix `TargetOS`/`TargetCPU`; it builds according to host platform; on Unix artifacts have no
`.exe` suffix (`build.sh` deletes both names). Windows uses `build.bat`;
`LAZBUILD` environment variable can also override.

Runtime dependency differences:

| Dependency | Windows | Linux | macOS |
|---|---|---|---|
| SQLite (for demos) | `sqlite3.dll` (already included in demo directory) | `libsqlite3.so` (`apt install libsqlite3-0`) | built into system |
| Alpine.js / lw-alpine.js (default); Ext JS / lw.js (optional) | same as left | same as left (paths built with `PathDelim`) | same as left |
| Command-line arguments | `--port=` `--root=` `--theme=` `--config=` | same as left | same as left |

Note that Unix file names are case-sensitive (Windows is not); keep directories/file names such as `src/client`
unchanged (ext directory name can be arbitrary; the server automatically recognizes the single
`ext-*` directory under root).

## Creating projects with the wizard in the IDE (design-time package `lwdesign`)

After installing `src/design/lwdesign.lpk`, three things appear in Lazarus:

| Location | Contents |
|---|---|
| File → New → Project | **lazarusWeb Application** (default widgetset, `$APPTYPE GUI`, press F9 directly in IDE, no black window) and **lazarusWeb Application (nogui)** (`LCLWidgetType=nogui` console service, deployment profile) two templates. Disk write timing is the same as Lazarus built-in templates: after choosing a template, no dialog is shown and nothing is written (the project is "virtual"); pressing Save (Ctrl+S) shows the "Save Project" dialog, and the directory defaults to the IDE option "project build test directory". This step generates `.lpr/.lpi/umain.pas/.lfm/build.bat/build.sh/favicon.ico`, and copies the framework's `src/client` into the project directory's `lw/` (runtime finds static resources by `exe/lw/<file>`; site icon `favicon.ico` goes in project root, and the server searches `<root>` → `<exe directory>` in order). The nogui profile's `.lpi` macro is patched **after the save transaction truly ends** (`.lpi` and all units are written, stable for two consecutive rounds before acting; never pop dialogs or reload project during saving, see NOTES Pitfall 172), so it is completed **about 1 second after saving**, then a message "nogui profile: effective after reloading project" pops up — click "Yes" to reopen the project, and F9 gives a windowless console service |
| File → New → File | **lazarusWeb Form** — a `TLWForm` form unit, directly into the designer |
| Component palette | **lazarusWeb** page: `TLWFileUpload` / `TLWCamera`, etc. |

Installation (only once):

```
tools\install_design.bat        :: register the three packages first
```

Then follow its prompts in the IDE: `Package → Open Package File → lwdesign.lpk → Use → Install`,
and let the IDE rebuild once (design-time packages are statically linked into `lazarus.exe`; a rebuild is required to take effect).

First use, five steps:

1. **Install packages**: the command above + `Install` to rebuild the IDE (also reinstall when switching to a new package version, otherwise old code still runs);
2. **New**: `File → New → Project`, choose a template (GUI profile for debugging / nogui profile for deployment), **nothing is written after selection**;
3. **Save**: `Ctrl+S` opens the standard "Save Project" dialog and only then writes to disk. Do not name the project `LWApp` (conflicts with `lwapp.pas`, compile reports `Duplicate identifier "LWAPP"`); the default `LWApp1` is safe;
4. **nogui profile has one extra step**: about 1 second after saving, a message "nogui profile: effective after reloading project" pops up; click **"Yes"**;
5. **F9**.

> **Note: pressing F9 within 1 second after saving still uses the win32 widgetset** — the macro has just been written into the `.lpi`
> file, but the project options in IDE memory have not been reread, so the build still pops up the server panel window. Wait for the
> prompt in step 4 to appear and click "Yes", then press F9; if you do not want to reopen the project, use the project directory's
> `build.bat`.

For the list of written files, UI details of each step, and troubleshooting (`%TEMP%\lazarusweb-wizard.log`), see
`docs/MANUAL.md` "Creating a project from scratch with the IDE wizard".

> TLWForm is a **real TForm descendant**, not a shadow class like uniGUI, so no
> design-time proxy is needed: dropped TButton/TEdit are LCL's own controls, property inspector, event page,
> alignment tools, and anchors all work as usual. The layout seen in the form designer is the layout in the browser.

If you do not want to open the IDE, you can also generate a project skeleton directly from the command line (this generates a Lazarus project, not a form template; for template skeletons use the IDE Tools menu above):

```
tools\lwnew.exe --name=DemoApp --dir=C:\work\DemoApp --units=C:\LazarusWeb\src\core
```

When `--units` specifies the source directory, it does not depend on installed packages; if omitted, it requires the
`lwserver` package to be registered.

**Compilation method**: which widgetset LCL uses is determined by the `LCLWidgetType` macro in `.lpi`.
The repository demos and manually converted old projects do not have this macro; pressing F9 in the IDE uses the IDE's own
widgetset (win32), cannot link LCL's nogui units, and can only rely on lazbuild specifying it. The wizard-generated
nogui project already writes this macro into `.lpi`; after reloading the project, F9 in the IDE directly uses
nogui (pressing F9 within 1 second after saving is still win32, see previous section). `build.bat` writes both:

```
lazbuild -B --ws=nogui <project>.lpi
```

> Note the distinction: **packages** (`lwserver.lpk`) can be compiled/installed directly in the IDE — `lwws.pas`'s
> nogui patch is wrapped in `{$IFDEF LCLnogui}` and degenerates to an empty implementation under non-nogui;
> but **projects without the `LCLWidgetType` macro** (demos, manually converted old projects) must use
> `--ws=nogui`, see `docs/NOTES.md` Pitfall 15.

## File upload / download

Use `TLWFileUpload` for uploads (a `TButton` descendant, can be placed at design time):

```pascal
procedure TFileForm.btnUploadUpload(Sender: TObject; const AFileName: string);
begin
  // AFileName is the full path on the server; open directly with TFileStream
  lstFiles.Items.Add(ExtractFileName(AFileName));
end;
```

- The browser opens the system file dialog; XHR uploads with progress; button text shows percentage in real time;

## Camera (TLWCamera)

Drag `TLWCamera` (a dedicated descendant of `TLWFileUpload`) onto the form:

```pascal
procedure TMainForm.camPhotoCapture(Sender: TObject; const AFileName: string);
begin
  // The photo has been saved on the server (uploads\<session>\camPhoto\xxx.jpg)
end;
```

- Mobile/tablet: clicking the button directly invokes the **system camera** (`Facing` switches front/back), and after shooting
  it is sent back through the existing upload channel and triggers `OnCapture`; **works over LAN http**;
- Desktop: under HTTPS or localhost, opens an **in-page viewfinder** (getUserMedia, live preview +
  capture/cancel/choose image); captured frames are compressed to long edge 1600px, converted to JPEG, and sent through the same channel;
  Desktop pages over LAN http are prohibited by browsers from accessing the camera, so it automatically degrades to "choose image file";
- Preview: `PreviewImage := 'imgPhoto'` — after browser capture, immediately display locally in the specified
  TImage; photo data does not go through the component tree patch; the server only gets the file path;
- Full description in `docs/MANUAL.md` usage section "Camera", example
  `demos/mobile_demo`, regression `tests/cdp_camera.py`.
- The server parses `multipart/form-data` and saves to
  `%TEMP%\lw_uploads\<session number>\<control name>\` (or specify with `TargetFolder`);
- File names are sanitized (remove paths, remove `..`, remove illegal characters); multi-select triggers `OnUpload` one by one;
- `Filter` (`'Text|*.txt;*.csv|All|*.*'`), `Multiple`, `MaxSizeKB` all participate in validation.

Download in one line of business code:

```pascal
SendFile('C:\data\report.xlsx');            // push an existing server file
SendText(csv.Text, 'list.csv', True);       // directly download computed text (True = with BOM, Excel recognizes Chinese)
```

The URL **does not** contain the server path: `SendFile` registers the file as a one-time token,
and the browser only receives `/lw/download?t=<token>`; the token expires after 30 minutes or after first use.

| Route | Description |
|---|---|
| `POST /lw/api/upload?sid=&id=` | `multipart/form-data`, returns new component tree |
| `GET /lw/download?t=<token>` | With `Content-Disposition` (including `filename*=UTF-8''`) |

**Complete business example**: `demos\db` attaches attachments to each product (upload → save to
`attachments\item<id>\` + write `attachments` table → download/delete),
using an independent database connection for attachment writes, without interrupting the main record being edited — see
`demos\db\README.md` "How attachments are connected".

## Dialogs (ShowMessage / MessageDlg / TOpenDialog ...)

**Not a single line of business code needs to change**. These LCL functions are redirected on the server to "pop up a modal in the browser",
and the server thread waits there until the user clicks, then continues:

```pascal
procedure TMainForm.Button1Click(Sender: TObject);
begin
  if OpenDialog1.Execute then              // browser pops up file selection dialog
    mmoLog.Lines.Add(OpenDialog1.FileName); // returns a server temporary path
  ShowMessage('lazarus Web test');          // browser pops up message box
end;
```

Directly available (no code, no replace needed):

| LCL entry | What the browser shows |
|---|---|
| `ShowMessage` / `ShowMessagePos` | Iconless message box + OK |
| `MessageDlg` / `MessageDlgPos` | Info/warning/error/question icon according to `TMsgDlgType` |
| `InputQuery` / `InputBox` / `PasswordBox` | With input box (`PasswordBox` is password box) |
| `QuestionDlg` | Custom button text, `ModalResult` returned as-is |
| `Application.MessageBox` / `LCLIntf.MessageBox` | Flags such as `MB_YESNO` parsed according to Windows semantics |
| `TOpenDialog.Execute` | Select file (**uploaded to server first**), `FileName` = server path |
| `TSaveDialog.Execute` | Enter file name, `FileName` = path under session temporary directory |

A few things you must know:

- **File dialogs return server paths**. The browser cannot hand local paths to the server,
  so the selected file is uploaded as `multipart` to `%TEMP%\lw_uploads\<session number>\pick\`;
  `FileName` is that path, and `TFileStream` can open it directly. Saving is similar:
  `TSaveDialog.FileName` lands in `...\<session number>\save\`; after writing the file, call `SendFile` to push it to the user for download.
- **The thread really blocks**. The event request hangs until the user answers (or 180-second timeout), consistent with desktop modal behavior;
  other sessions continue running during this time; popping a second dialog in the same session is rejected with a message.
- **When there is no browser session** (e.g., pressing F9 directly in the IDE, or running unit tests from command line), it automatically falls back to the original LCL implementation.
- These are **runtime replacements**; `lwdlg.pas` is in the `lwcore` package, and business projects using `lwapp` take effect
  (`LWInstallDialogs` is installed before `TLWApp.Run`, hooking `InterfaceBase`'s
  `PromptDialogFunction` / `InputDialogFunction` / `QuestionDialogFunction` /
  `Forms.MessageBoxFunction` and `RegisterWSComponent(TOpenDialog, …)`).

**Complete example and HTTP-level tests**: `demos\dialogs` (7 buttons each demonstrating one type),
`tests\t_dialog.py` (36 items, including the full chain "push → answer → wake → return value").

## Runtime behavior (correspondence with uniGUI)

| uniGUI | lazarusWeb |
|---|---|
| TUniSession | TLWSession (one per browser tab) |
| Component → JS mapping | lwwriter + lw.js incremental reconciliation |
| Synchronous modal (nested message loop) | `ShowModal` pushes instruction then suspends request thread, `TEvent.WaitFor` waits for browser close |
| Ajax event | `POST /lw/api/event`, values written back to control first, then RTTI triggers event |

Business code is completely unaware of the web:

```pascal
procedure TMainForm.miAboutClick(Sender: TObject);
var f: TAboutForm;
begin
  f := TAboutForm.Create(nil);
  try
    if f.ShowModal = mrOk then          // under Web this line waits for user to click OK
      lblState.Caption := 'About viewed';
  finally
    f.Free;
  end;
end;
```

## HTTP API

| Route | Description |
|---|---|
| `GET /` | UI shell (`?ext=7.0.0&form=MainForm` can override defaults; `?fresh=1` forces new session) |
| `POST /lw/api/session` | Create session `{form:"MainForm"}` → returns tree + `sid` + `seq` |
| `GET /lw/api/attach?sid=` | **Cross-tab sharing**: attach this tab to an existing session (returns 410 + `gone` if nonexistent) |
| `GET /lw/api/tree?sid=` | Current component tree |
| `POST /lw/api/event` | `{sid,id,ev,val,row,col,vals,tab}` → new component tree |
| `GET /lw/api/poll?sid=&t=&after=` | Long polling. With `after`, fetch pushes by cursor (each tab fetches its own); without it, old destructive queue. **The only push channel** |
| `GET /lw/ws?sid=` | WebSocket upgrade (RFC6455): **only transmits event requests/responses** (events go through WS frames when WS is connected); pushes do not go through WS, always delivered by the long-polling cursor above; automatically falls back to HTTP on disconnect |
| `GET /lw/api/log?sid=` | Session log (Show/ShowModal/EndModal all recorded) |
| `POST /lw/api/close` | End session |
| `POST /lw/api/dlg` / `POST /lw/api/dlgfile` | Browser modal (ShowMessage/MessageDlg/InputQuery/TOpenDialog...) reply endpoints (see `docs/MAPPING.md` dialog section) |
| `POST /lw/api/upload?sid=&id=` | File upload (`multipart/form-data`, arbitrary field names, multiple files allowed) |
| `GET /lw/download?t=` | Download (`t` is a one-time token registered by `lwdownload`, invalid after use) |
| `GET /lw/ajax/<name>` | **Custom AJAX endpoint**: registered via `TLWApp.AddAjax(name, handler)`, third-party JS can fetch directly |
| `GET /lw/healthz` | Health check (LB/k8s probe): `{"ok":true,"sessions":..,"uptime":..}` |
| `GET /ext/<version>/<path>` | Ext JS static resources (two versions can coexist) |
| `GET /favicon.ico` | Site icon: `--root` directory → exe directory → 204 if none; when hit, 200 + `Cache-Control: public, max-age=86400`. Both shell HTML heads include `<link rel="icon">` |

## Control support (tested)

`docs/CONTROL_MATRIX.md` is auto-generated by `tools\lwaudit` (snapshot: 2026-11-09;
fixes later than that date are in `docs/NOTES.md` Pitfalls 97/107): 66 common LCL
visual controls are each **really created under nogui + attached to a form + serialized once**, then compared with whether `lw.js`
actually has a rendering branch, divided into five categories:

| Status | Meaning | Current count |
|---|---|---:|
| ok | Rendered as a real control in browser, two-way events available | 49 (74.2%) |
| placeholder | Usable on server, browser only draws a box with class name | 14 |
| kind-only | kind mapped but missing rendering branch | 1 |
| create-failed | Throws exception during construction under nogui (e.g., native `TDBNavigator` depends on button glyphs; use `TLWDBNavigator` instead, see Pitfalls 29/41) | 1 |
| render-failed | Construction succeeds but serialization/rendering crashes (e.g., `TDateEdit` NullDate, fallback added in Pitfall 107) | 1 |

The latest classification is authoritative in `docs/CONTROL_MATRIX.md`; this table is only an overview.

There are also 16 non-visual components (`TTimer`/`TOpenDialog`/`TDataSource`/`TMainMenu`...)
usable directly on the server and not included in rendering statistics.

## Mobile (phone / narrow window)

The Alpine rendering layer has built-in mobile adaptation, **zero business code changes**: viewport ≤834px automatically enters
mobile layout (exits at ≥1100px, hysteresis in between prevents jitter); phones/tablets/desktop narrow windows all adapt automatically:

- **No template**: the form renders at design size (font size not reduced); parts beyond the screen scroll
  and pan to view — usable, but not small-screen optimized layout;
- **With template**: write an HTML template for the form (`{%controlName%}` placeholders reference control Name,
  the browser moves existing control DOM into template flow layout), events and incremental patches remain unchanged, automatically switching
  between breakpoints without losing state; template changes take effect on refresh, no recompile:
  - Mobile `<root>\tpl\<form name>.m.html` — single-column mobile layout, form fills viewport;
  - Desktop `<root>\tpl\<form name>.html` — custom desktop layout (centered card,
    two columns, etc.), **form position and size remain design-time**, only client area content becomes flow layout;
- Manual switch: URL `?layout=mobile|desktop` or `LW.layout.set()`;
- **One-click template skeleton generation**: after installing design-time package `lwdesign`, the IDE **Tools menu**
  has an extra item "Generate lazarusWeb Form Template (current unit LFM)" — generates **desktop + mobile** template skeletons at once from the currently open form's
  .lfm to `<project directory>\tpl\` (including `{%controlName%}` placeholders and basic CSS with design-time per-control heights; the main area filling the form
  stretches by **container** height `calc(100% - other controls)` (desktop accumulates by row, mobile adds in single column;
  not `100vh` — when the form opens in a floating window, the client area is smaller than the viewport). If files already exist, asks before overwriting each;
  generation includes a self-check report (skipped non-visual controls, duplicate/illegal placeholder names, nested containers, main area
  changes); after generation, copy to runtime root (or if project directory is runtime root, effective immediately), refresh to see;
  see `MANUAL.md` 16.0; ready example `demos\mobile_demo\tpl\` (manually adjusted proportions),
  the generator itself uses real forms in `demos\gallery` and `demos\dbaware` for parsing and size
  regression (the latter covers main form in floating window, login page without main area, top toolbar + PDF main area);
- **Camera upload**: `TLWCamera` control (drag from component palette and use) — mobile button invokes
  system camera, automatically uploads after shooting (`OnCapture`), instant local preview in browser;
  works over LAN http (no HTTPS required), see README "Camera (TLWCamera)" section;
- Usage in `docs/MANUAL.md` usage section "Mobile", template development guide in
  `MANUAL.md` Part 2 "16. Form Template Development Guide (Desktop + Mobile)", mechanism and
  tests in `docs/MOBILE.md` §8, runnable example `demos/mobile_demo`
  (same form configured with desktop + mobile templates).

## Known limitations

- Single-form applications by default use one thread per session request on one port; during modal, other requests in that session queue on the event queue (consistent with desktop modal semantics);
- Modal timeout `LW_MODAL_TIMEOUT_MS = 180000` (3 minutes);
- Only one dialog at a time: nesting a second dialog in the same session is ignored (browser cannot stack two modals);
- `TOpenDialog` does not read server directory listings — the browser file picker can only "upload files", not browse server disk;
  to select files on the server, build your own UI with `TListView`/`TShellListView` or similar;
- Unsupported controls are gray placeholder boxes in the browser (server remains alive), does not affect other controls;
  see `docs/CONTROL_MATRIX.md` for the specific list;
- `TSplitter` only draws a splitter bar, **dragging is not supported**; `TProgressBar` / `TTrackBar` /
  `TUpDown` adjustments in the browser write back to the server (`TUpDown` arrows also link
  Associate edit box, see `docs/NOTES.md` Pitfall 152);
- High DPI is handled only as virtual display 96 DPI (`lwws.pas` constant can be changed);
  forms designed on Windows with 125%/150% scaling (lfm `DesignTimePPI=120/144`)
  are automatically scaled back to 96 DPI at creation (geometry + font together, driven by `Application.Scaled`,
  see `docs/NOTES.md` Pitfall 18).

## Database applications (TDBGrid / TDBEdit + SQLite)

`demos/db` is a complete CRUD example, `demos/dbaware` is the **DB-aware control suite**
(12 data-aware controls laid out on one page; support matrix in `docs/DB_AWARE_MATRIX.md`).
DB controls bind directly to `TDataSource`; browser behavior is consistent with desktop: click row to locate,
edit fields, Post / Cancel / Delete / Locate.

| DB control | Support |
|---|---|
| TDBGrid / TDBEdit / TDBMemo / TDBComboBox | Full (browse + write-back) |
| TDBCheckBox | Full (for 0/1 fields must set `ValueChecked`/`ValueUnchecked`) |
| TDBListBox / TDBRadioGroup / TDBLookupComboBox / TDBLookupListBox | Full (returns selected item/key value and writes back to field) |
| TDBText / TDBImage | Read-only (text / PNG image follows field in real time) |
| TDBNavigator | Full. lfm must use real class name `TLWDBNavigator` and `RegisterClass(TLWDBNavigator)` — `RegisterClassAlias` cannot replace already registered `TDBNavigator` (Pitfalls 29/41 overturn old solution); code side can also use `LWNewNavigator` factory |

Three hard rules (see `docs/NOTES.md` for details):

1. **SQLite string columns must use `VARCHAR(n)`** — `sqlite3conn` maps `TEXT`/`CHAR`
   to `ftMemo`, and DBGrid only shows `(MEMO)`;
2. **`sqoAutoApplyUpdates` only sends SQL, does not commit transactions** — clicking "Save" in browser appears
   successful, but actually hangs in an uncommitted transaction: when program exits everything rolls back, and another session writing causes
   `database is locked`. After Post/Delete you must explicitly `SQLTransaction.Commit`;
   additionally add `Params.Add('journal_mode=WAL')` + `PRAGMA busy_timeout=10000` to the connection, and before writing `CommitRetaining` to discard old read
   snapshot (WAL's `SQLITE_BUSY_SNAPSHOT` is not governed by busy_timeout). See `docs/NOTES.md` Pitfall 9.2 for complete practice;
3. **The framework does not send grid rows while the dataset is in edit state** (moving cursor triggers automatic Post),
   the browser uses the previous data and automatically refreshes after save/cancel.

## Reports (printing / export)

`src/core/lwreport.pas` is the server-side report engine: one report definition (title + columns + summaries +
paper), three outputs share it:

| Output | Description |
|---|---|
| Printable HTML | A4 `@page`, `@media print`, `thead` repeated per page, zebra stripes, total row; preview page has "Print / Save as PDF" buttons |
| CSV | UTF-8 BOM + CRLF, Excel / WPS double-click without garbled text |
| XLSX | Real OOXML (`zipper` packaging, no third-party library): header styles, frozen panes, column widths, total row |

The "Report Center" form in `demos/dbaware` is a complete example: data source switching, preview (iframe +
view token), clicking "Print..." with `#print` automatically opens print dialog, guest account disables export.

```pascal
rpt := TLWReport.Create(nil);
rpt.DataSet := FQry;
rpt.Title := 'Inventory Detail';
rpt.Columns.AddCol('Code', 'code', 30);
rpt.Columns.AddCol('Amount', 'amount', 34, taRightJustify, rsSum);
rpt.SaveHTML(fn);   // or SaveCSV / SaveXLSX
```

## Custom AJAX endpoints (escape hatch for third-party JS integration)

When you want to embed your own JS / third-party component libraries in the page and request data directly bypassing the component tree protocol,
use `TLWApp.AddAjax` to register an endpoint with any name (name case-insensitive, `/` allowed):

```pascal
TLWApp.AddAjax('items/price',
  function (Ctx: TLWAjaxContext): Boolean
  begin
    Ctx.Json('{"price":299.00}');    // or Ctx.Text(...) / Ctx.Error(...)
    Result := True;
  end);
```

Browser can directly `fetch('/lw/ajax/items?limit=3')`; for cross-page integration add
`--ajax-cors` startup parameter. The context object provides `Param()/Header()/JSONBody()/
FormField()` and `Session` (`?sid=` or `X-LW-Sid` header, can read session-level data).
Complete example: `demos/dbaware/uAjax.pas` (four endpoints items / items/price / whoami / echo,
the "Charts/Other" tab of the main form has a native HTML frame directly fetching them).
Unregistered names return 404 and list all available endpoints for introspection.

## Cross-tab session sharing

The second tab of the same browser no longer "starts a new session and logs in again": sid is stored in
`localStorage`; on startup a new tab first calls `GET /lw/api/attach?sid=…` to attach to the existing session
— login identity, open forms, and server-side data are all there, directly showing the main form.

- Pushes (modal / message box / mask / download instructions...) uniformly enter the session queue with sequence numbers; each tab uses
  `/lw/api/poll?after=N` to fetch its own, without consuming each other;
- Dialog instructions carry `to=<tab identifier>`; only the tab that initiated the event pops up, other tabs do not re-pop;
- Operations in any tab (open form / close form / mask) sync to other tabs in real time;
- When session expires / server restarts, returns 410; browser automatically discards old sid and creates a new session back to login page;
- `?fresh=1` forces a new session (for shared browser or debugging).

Regression: `tests/t_multitab.py` (22 items) + `tests/cdp_multitab.py` (CDP two real tabs, 6 items).

## GUI server panel

Each demo has two builds (using dbaware as example):

| Build method | Artifact | Form |
|---|---|---|
| `dbaware.lpi` (default, `--ws=nogui`) | `dbaware.exe` | Console subsystem: large black terminal prints logs in real time, for tests/CI |
| `dbaware_gui.lpi` (win32 + `-WG`) | `dbaware_gui.exe` | **GUI subsystem**: double-click to run, only a small panel window |

After the GUI version starts, it is a server panel (benchmarking uniGUI standalone server window):

- Title `lazarusWeb 0.9.6 Standalone Server - Port <N>`;
- Menu "File": open browser (F5) / copy access address / exit;
- Menu "Manage": clear log / toggle verbose log / about;
- Middle is scrolling log area (startup banner + session creation + request logs, limited to 4000 lines);
- Status bar three cells: listen address / online sessions (refreshed every second) / uptime;
- **System tray**: resident tray icon (blue background "LW"), clicking X only hides to tray (first time shows
  balloon reminder), left-click icon restores panel, right-click menu: open panel / open browser / exit;
- **Only menu "Exit" truly stops the service** (graceful stop ~0.3s: wake suspended long polling,
  disconnect keep-alive connections, accept loop exits within 250ms, see NOTES Pitfall 44).

Command-line parameters work for both builds: `--nogui` (GUI build falls back to windowless mode,
for service deployment), `--log=path` (log to file). Logs uniformly go through `lwrlog` unit:
console build writes to console, GUI build writes to panel, both can write to file simultaneously.

To make your own program a GUI version, copy `demos/dbaware/dbaware_gui.lpi`:
its only difference from a normal `.lpi` is the `LCLWidgetType=win32` macro +
`-WG` compile option + target name with `_gui` suffix. Note that `.lpr` must not contain
`{$APPTYPE CONSOLE}` (it overrides command-line `-WG`).

## Deployment (HTTPS / reverse proxy / cluster)

HTTPS has two paths, both zero code changes:

1. **Use FPC's built-in TLS directly (recommended, no proxy needed)**: add `--ssl` to the business exe or
   `lwhyper`; the same port changes from HTTP to HTTPS; if no certificate is given, a self-signed certificate is automatically generated.
   Requires shipping `libssl-3-x64.dll` + `libcrypto-3-x64.dll`.
   In cluster scenarios, enable it on the outer lwhyper; workers still use plaintext between each other.
2. **Front reverse proxy**: nginx / Caddy terminates TLS, exe remains HTTP. Complete guide and
   ready configurations in **`deploy/README.md`**, [`deploy/nginx.conf`](deploy/nginx.conf),
   [`deploy/Caddyfile`](deploy/Caddyfile).

`--ssl-host` is the **certificate hostname** (domain/IP in browser address, must match certificate SAN),
not the listen address. For formal CA or private CA non-self-signed certificate command-line examples and intranet
CA generation steps, see `deploy/README.md` §1.1; only when both parameters are empty is a self-signed certificate automatically generated.

Key points:

- Start exe behind proxy with `--trust-proxy` (so IP in logs is the real client IP);
- nginx's `/lw/ws` location must carry `Upgrade`/`Connection` headers (WebSocket),
  otherwise it silently degrades to long polling;
- Cluster = same exe multiple ports + **sticky sessions** (nginx `ip_hash` /
  Caddy `lb_policy ip_hash`): sessions are in process memory; without stickiness "session lost";
- Health check uniformly hits `/lw/healthz` (pure memory read, returns online session count and uptime);
- After instance failure and switchover, browser receives 410 and automatically creates a new session back to login page (fallback chain implemented).

## Dedicated load balancer lwhyper (benchmarking uniGUI Hyper Server)

If you do not want to install nginx, use `tools/lwhyper.exe` as a single process for the cluster (the counterpart of uniGUI Hyper Server):
launches N workers (same business exe multiple instances), automatically restarts on crash, single external port
reverse proxy, sid-based session stickiness, WebSocket TCP-level passthrough, built-in health monitoring.

```
:: build (once)
lazbuild -B --ws=nogui tools\lwhyper.lpi

:: start: 2 workers (dbaware.exe multiple instances), external listen 8080
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\dbaware\dbaware.exe
```

If you do not want to remember parameters, use GUI version `tools\lwhyper_gui.exe` (Windows use
`tools\build_hyper_gui.bat` to build, Linux/macOS use `tools/build.sh hyper_gui`):
fill in business exe / port / worker count in the window and click "Start"; the panel has worker
detail table (port/PID/sessions/restarts), real-time logs, and tray residency (click X to hide, right-click to exit).
GUI version and console version share `src/core/lwhyper.pas`, proxy behavior completely identical.

Open `http://127.0.0.1:8080/` in browser; no difference from direct single instance. Parameters:

```
--port=8080          Listen port (workers default to port+1 sequentially)
--workers=N          Number of worker processes (default 2)
--exe=path           Business exe (required)
--base-port=N        First worker port
--root= / --theme=   Forward to worker
--worker-args="..."  Append verbatim to worker command line (e.g. --trust-proxy)
--logdir=directory   Worker log directory (default <TEMP>\lwhyper)
--ssl                Enable HTTPS on outer layer; workers still use HTTP between each other
--ssl-host=name      Certificate hostname/SAN domain or IP; use self-signed certificate when empty
--ssl-cert=file      Specify PEM certificate (paired with --ssl-key); given automatically enables HTTPS
--ssl-key=file       Specify PEM private key (paired with --ssl-cert)
--tls-cert= / --tls-key=  Aliases for the above two (also automatically enable HTTPS when given)
--hot-update         Hot update (default on): watch for new version exe, rolling restart workers after shell replacement
--no-hot-update      Disable hot update
--update-dir=dir     New version drop directory (place file with same name as business exe; default looks at <exe>.new)
--verbose            Print every proxy request and probe
```

**Hot update (zero-downtime version switch)**: after compiling, copy the new exe to `<business exe>.new` (or drop it into
`--update-dir`); lwhyper will settle in about 4 seconds, replace the shell, and **one by one** restart workers
(at least N-1 serving at any moment); if the new version fails to start, it automatically rolls back and keeps `.bad-<time>`.
Stopping workers uses graceful exit (worker side `POST /lw/shutdown` + token), not force kill.
Mechanism and usage in `docs/WHYPER.md` §5.1 (usage) / §5.2 (implementation).

Own endpoints: `/lw/healthz` (aggregate probe), `/lw/hyper/status` (worker details:
port/pid/alive/session count/restart count/sticky session count).

How it works and boundaries:

- **Stickiness**: sid is on every API call (`?sid=` / `X-LW-Sid`); new sessions are allocated round-robin,
  then stuck to the same worker via table lookup; after lwhyper restart loses the table, requests with unknown sid are forwarded round-robin,
  worker returns 410 → browser automatically rebuilds session (existing fallback chain);
- **Worker crash**: automatically restarted within 2-second probe cycle (`restarts` count visible),
  sessions on that worker are lost with the process (sessions are in process memory; session externalization to Redis not implemented);
- **HTTP scenarios no longer need nginx**; HTTPS can be enabled directly on lwhyper with `--ssl`
  (pure FPC built-in, workers still plaintext; self-signed certificate zero configuration). Front reverse proxy also supported,
  but reverse proxy config no longer needs `ip_hash` / worker list (stickiness managed by lwhyper);
- Regression: `tests/t_hyper.py` (20 items, requires manually starting lwhyper) +
  `tests/t_hyper_ws.py` (6 items WS tunnel, run_with_server fully automatic).

Distribution mechanism (why application-layer stickiness is required, how sid table is maintained, probe/warm-up gate/retry semantics,
why WebSocket is TCP-level passthrough, single point of failure boundaries) see **`docs/LOADBALANCE.md`**.

## Roadmap

- ~~Printing and export~~ ✅ Implemented: `lwreport` report engine (HTML print preview / CSV / XLSX,
  see "Report Center" in `demos/dbaware`). FastReport commercial library not available locally; LazReport
  is strongly tied to LCL preview window/printer (unusable under nogui), so browser printing engine is used.
- ~~WebSocket replacing long polling~~ ✅ Implemented (`lwwebsocket`, `tests/t_ws.py`)
- ~~Server-side direct PDF output~~ Temporarily replaced by browser "Save as PDF" (fcl-pdf has been verified to embed Chinese
  TrueType subsets, but ToUnicode/page output in that version is still unstable)
- ~~Cross-tab session sharing~~ ✅ Implemented (localStorage reuses sid + `/lw/api/attach` +
  cursor-style push queue, see above)
- ~~Cluster/load balancing~~ ✅ Two solutions landed: **lwhyper dedicated load balancer** (see "Dedicated load balancer" section,
  benchmarking uniGUI Hyper Server) and nginx/Caddy sticky sessions (`deploy/nginx.conf`'s
  `ip_hash`, `/lw/healthz` probe, `--trust-proxy`; session externalization to Redis not implemented)
- ~~`lwconvert` deepening~~ ✅ Completed (v2: base class rewrite, startup code rewrite, `.lpi` regeneration, support report, `tests/t_convert.py` end-to-end regression)
- ~~Add renderers for high-frequency placeholder controls~~ ✅ Implemented: `TRadioGroup`/`TCheckGroup`/`TCheckListBox`/`TValueListEditor` (Pitfalls 25/42/97), `TDateEdit`/`TTimeEdit` (Pitfalls 55/70) are all ok, see `docs/CONTROL_MATRIX.md`
- Alpine.js lightweight client ✅ Implemented: **default rendering layer** `lw-alpine.js`, no ext directory needed; Ext JS is optional layer, explicitly enabled with `--client=ext` (Pitfalls 89–97)

## License

This project is open source under the [MIT License](LICENSE):

```
MIT License

Copyright (c) 2026 szlbz(秋风) QQ:315795176
```

Free to use, modify, and distribute (including commercial use), provided the above copyright notice is retained.

### Ext JS (optional dependency) and license notice

- This project **does not include, package, or distribute** any Sencha / Ext JS files (`ext-all.js`,
  theme CSS, charts packages, etc. are all absent). If you need the Ext rendering layer, obtain `ext-<version>` from Sencha's official
  channel and place it in the deployment directory; license compliance is the responsibility of the deployer using Ext JS;
- Ext JS is released by Sencha under GPLv3 / commercial dual licensing. The official GPL version only goes to 7.0.x;
  later versions use commercial licensing — when using the GPLv3 version, follow its open-source terms
  (open application source code, etc.); for commercial closed-source distribution, purchase a commercial license;
- The Ext rendering layer scripts `lw.js` / `lw.css` are original code of this project, distributed with this project under MIT,
  and do not contain or derive from any Sencha code;
- The framework's default rendering layer is Alpine.js (MIT); **deployments without any ext directory are fully
  functional** (startup auto-detection prefers alpine, `?client=` can switch per request);
- Other third-party dependencies: Lazarus/FPC is modified GPL (runtime linking exception);
  please explain this to downstream recipients when distributing.

### Alpine.js (built-in dependency) and license notice

- `src/client/alpine.min.js` (3.14.9 official CDN build, unmodified) **is distributed with this project**
  and is the only built-in third-party runtime file in the release package;
- Alpine.js is released under the MIT license (Copyright (c) Caleb Porzio and Alpine.js
  contributors). To satisfy MIT's "retain copyright and license notice" requirement, the distributed file header
  includes the license notice (with official LICENSE link); do not remove it when redistributing;
- The project's own `lw-alpine.js` / `lw-alpine.css` are original code, distributed under MIT
  (file headers include SPDX declarations);
- The Alpine rendering layer is the framework's default rendering layer; deployment requires no external downloads.

<img width="1836" height="1271" alt="QQ_2026-11-12_17-10-34" src="https://github.com/user-attachments/assets/5b863786-318e-496f-85d9-c603eb295d5a" />
<img width="1845" height="1269" alt="QQ_2026-11-12_17-11-14" src="https://github.com/user-attachments/assets/2f6bb2ff-cae0-4177-b82e-1032c1663d2c" />
<img width="1821" height="1179" alt="QQ_2026-11-12_17-11-33" src="https://github.com/user-attachments/assets/6cf0fb0d-6586-470a-94ca-04641d33620e" />
<img width="1815" height="1170" alt="QQ_2026-11-12_17-11-48" src="https://github.com/user-attachments/assets/305a37e0-0fae-4fb5-b123-fa741f96c0b5" />
<img width="1815" height="1179" alt="QQ_2026-11-12_17-12-04" src="https://github.com/user-attachments/assets/c3ccde1f-ddb7-4089-8073-978f3d0dacaa" />
<img width="1815" height="1184" alt="QQ_2026-11-12_17-12-21" src="https://github.com/user-attachments/assets/5748a74a-e25f-4aed-b3d5-fc23327430b8" />
<img width="1815" height="1173" alt="QQ_2026-11-12_17-12-38" src="https://github.com/user-attachments/assets/54d084f1-e637-4b60-a2ed-7b5f97cccd4f" />
<img width="1809" height="1177" alt="QQ_2026-11-12_17-13-01" src="https://github.com/user-attachments/assets/7fbe0270-3a95-424a-8c35-24fc87f50a05" />
<img width="1815" height="1179" alt="QQ_2026-11-12_17-17-44" src="https://github.com/user-attachments/assets/92e18df9-9ca7-4565-9b78-1e73260f254c" />
<img width="1817" height="1179" alt="QQ_2026-11-12_17-18-11" src="https://github.com/user-attachments/assets/8b8df772-352e-43ad-97e9-f559cfc02b66" />
<img width="1824" height="1173" alt="QQ_2026-11-13_09-15-53" src="https://github.com/user-attachments/assets/90ca9690-cba7-48da-bb30-1cefebaad4d1" />
<img width="1770" height="1118" alt="QQ_2026-11-14_05-46-50" src="https://github.com/user-attachments/assets/c9a81e47-b5a5-45a1-93a2-fd6443108711" />
<img width="895" height="995" alt="ea06f9d6c6f516fa2af43e02e73d267a" src="https://github.com/user-attachments/assets/12276ce3-5c55-403a-b342-b9f2a4831cb3" />
<img width="1280" height="2769" alt="b2340579cb8b66a2d08744b6e7cefff9_720" src="https://github.com/user-attachments/assets/1892599a-91e8-4b40-9a4f-b6214b52cf4a" />
<img width="1083" height="747" alt="c324b8f680f555105b954aeeaf104029" src="https://github.com/user-attachments/assets/008d8db0-8bbd-42a0-b576-6184f0c57960" />
<img width="1284" height="2778" alt="1165bfa448560c9dc2f3cb7e7429f91a" src="https://github.com/user-attachments/assets/52012cd3-bf35-4eb2-b352-cbc791dbb383" />