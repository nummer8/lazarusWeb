# lazarusWeb

A Web runtime for Lazarus desktop applications — it follows uniGUI's approach, but serializes the **real LCL control tree** directly into the UI; the **default rendering layer is Alpine.js** (bundled dependency, zero extra deployment). Ext JS is an optional rendering layer (you must supply the `ext` directory yourself and explicitly enable it with `--client=ext`). Business applications only need to change the form base class from `TForm` to `TLWForm` — all other code (events, properties, `.lfm`) stays as-is, and the program runs as a service in the browser.

Browser (Alpine.js by default / Ext JS optional) — Server (Lazarus, nogui widgetset)

| Browser side (Alpine.js by default, Ext JS optional) | Communication | Server (Lazarus, nogui widgetset) |
| :--- | :---: | :--- |
| `lw-alpine.js` + `alpine.min.js` renderer/coordinator<br>(optional: `lw.js` + `ext-<version>/`)<br><br>Native DOM/CSS (optional: Ext.window/panel/grid/...)<br><br>`events over WS / pushes via long-poll cursor` | <br>**HTTP ←→ JSON**<br><br> | `lwhttp` fcl-web multithreaded server<br>`lwsession` one LCL control tree per browser tab<br>`lwwriter` LCL tree → JSON<br>`lwdispatch` event → RTTI call into business code<br>`lwws` nogui patches (virtual display / canvas) |

## Component Installation  
1、src\lwcore.lpk               —> compile only  
2、src\lwserver.lpk             —> compile only  
3、src\design\lwdesign.lpk —> compile and install  


## Requirements

- FPC 3.3.1/3.2.2 + Lazarus
- Alpine.js (bundled dependency)
- Ext JS 7.0.0 (GPLv3 edition, **optional**: not included in the release package; obtain it yourself from Sencha's official channel and place it into `ext-7.0.0\`; when absent, the built-in Alpine.js rendering layer is used by default)
- **Ext support is an optional feature; the ext-js files must be obtained by the user, and the user is responsible for license compliance.**

## Cross-platform build matrix (host → target)

All source code (`src/`, `tools/`, `demos/`) is cross-platform: platform differences in the core units (timestamp precision / critical-section reentrancy / path style, etc.) are isolated with `$IFDEF MSWINDOWS/LCLGTK2/LCLQT5` and all have non-Windows branches; no Windows-only units are referenced. All `.lpi`/`.lpk` paths use forward slashes and never hard-code the target CPU/OS (artifact names use the `$(TargetCPU)-$(TargetOS)` variables).

**FPC versions**: the same source supports both **FPC 3.2.2 and 3.3.1**. Capabilities added in 3.3.1 (`fphttpserver`'s `RegisterUpdateHandler` / `ThreadMode` / `ConnectionHandler`, plus `SetTextAutoFlush`, `GetHTTPStatusText`, etc.) are wrapped in `{$IF FPC_FULLVERSION >= 30301}` dual branches; under 3.2.2 an equivalent shim is used (manual upgrade takeover in OnRequest, a `select`-based `LWCanRead`, a built-in status-code table, 1-byte text buffering), while under 3.3.1 the native path is used — behavior is identical.

Cross-compilation combinations actually tested (Windows host, nogui widgetset):

| Target | Key command | Artifact |
|---|---|---|
| x86_64-linux | `--os=linux --cpu=x86_64 --ws=nogui --compiler=...ppcrossx64.exe` | `gallery_nogui-x86_64-linux` (ELF x86-64) |
| mips64el-linux | `--os=linux --cpu=mips64el --ws=nogui --compiler=...ppcrossmips64el.exe` | `gallery_nogui-mips64el-linux` (ELF MIPS, verified on Loongson 3A) |

```
lazbuild --os=linux --cpu=mips64el --ws=nogui \
         --compiler=/c/111/fpc/bin/x86_64-win64/ppcrossmips64el.exe \
         demos/gallery/gallery.lpi
# → gallery_nogui-mips64el-linux (ELF, ~6.5MB of code; ld's abicalls
#   mixed-link warning can be ignored)
```

On a Linux host just run `lazbuild` on each demo's `.lpi`; `build.sh` and `build.bat` are functionally equivalent. Directory/file names are case-sensitive on Unix — see the next section.

## Directory structure

| Path | Contents |
|---|---|
| `src/core/lwbase.pas` | Common types, utilities, threadvar session pointer |
| `src/core/lwws.pas` | nogui widgetset patches (**required**, see below) |
| `src/core/lwform.pas` | `TLWForm` business form base class (includes `SendFile` / `SendText`) |
| `src/core/lwwriter.pas` | LCL control tree → JSON |
| `src/core/lwsession.pas` | Sessions, form list, synchronous modal |
| `src/core/lwdispatch.pas` | Browser event → real LCL control event |
| `src/core/lwhttp.pas` | HTTP service, static resources, API routing, upload/download |
| `src/core/lwapp.pas` | Application facade (registration / command line / startup) |
| `src/core/lwconfig.pas` | Server configuration file (INI: Port / Theme / ExtDir) |
| `src/core/lwfileupload.pas` | `TLWFileUpload` upload button control |
| `src/core/lwcamera.pas` | `TLWCamera` photo control (summons the system camera on phones / in-page viewfinder on desktop) |
| `src/core/lwdlg.pas` | **LCL dialogs redirected to the browser** (ShowMessage / MessageDlg / InputQuery / TOpenDialog …) |
| `src/core/lwupload.pas` | multipart parsing and saving to disk |
| `src/core/lwdownload.pas` | Download token table (paths never exposed in URLs) |
| `src/core/lwnewproject.pas` | Project skeleton template (shared by the wizard and `lwnew`) |
| `src/client/lw.js` | Browser-side rendering and incremental reconciliation |
| `src/client/lw.css` | Base styles |
| `src/lwcore.lpk` | Runtime package (widgetset-independent; needed by the design-time package) |
| `src/lwserver.lpk` | Runtime package (server side; automatically applies widgetset patches under nogui) |
| `src/design/lwdesign.lpk` | **Design-time package**: new-project wizard / New Form / component palette |
| `demos/hello` | Minimal example |
| `demos/grid` | Grid example (load/filter/edit/status bar) |
| `demos/multi` | Comprehensive example (menu/multi-tab/toolbar/**synchronous modal**) |
| `demos/db` | **SQLite database example** (TDBGrid/TDBEdit/TDBMemo CRUD, sorting, filtering, category statistics) |
| `demos/files` | **File upload/download example** (TLWFileUpload, SendFile, SendText CSV export) |
| `demos/dbaware` | **Full set of DB-aware controls** (TDBText/TDBListBox/TDBRadioGroup/TDBLookup*/TDBImage data-awareness in practice; 87 objects on the main form, `uAwareMain.lfm` is 866 lines) |
| `demos/dialogs` | **Dialog example** (ShowMessage/MessageDlg/InputQuery/QuestionDlg/MessageBox/OpenDialog/SaveDialog) |
| `demos/gallery` | **Full-feature gallery** (benchmarked against the uniGUI full-feature demo: 12 pages, 60+ controls — standard controls/buttons/extended inputs/containers/grids/toolbars/charts/HTML·PDF·upload/dialogs/timers/DB-aware/large-table paging; `tests/t_gallery.py` 50-item regression) |
| `docs/MAPPING.md` | Control/property mapping table |
| `docs/CONTROL_MATRIX.md` | **Measured support matrix for 66 visual controls** (auto-generated) |
| `docs/DB_AWARE_MATRIX.md` | **Measured matrix for 12 DB-aware controls** (binding/display/sync/write-back, auto-generated) |
| `docs/NOTES.md` | nogui porting pitfalls, accumulated over time as pitfalls 1–108 (important; older conclusions such as pitfalls 23/66 have been superseded by later ones — follow the annotations) |
| `docs/HOW_IT_WORKS.md` | **How it works** (for first-time code readers: the full round trip of one click, and why a full RTTI dump is not possible) |
| `docs/MANUAL.md` | **User manual** (usage part + development part) |
| `docs/FEATURES.md` | **Features and highlights** (one page on where it is strong and where its boundaries are: eleven capabilities / seven decisions done right / numbers at a glance / comparison with uniGUI) |
| `docs/INDEX.md` | Documentation navigation index (find docs by scenario) |

## Quick start

```
cd c:\LazarusWeb
build.bat                 :: build all demos (lazbuild -B --ws=nogui)
build.bat grid            :: build only demos\grid (project name auto-detected, db→dbdemo, files→filedemo)
demos\multi\multi.exe --port=8090
demos\db\dbdemo.exe --port=8095      :: SQLite CRUD example (needs demos\db\sqlite3.dll)
demos\files\filedemo.exe --port=8096 :: upload/download example
demos\dbaware\dbaware.exe --port=8110 :: full set of DB-aware controls
start-gui.bat           :: double-click to start the GUI version (dbaware_gui.exe, see below)
                           Linux/macOS: ./start-gui.sh
```

Open `http://127.0.0.1:8090/` in a browser. Command-line options:

```
--config=path         specify config file (default auto-finds <exe name>.ini / lazarusWeb.ini, see next section)
--port=8090           listening port
--root=C:\LazarusWeb  project root (contains src/client; ext-<version> only needed for the optional Ext layer); defaults to the current directory
--form=Name           default form name
--client=alpine       browser rendering layer: alpine (default, built in) | ext (optional, needs the ext directory); auto-detected when omitted (alpine preferred if both present)
--ext=7.0.0           default Ext version (URL can also temporarily switch with ?ext=<version>)
--extdir=directory    ext-js directory (equivalent to the ExtDir config item)
--theme=crisp         default theme (Ext rendering layer: classic/crisp/gray/material/neptune/graphite;
                      the Alpine layer's color scheme is not here, see below)
--title=title         browser tab title (defaults to Application.Title)
--timeout=20          session idle timeout (minutes)
--trust-proxy         add when behind nginx/Caddy: use X-Forwarded-For for the client IP in logs
--ssl                 enable HTTPS (FPC built-in; auto-generates a self-signed cert if none given)
--ssl-host=name       certificate hostname/SAN domain or IP, not the listening address
--ssl-cert=file       specify PEM certificate (paired with --ssl-key; relative paths resolved against the exe directory)
--ssl-key=file        specify PEM private key (paired with --ssl-cert)
--ajax-cors           allow cross-origin calls to /lw/ajax/* (for third-party page integration)
--verbose             print every request and exception stack
--nogui               don't show the server-side panel even in a GUI build (service deployment)
--patch=1             incremental patches (events return only changed ops, off by default; old frontends fall back to full trees)
--log=path            append server logs to a file
--help                help
```

The parameter table matches the `--help` output of `src/core/lwapp.pas`; the source is authoritative.

### Configuration file (INI)

If you don't want to type a long command line every time, put an INI next to the exe (template: [`lazarusWeb.ini.sample`](lazarusWeb.ini.sample)):

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
| `Port` | Listening port | Uses the default **8090** (warns if out of range) |
| `Theme` | Default theme (Ext rendering layer only; `?theme=` still temporarily overrides); the Alpine layer's color scheme is chosen from the title-bar button, see `docs/MANUAL.md` §5.1 | Uses `crisp` |
| `ExtDir` | ext-js directory, absolute or relative | Auto-finds `<root>\ext-<version>` |
| `Patch` | Incremental patch switch, `1` = events return only changed ops | Default `0` (off) |
| `Client` | Browser rendering layer: `ext` / `alpine` (auto-detected if absent) | Auto-detected |
| `SSL` | Enable HTTPS: `1` / `true` / `yes` | Default `0` (HTTP) |
| `SSLHost` | Certificate hostname/SAN domain or IP; not the listening address | Self-signed cert when empty |
| `SSLCert` | PEM certificate path (paired with `SSLKey`, relative to the exe directory) | Self-signed cert when empty |
| `SSLKey` | PEM private key path (paired with `SSLCert`) | Self-signed cert when empty |

Details (all decided after getting burned):

- **Priority**: built-in defaults < config file < command line. `--port=9000` always beats `Port=8090`, so "one exe copied ten times, each with its own ini" and "temporarily switch ports for debugging" can coexist;
- **Where it lives**: `--config=<path>` explicitly; otherwise it looks for `<exe dir>\<exe name>.ini` → `<exe dir>\lazarusWeb.ini` → `<current dir>\<exe name>.ini` → `<current dir>\lazarusWeb.ini`; a relative `--config=` may also be relative to the exe directory (when started as a service, cwd is often System32);
- **Lenient format**: the section name is optional (`[lazarusWeb]` / `[server]` / none are all accepted); keys are case-insensitive and ignore `-`/`_` (`ext-dir` = `ExtDir`); values may be quoted; `;` and `#` start comments. Save the file as UTF-8 or plain ASCII (Chinese paths written in ANSI will be garbled);
- **`ExtDir` is a "directory", not a "version number"**: give it one, and `/ext/<any version>/...` is served from that directory (a deployment usually carries one ext version); if it points to a nonexistent or empty directory, a warning is printed and it falls back to `<root>\ext-<version>` — the service will not fail to start;
- The startup banner prints the actual config file path and ext directory; look at those two lines first when troubleshooting.

Writing your own Web program (this is all the server-side code there is):

```pascal
program myapp;
uses Interfaces, Forms, lwapp, uMain;
begin
  Application.Initialize;
  TLWApp.Register(TMainForm);   // class name minus the T is the form name in the browser
  TLWApp.Run;                   // automatically calls LWInstallWidgetSet
end.
```

The only line to change in the form unit:

```pascal
uses ..., lwform;
TMainForm = class(TLWForm)   // was class(TForm)
```

> **Important**: compilation must use `-B` (`lazbuild` does not record `.lfm` in the dependency table; if you only change the UI and not the `.pas`, the old `.o` keeps being used).
> `build.bat` already does this.

## Deployment (running from a standalone directory)

The framework **supports** copying the `ext-<version>` directory into the application's own directory for self-contained deployment. When `--root=` is not given, the root directory (Root) is determined in this order:

1. **The current working directory** — as long as it contains an `ext-<version>` directory it is taken as the root. Whichever directory you start from is used, which is the most intuitive.
2. **Up to 5 levels up from the executable's directory** — look for a directory where both `ext-<version>` and `src/client/lw.js` exist (fallback for double-click launches or starting from elsewhere).
3. If none found → `C://LazarusWeb`.
4. An explicit `--root=<path>` has the highest priority and overrides all three above.

Lookups of `/lw/lw.js`, `/lw/lw.css` (and, for Alpine, `/lw/lw-alpine.js`, `/lw/lw-alpine.css`, `/lw/alpine.min.js`) all have multiple fallbacks; all the following layouts work:

| Layout | Required files (one set, depending on rendering layer) |
|---|---|
| Standard repository layout (recommended) | `<root>/src/client/lw.js`, `lw.css`; or `lw-alpine.js`, `lw-alpine.css`, `alpine.min.js` |
| Flat deployment | The above files in the same directory as the exe |
| Semi-flat | The above files under `<exe dir>/lw/` or `<root>/lw/` (old deployments' `<root>/client/` is still supported) |
| Fallback | Search upward from root for files of the same name under `src/client/` |

Minimal self-contained deployment directory (**default Alpine.js rendering layer, no ext directory needed**):

```
MyApp/
  MyApp.exe
  src/client/alpine.min.js   44 KB   Alpine.js itself (defer-loaded, no CDN)
  src/client/lw-alpine.js    205 KB  renderer/coordinator (also the only layer where templates/adaptive layout take effect)
  src/client/lw-alpine.css    59 KB  styles: CSS variables for 7 color schemes (light/beige/eye-care green/high contrast/dark/dark blue/ink green) all live here
  tpl/                              optional: form templates; Alpine layer only, silently falls back to the design-time layout when missing
  favicon.ico                       optional: browser tab icon (put in the exe directory or the --root directory)
  ext-<version>/                    optional: Ext JS rendering layer (~75MB, requires explicit --client=ext to switch)
  cert/                             optional: put server.crt/server.key/ca.crt here when using SSL with your own PEM
  libssl-3-x64.dll + libcrypto-3-x64.dll  optional: required in the exe directory when SSL is enabled
```

(For the Ext rendering layer, substitute `src/client/lw.js` + `lw.css` + `ext-<version>/`; all three alpine files are required — without `alpine.min.js` auto-detection decides alpine is unavailable and falls back to ext, and without the css the page runs but has no styling at all.)

Verification: after startup, check the `Root :` and `Client :` lines in the banner (should be alpine by default), or `curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8090/lw/lw-alpine.js` (should be 200).

### Starting the demo

```bat
start-demo.bat            :: defaults to 8092, just double-click
start-demo.bat 8095       :: specify port
```

```bash
./start-demo.sh           # Linux / macOS, defaults to 8092
./start-demo.sh 8095
```

The service runs in the foreground; open the address it prints in a browser, and stop it with `Ctrl+C` or by closing the window.
(If the port is taken, use another one: after a process is force-killed there may be an orphan socket left in `LISTENING PID 0` state, visible in `netstat` but not killable — switching ports is easiest.)

## Cross-platform (Linux / macOS)

The core units use only FPC/LCL's general facilities: `fphttpserver`, `SysUtils`'s `DirectoryExists`/`FileExists`/`ExtractFileDir`, and path building with `PathDelim` / `IncludeTrailingPathDelimiter` — there are **no** platform units such as `Windows`, `winsock`, or `ShellExecute` (`grep -rn "Windows" src/core/*.pas` only hits comments). `lwws.pas` degrades to an empty implementation under non-nogui widgetsets, so it also compiles under win32/gtk2/qt5/carbon (running with `--ws=nogui` is still recommended).

Building:

```bash
./build.sh                        # all demos
./build.sh dbaware                # a single one
LAZBUILD=/opt/lazarus/lazbuild ./build.sh

tools/build.sh                    # all tools (convert/hyper/audit/dbcheck/hyper_gui/convert_gui)
tools/build.sh convert            # a single tool (compiled directly with fpc, no LCL)
tools/build.sh hyper_gui          # GUI tools are built with the host widgetset
```

`.lpi` files do not pin `TargetOS`/`TargetCPU`, so they build for the host platform; on Unix the artifacts have no `.exe` suffix (`build.sh` deletes both names). On Windows use `build.bat`; the `LAZBUILD` environment variable can override it as well.

Runtime dependency differences:

| Dependency | Windows | Linux | macOS |
|---|---|---|---|
| SQLite (used by demos) | `sqlite3.dll` (shipped in the demo directory) | `libsqlite3.so` (`apt install libsqlite3-0`) | bundled with the system |
| Alpine.js / lw-alpine.js (default); Ext JS / lw.js (optional) | Same as left | Same as left (paths built with `PathDelim`) | Same as left |
| Command-line arguments | `--port=` `--root=` `--theme=` `--config=` | Same as left | Same as left |

Note that Unix filenames are case-sensitive (Windows is not); keep directories/filenames such as `src/client` exactly as they are (the ext directory name can be anything — the server auto-detects the single `ext-*` directory under root).

## Creating a project with the IDE wizard (design-time package `lwdesign`)

Once `src/design/lwdesign.lpk` is installed, three things appear in Lazarus:

| Location | Contents |
|---|---|
| File → New → Project | **lazarusWeb Application** (default widgetset, `$APPTYPE GUI`, F9 runs directly in the IDE with no console window) and **lazarusWeb Application (nogui)** (`LCLWidgetType=nogui` console service, the deployment flavor). The timing of writing to disk matches Lazarus's own templates: choosing a template pops no dialog and writes nothing (the project is "virtual"); only when you save (Ctrl+S) does the standard "Save project" dialog appear, with the directory defaulting to the IDE option's "project build/test directory". This step generates `.lpr/.lpi/umain.pas/.lfm/build.bat/build.sh/favicon.ico` and copies the framework's `src/client` into the project's `lw/` directory (at runtime static resources are found at `exe/lw/<file>`; the site icon `favicon.ico` goes in the project root and the server looks in `<root>` → `<exe directory>` order). The nogui flavor's `.lpi` macros are written **only after the save transaction really ends** (`.lpi` and all units written to disk, stable for two consecutive rounds before acting; no dialogs and no project reload during saving — see NOTES pitfall 172), so they are completed **about 1 second after saving**, and then a prompt says "nogui flavor: takes effect after reloading the project" — click "Yes" to reopen the project, and F9 gives you the windowless console service |
| File → New → File | **lazarusWeb Form** — a `TLWForm` form unit that goes straight into the designer |
| Component palette | The **lazarusWeb** page: `TLWFileUpload` / `TLWCamera`, etc. |

Installation (only once):

```
tools\install_design.bat        :: registers the three packages first
```

Then follow its instructions in the IDE: `Package → Open Package File → lwdesign.lpk → Use → Install`, and let the IDE rebuild once (design-time packages are statically linked into `lazarus.exe`, so a rebuild is required for them to take effect).

Using it for the first time, five steps:

1. **Install the package**: the command above + `Install` to rebuild the IDE (reinstall whenever the package is updated, otherwise the old code still runs);
2. **Create**: `File → New → Project`, choose a template (GUI flavor for debugging / nogui flavor for deployment); nothing is written when you choose;
3. **Save**: `Ctrl+S` brings up the standard "Save project" dialog and only then is anything written. Don't name the project `LWApp` (it clashes with `lwapp.pas` and fails with `Duplicate identifier "LWAPP"`); the default `LWApp1` is safe;
4. **One extra step for the nogui flavor**: about 1 second after saving, a prompt "nogui flavor: takes effect after reloading the project" appears — click **"Yes"**;
5. **F9**.

> **Note: pressing F9 within 1 second of saving still uses the win32 widgetset** — the macro has just been written into the `.lpi` file but the IDE's in-memory project options haven't been re-read, so the build still pops up a server panel window. Wait for the prompt in step 4, click "Yes", and then F9 is correct; if you don't want to reopen the project, use the `build.bat` in the project directory.

The list of files written, the UI details of each step, and troubleshooting (`%TEMP%\lazarusweb-wizard.log`) are in `docs/MANUAL.md`, "Creating a project with the IDE wizard (building one from scratch)".

> TLWForm is a **genuine TForm descendant**, not a shadow class like uniGUI's, so no design-time proxies are needed: a TButton/TEdit you drop on it is LCL's own control, and the property panel, events page, alignment tools, and anchors all work as usual — the layout you see in the form designer is the layout in the browser.

If you don't want to open the IDE, you can also generate a project skeleton from the command line (this generates a Lazarus project, not form templates; for template skeletons use the IDE Tools menu above):

```
tools\lwnew.exe --name=DemoApp --dir=C:\work\DemoApp --units=C:\LazarusWeb\src\core
```

When `--units` specifies the source directory, no installed packages are required; if omitted, the `lwserver` package must already be registered.

**How it is built**: which widgetset LCL uses is decided by the `LCLWidgetType` macro in the `.lpi`. The demos in the repository and hand-converted legacy projects don't have this macro, so pressing F9 in the IDE uses the IDE's own widgetset (win32) and fails to link LCL's nogui units — only lazbuild can specify it. Wizard-generated nogui projects already have this macro in the `.lpi`, so after reloading the project F9 in the IDE gives nogui directly (pressing F9 within 1 second of saving is still win32, see the previous section). `build.bat` writes both forms:

```
lazbuild -B --ws=nogui <project>.lpi
```

> Note the difference: **packages** (`lwserver.lpk`) can be compiled/installed directly in the IDE — `lwws.pas`'s nogui patches are wrapped in `{$IFDEF LCLnogui}` and degrade to empty implementations under non-nogui; but **projects without the `LCLWidgetType` macro** (demos, hand-converted legacy projects) require `--ws=nogui`, see `docs/NOTES.md` pitfall 15.

## File upload / download

Uploads use `TLWFileUpload` (a `TButton` descendant, placeable at design time):

```pascal
procedure TFileForm.btnUploadUpload(Sender: TObject; const AFileName: string);
begin
  // AFileName is the full path on the server; open it directly with TFileStream
  lstFiles.Items.Add(ExtractFileName(AFileName));
end;
```

- The browser opens the system file dialog; XHR uploads with progress, and the button text shows the percentage in real time;

## Taking photos (TLWCamera)

`TLWCamera` (a specialized descendant of `TLWFileUpload`) — just drop it on the form:

```pascal
procedure TMainForm.camPhotoCapture(Sender: TObject; const AFileName: string);
begin
  // The photo has already been saved on the server (uploads\<session>\camPhoto\xxx.jpg)
end;
```

- Phone/tablet: clicking the button directly summons the **system camera** (`Facing` switches front/rear), and after taking the photo it is sent back through the existing upload channel and `OnCapture` fires; **plain HTTP on the LAN works**;
- Desktop: under HTTPS or localhost an **in-page viewfinder** pops up (getUserMedia, live preview + capture/cancel/choose image); the captured frame is scaled to 1600px on the long side, converted to JPEG, and sent through the same channel. On a desktop page served over LAN HTTP, browsers forbid camera access, so it automatically degrades to "choose an image file";
- Preview: `PreviewImage := 'imgPhoto'` — the browser displays the shot locally in the specified TImage immediately; the photo data does not travel in the control-tree patch; the server only gets the file path;
- Full description in `docs/MANUAL.md`, usage part, "Taking photos"; example `demos/mobile_demo`; regression `tests/cdp_camera.py`.
- The server parses `multipart/form-data` and saves to `%TEMP%\lw_uploads\<session id>\<control name>\` (or use `TargetFolder` to specify);
- Filenames are sanitized (path stripped, `..` removed, illegal characters removed); with multi-select, `OnUpload` fires once per file;
- `Filter` (`'Text|*.txt;*.csv|All|*.*'`), `Multiple`, and `MaxSizeKB` all take part in validation.

Downloading is one line in business code:

```pascal
SendFile('C:\data\report.xlsx');            // push an existing server-side file
SendText(csv.Text, 'list.csv', True);       // compute text and download directly (True = with BOM, so Excel handles Chinese correctly)
```

The URL **never** contains a server path: `SendFile` registers the file as a one-time token and the browser only gets `/lw/download?t=<token>`, which expires after 30 minutes or on first use.

| Route | Description |
|---|---|
| `POST /lw/api/upload?sid=&id=` | `multipart/form-data`, returns the new control tree |
| `GET /lw/download?t=<token>` | With `Content-Disposition` (including `filename*=UTF-8''`) |

**Complete business example**: `demos\db` attaches files to each product (upload → saved under `attachments\item<id>\` + write to the `attachments` table → download/delete), using a separate database connection for the attachment write so the record being edited is not interrupted — see "How attachments are wired in" in `demos\db\README.md`.

## Dialogs (ShowMessage / MessageDlg / TOpenDialog …)

**Not a single line of business code changes.** These LCL functions on the server are redirected to "pop up a modal in the browser"; the server thread waits there for the user to click, then continues:

```pascal
procedure TMainForm.Button1Click(Sender: TObject);
begin
  if OpenDialog1.Execute then              // browser shows a file picker
    mmoLog.Lines.Add(OpenDialog1.FileName); // returns a server-side temp path
  ShowMessage('lazarus Web test');          // browser shows a message box
end;
```

Available directly (no code, no replacement needed):

| LCL entry point | What you see in the browser |
|---|---|
| `ShowMessage` / `ShowMessagePos` | Icon-less message box + OK |
| `MessageDlg` / `MessageDlgPos` | Info/warning/error/question icon per `TMsgDlgType` |
| `InputQuery` / `InputBox` / `PasswordBox` | With an input field (`PasswordBox` is a password field) |
| `QuestionDlg` | Custom button captions, `ModalResult` returned as-is |
| `Application.MessageBox` / `LCLIntf.MessageBox` | Flags such as `MB_YESNO` parsed with Windows semantics |
| `TOpenDialog.Execute` | Pick a file (**uploaded to the server first**), `FileName` = server path |
| `TSaveDialog.Execute` | Enter a filename, `FileName` = a path in the session temp directory |

A few things you must know:

- **File dialogs give you server paths.** A browser cannot hand local paths to the server, so the chosen file is uploaded as `multipart` to `%TEMP%\lw_uploads\<session id>\pick\`, and `FileName` is that path — `TFileStream` can open it directly. Saving works the same way: `TSaveDialog.FileName` lands in `...\<session id>\save\`; after writing the file, call `SendFile` to push it to the user.
- **The thread really blocks.** The event request hangs until the user answers (or the 180-second timeout), matching the behavior of a desktop modal; other sessions keep running normally, and a second dialog in the same session is rejected with a message.
- **With no browser session** (for example pressing F9 in the IDE, or running unit tests from the command line) it automatically falls back to the original LCL implementation.
- These are all **runtime replacements**; `lwdlg.pas` lives in the `lwcore` package and takes effect as soon as the business project `uses lwapp` (`LWInstallDialogs` is installed before `TLWApp.Run`, hooking `InterfaceBase`'s `PromptDialogFunction` / `InputDialogFunction` / `QuestionDialogFunction` / `Forms.MessageBoxFunction` and `RegisterWSComponent(TOpenDialog, …)`).

**Complete example and HTTP-level tests**: `demos\dialogs` (7 buttons, one per dialog type), `tests\t_dialog.py` (36 items, covering the whole chain "push → answer → wake up → return value").

## Runtime behavior (correspondence with uniGUI)

| uniGUI | lazarusWeb |
|---|---|
| TUniSession | TLWSession (one per browser tab) |
| Component → JS mapping | lwwriter + lw.js incremental reconciliation |
| Synchronous modal (nested message loop) | `ShowModal` pushes a command and suspends the request thread; `TEvent.WaitFor` waits for the browser to close |
| Ajax event | `POST /lw/api/event`, values written back to controls first, then the event is triggered via RTTI |

Business code is completely unaware that the Web exists:

```pascal
procedure TMainForm.miAboutClick(Sender: TObject);
var f: TAboutForm;
begin
  f := TAboutForm.Create(nil);
  try
    if f.ShowModal = mrOk then          // under the Web this line waits for the user to click OK
      lblState.Caption := 'About viewed';
  finally
    f.Free;
  end;
end;
```

## HTTP API

| Route | Description |
|---|---|
| `GET /` | UI shell (`?ext=7.0.0&form=MainForm` overrides defaults; `?fresh=1` forces a new session) |
| `POST /lw/api/session` | Create session `{form:"MainForm"}` → returns tree + `sid` + `seq` |
| `GET /lw/api/attach?sid=` | **Cross-tab sharing**: attach this tab to an existing session (410 + `gone` if it doesn't exist) |
| `GET /lw/api/tree?sid=` | Current control tree |
| `POST /lw/api/event` | `{sid,id,ev,val,row,col,vals,tab}` → new control tree |
| `GET /lw/api/poll?sid=&t=&after=` | Long polling. With `after`, fetch pushes by cursor (each tab gets its own); without it, the old destructive queue. **The only push channel** |
| `GET /lw/ws?sid=` | WebSocket upgrade (RFC6455): **only carries event requests/responses** (when connected, events go over WS frames); pushes never go over WS — they are always delivered by the long-poll cursor above, and it falls back to HTTP automatically on disconnect |
| `GET /lw/api/log?sid=` | Session log (all Show/ShowModal/EndModal records) |
| `POST /lw/api/close` | End session |
| `POST /lw/api/dlg` / `POST /lw/api/dlgfile` | Endpoints for answers to browser modals (ShowMessage/MessageDlg/InputQuery/TOpenDialog…), see the dialog section of `docs/MAPPING.md` |
| `POST /lw/api/upload?sid=&id=` | File upload (`multipart/form-data`, any field name, multiple files allowed) |
| `GET /lw/download?t=` | Download (`t` is a one-time token registered by `lwdownload`, invalid after use) |
| `GET /lw/ajax/<name>` | **Custom AJAX endpoint**: registered with `TLWApp.AddAjax(name, handler)`, third-party JS can fetch it directly |
| `GET /lw/healthz` | Health check (LB/k8s probes): `{"ok":true,"sessions":..,"uptime":..}` |
| `GET /ext/<version>/<path>` | Ext JS static resources (two versions can coexist) |
| `GET /favicon.ico` | Site icon: `--root` directory → exe directory → 204 if neither; on a hit, 200 + `Cache-Control: public, max-age=86400`. Both shell HTML heads include `<link rel="icon">` |

## Control support (measured)

`docs/CONTROL_MATRIX.md` is auto-generated by `tools\lwaudit` (snapshot: 2026-11-09; fixes after that date are in `docs/NOTES.md` pitfalls 97/107): each of the 66 commonly used LCL visual controls is **actually created + attached to a form + serialized once** under nogui, then cross-checked against whether `lw.js` really has a rendering branch, yielding five categories:

| Status | Meaning | Current count |
|---|---|---:|
| ok | Rendered as a real control in the browser, two-way events work | 49 (74.2%) |
| placeholder | Usable on the server, browser only draws a box with a class name | 14 |
| kind-only | kind is mapped but the rendering branch is missing | 1 |
| create-failed | Constructor throws under nogui (e.g. native `TDBNavigator` depends on button glyphs; use `TLWDBNavigator` instead, see pitfalls 29/41) | 1 |
| render-failed | Constructs fine but serialization/rendering crashes (e.g. `TDateEdit` NullDate; fallback added in pitfall 107) | 1 |

The latest classification is in `docs/CONTROL_MATRIX.md`; this table is only an overview.

There are also 16 non-visual components (`TTimer`/`TOpenDialog`/`TDataSource`/`TMainMenu`…) usable directly on the server; they are not counted in rendering statistics.

## Mobile (phone / narrow window)

The Alpine rendering layer has built-in mobile adaptation, **with zero changes to business code**: viewports ≤834px automatically switch to the mobile layout (exiting at ≥1100px, with hysteresis in between to prevent flapping); phones/tablets/narrow desktop windows all adapt automatically:

- **Without a template**: the form renders at its design size (font size not shrunk), and parts beyond the screen are reached by scrolling/panning — usable, but not a small-screen-optimized arrangement;
- **With a template**: write an HTML template for the form (`{%ControlName%}` placeholders reference control Names; the browser moves the existing control DOM into the template's flow layout), and events and incremental patches work as before, switching automatically between the two breakpoints without losing state; template changes take effect on refresh, no rebuild needed:
  - Mobile `<root>\tpl\<form name>.m.html` — single-column layout for phones, form fills the viewport;
  - Desktop `<root>\tpl\<form name>.html` — custom desktop layout (centered card, two columns, etc.); **the form's position and size stay as designed**, only the client-area content becomes flow-based;
- Manual switching: URL `?layout=mobile|desktop` or `LW.layout.set()`;
- **One-click template skeleton generation**: after installing the design-time package `lwdesign`, the IDE's **Tools menu** gains an item "Generate lazarusWeb form template (current unit LFM)" — it generates **desktop + mobile** template skeletons in one go from the currently open form's `.lfm` into `<project dir>\tpl\` (with `{%ControlName%}` placeholders and basic CSS giving each control its design-time height; the main area that fills the form stretches by **container** height `calc(100% - other controls)` (accumulated per row on desktop, simply added in the mobile single column; not `100vh` — when the form opens in a floating window the client area is smaller than the viewport)); existing files are individually prompted before overwriting; a self-check report is attached (skipped non-visual controls, duplicate/illegal placeholder names, nested containers, main-area changes); after generation, copy to the runtime root (or it takes effect directly if the project directory is the runtime root) and refresh. See `MANUAL.md` 16.0; ready-made example `demos\mobile_demo\tpl\` (hand-tuned proportions); the generator itself uses the real forms of `demos\gallery` and `demos\dbaware` for parsing and sizing regressions (the latter covers a main form inside a floating window, a login page with no main area, and a top toolbar row + PDF main area);
- **Photo upload**: the `TLWCamera` control (drag from the component palette and use) — tapping the button on a phone summons the system camera, and after shooting it is automatically uploaded back to the server (`OnCapture`) with instant local preview in the browser; LAN HTTP works (no HTTPS needed), see the "Taking photos (TLWCamera)" section of the README;
- Usage is described in the "Mobile" section of `docs/MANUAL.md`, the template development guide is in `MANUAL.md` part two "16. Form template development guide (desktop + mobile)", the mechanism and measurements are in `docs/MOBILE.md` §8, and there is a runnable example `demos/mobile_demo` (the same form with both desktop and mobile templates).

## Known limitations

- A single-form application runs one thread per session request by default; during a modal, other requests for that session queue on the event queue (consistent with desktop modal semantics);
- Modal timeout `LW_MODAL_TIMEOUT_MS = 180000` (3 minutes);
- Only one dialog at a time: a nested second dialog in the same session is ignored (the browser cannot stack two modals);
- `TOpenDialog` does not read server directory listings — the browser picker can only "upload a file", not browse the server disk; to pick files on the server, build your own UI with `TListView`/`TShellListView` or similar;
- Unsupported controls appear as gray placeholder boxes in the browser (the server side is alive as usual) and don't affect other controls; the specific list is in `docs/CONTROL_MATRIX.md`;
- `TSplitter` only draws the divider, **dragging is not supported**; adjustments to `TProgressBar` / `TTrackBar` / `TUpDown` in the browser are all written back to the server (`TUpDown` arrow buttons also link to the Associate edit box, see `docs/NOTES.md` pitfall 152);
- High DPI is handled only at the virtual display's 96 DPI (the constant in `lwws.pas` can be changed); forms designed on Windows at 125%/150% scaling (`DesignTimePPI=120/144` in the lfm) are automatically scaled back to 96 DPI at creation time (geometry and fonts together, driven by `Application.Scaled`, see `docs/NOTES.md` pitfall 18).

## Database applications (TDBGrid / TDBEdit + SQLite)

`demos/db` is a complete CRUD example, and `demos/dbaware` is a **full set of DB-aware controls** (12 data-aware controls laid out on one page; support levels in `docs/DB_AWARE_MATRIX.md`).
DB controls bind directly to `TDataSource`, and behavior in the browser matches the desktop program: click a row to position, edit fields, Post / Cancel / Delete / Locate.

| DB control | Support |
|---|---|
| TDBGrid / TDBEdit / TDBMemo / TDBComboBox | Full (browse + write-back) |
| TDBCheckBox | Full (for 0/1 fields you must set `ValueChecked`/`ValueUnchecked`) |
| TDBListBox / TDBRadioGroup / TDBLookupComboBox / TDBLookupListBox | Full (returns the selected item/key value and writes it back to the field) |
| TDBText / TDBImage | Read-only (text / PNG images follow the field in real time) |
| TDBNavigator | Full. The lfm must use the real class name `TLWDBNavigator` and `RegisterClass(TLWDBNavigator)` — `RegisterClassAlias` cannot replace an already-registered `TDBNavigator` (pitfalls 29/41 overturn the old approach); the code side can also use the `LWNewNavigator` factory |

Three hard rules (see `docs/NOTES.md` for details):

1. **Always use `VARCHAR(n)` for SQLite string columns** — `sqlite3conn` maps `TEXT`/`CHAR` to `ftMemo`, and DBGrid only shows `(MEMO)`;
2. **`sqoAutoApplyUpdates` only issues SQL, it does not commit the transaction** — clicking "Save" in the browser looks successful, but the changes sit in an uncommitted transaction: when the program exits everything rolls back, and another session writing causes `database is locked`. After Post/Delete you must explicitly `SQLTransaction.Commit`; add `Params.Add('journal_mode=WAL')` + `PRAGMA busy_timeout=10000` to the connection, and call `CommitRetaining` before writing to drop the old read snapshot (WAL's `SQLITE_BUSY_SNAPSHOT` is not governed by busy_timeout). The complete approach is in `docs/NOTES.md` pitfall 9.2;
3. **The framework does not send grid rows while the dataset is in edit state** (moving the cursor triggers an automatic Post), so the browser keeps using the previous data and refreshes automatically after save/cancel.

## Reports (printing / export)

`src/core/lwreport.pas` is the server-side report engine: a single report definition (title + columns + totals + paper) serves three outputs:

| Output | Description |
|---|---|
| Printable HTML | A4 `@page`, `@media print`, `thead` repeated on each page, zebra striping, totals row; the preview page has its own "Print / Save as PDF" buttons |
| CSV | UTF-8 BOM + CRLF, no garbling when opened by Excel / WPS |
| XLSX | Real OOXML (packaged with `zipper`, no third-party library): header styles, frozen panes, column widths, totals row |

The "Report Center" form in `demos/dbaware` is a complete example: data source switching, preview (iframe + view token), clicking "Print…" appends `#print` to auto-open the print dialog, and export is disabled for the guest account.

```pascal
rpt := TLWReport.Create(nil);
rpt.DataSet := FQry;
rpt.Title := 'Large inventory table details';
rpt.Columns.AddCol('Code', 'code', 30);
rpt.Columns.AddCol('Amount', 'amount', 34, taRightJustify, rsSum);
rpt.SaveHTML(fn);   // or SaveCSV / SaveXLSX
```

## Custom AJAX endpoints (escape hatch for third-party JS integration)

When you want to embed your own JS / a third-party component library in the page and get data directly, bypassing the control-tree protocol, register an endpoint with any name using `TLWApp.AddAjax` (names are case-insensitive and may contain `/`):

```pascal
TLWApp.AddAjax('items/price',
  function (Ctx: TLWAjaxContext): Boolean
  begin
    Ctx.Json('{"price":299.00}');    // or Ctx.Text(...) / Ctx.Error(...)
    Result := True;
  end);
```

From the browser just `fetch('/lw/ajax/items?limit=3')`; for cross-page integration add the `--ajax-cors` startup option. The context object provides `Param()/Header()/JSONBody()/FormField()` and `Session` (`?sid=` or the `X-LW-Sid` header, for reading session-level data).
Complete example: `demos/dbaware/uAjax.pas` (four endpoints: items / items/price / whoami / echo; the "Charts/Other" tab of the main form has a native HTML frame that fetches them directly).
Unregistered names return 404 and list all available endpoints, for self-discovery.

## Cross-tab session sharing

A second tab of the same browser no longer "starts a new session and logs in again": the sid is stored in `localStorage`, and a new tab first calls `GET /lw/api/attach?sid=…` to attach to the existing session — login identity, open forms, and server-side data are all there, and the main form appears immediately.

- Pushes (modal / message box / mask / download commands…) all go into a numbered session queue, and each tab fetches its own with `/lw/api/poll?after=N` without consuming others';
- Dialog commands carry `to=<tab id>`, so only the tab that raised the event shows the dialog and other tabs don't re-show it;
- Actions in any tab (open form / close form / mask) are synced to other tabs in real time;
- When the session expires or the service restarts, it returns 410 and the browser automatically drops the old sid, creates a new session, and returns to the login page;
- `?fresh=1` forces a new session (for multiple people sharing one browser, or for debugging).

Regression: `tests/t_multitab.py` (22 items) + `tests/cdp_multitab.py` (CDP, two real tabs, 6 items).

## GUI server panel

Each demo has two builds (dbaware as an example):

| Build | Artifact | Form |
|---|---|---|
| `dbaware.lpi` (default, `--ws=nogui`) | `dbaware.exe` | Console subsystem: a big black terminal printing logs in real time, for tests/CI |
| `dbaware_gui.lpi` (win32 + `-WG`) | `dbaware_gui.exe` | **GUI subsystem**: double-click to run, only a small panel window |

After the GUI version starts, it shows a server panel (the counterpart of uniGUI standalone server's window):

- Title `lazarusWeb 0.9.6 standalone server - port <N>`;
- "File" menu: open browser (F5) / copy access address / exit;
- "Manage" menu: clear log / toggle verbose logging / about;
- The middle is a scrolling log area (startup banner + session creation + request logs, capped at 4000 lines);
- Three status-bar cells: listening address / online sessions (refreshed every second) / uptime;
- **System tray**: a resident tray icon (blue background, "LW"); clicking X only hides to the tray (with a balloon hint the first time), left-clicking the icon restores the panel, and the right-click menu has: open panel / open browser / exit;
- **Only the "Exit" menu item actually stops the service** (graceful shutdown in ~0.3s: wakes up suspended long polls, closes keep-alive connections, accept loop exits within 250ms, see NOTES pitfall 44).

Command-line arguments apply to both builds: `--nogui` (falls back to windowless mode in a GUI build, for service deployment), `--log=path` (write logs to a file). Logging goes through the `lwrlog` unit uniformly: console builds write to the console, GUI builds write to the panel, and both can write to a file at the same time.

To make your own program a GUI build, just copy `demos/dbaware/dbaware_gui.lpi`: the only differences from a normal `.lpi` are the `LCLWidgetType=win32` macro + the `-WG` compiler option + the `_gui` suffix on the target name. Note that the `.lpr` must not contain `{$APPTYPE CONSOLE}` (it overrides the command-line `-WG`).

## Deployment (HTTPS / reverse proxy / cluster)

There are two ways to get HTTPS, both requiring zero code changes:

1. **Use FPC's built-in TLS directly (recommended, no proxy needed)**: add `--ssl` to the business exe or `lwhyper` and the same port switches from HTTP to HTTPS; if no certificate is given, a self-signed one is generated automatically. You need to ship `libssl-3-x64.dll` + `libcrypto-3-x64.dll` with the package. In cluster scenarios just enable it on the outer `lwhyper`; workers still talk plaintext among themselves.
2. **Front it with a reverse proxy**: nginx / Caddy terminates TLS and the exe stays HTTP. Complete guide and ready-made configs in **`deploy/README.md`**, [`deploy/nginx.conf`](deploy/nginx.conf), [`deploy/Caddyfile`](deploy/Caddyfile).

`--ssl-host` is the **certificate hostname** (the domain/IP in the browser's address, which must match the certificate SAN), not the listening address. For command-line examples with a real CA or a private CA's non-self-signed certificate, and steps for generating an internal CA certificate, see `deploy/README.md` §1.1; only when both parameters are empty is a self-signed certificate generated automatically.

Key points:

- Start the exe with `--trust-proxy` behind a proxy (so the IP in logs is the real client IP);
- nginx's `/lw/ws` location must carry the `Upgrade`/`Connection` headers (WebSocket), otherwise it silently degrades to long polling;
- Cluster = the same exe on multiple ports + **sticky sessions** (nginx `ip_hash` / Caddy `lb_policy ip_hash`): sessions live in process memory, so without stickiness you "lose sessions";
- Health checks should all hit `/lw/healthz` (a pure in-memory read, returning online sessions and uptime);
- After an instance goes down and traffic switches over, the browser receives 410 and automatically creates a new session back at the login page (the fallback chain is already implemented).

## Dedicated load balancer lwhyper (the counterpart of uniGUI Hyper Server)

If you don't want to install nginx, use `tools/lwhyper.exe` — a single process that does the whole cluster job (the equivalent of uniGUI Hyper Server): launches N workers (multiple instances of the same business exe), auto-restarts on crash, reverse-proxies a single external port, keeps session stickiness by sid, tunnels WebSocket at the TCP level, and does its own health monitoring.

```
:: build (once)
lazbuild -B --ws=nogui tools\lwhyper.lpi

:: start: 2 workers (multiple dbaware.exe instances), listening on 8080
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\dbaware\dbaware.exe
```

If you don't want to remember arguments, use the GUI version `tools\lwhyper_gui.exe` (on Windows build with `tools\build_hyper_gui.bat`, on Linux/macOS with `tools/build.sh hyper_gui`): fill in the business exe / port / worker count in the window, click "Start", and the panel shows a worker detail table (port/PID/sessions/restarts), live logs, and a resident tray (clicking X hides it, right-click to exit). The GUI version and the console version share `src/core/lwhyper.pas` and proxy identically.

Open `http://127.0.0.1:8080/` in a browser — indistinguishable from connecting directly to a single instance. Parameters:

```
--port=8080          listening port (worker ports default to port+1 in sequence)
--workers=N          number of worker processes (default 2)
--exe=path           business exe (required)
--base-port=N        port of the first worker
--root= / --theme=   forwarded to workers
--worker-args="..."  appended verbatim to the worker command line (e.g. --trust-proxy)
--logdir=directory   worker log directory (default <TEMP>\lwhyper)
--ssl                enable HTTPS on the outside; workers still use HTTP among themselves
--ssl-host=name      certificate hostname/SAN domain or IP; empty means a self-signed certificate
--ssl-cert=file      specify PEM certificate (paired with --ssl-key)
--ssl-key=file       specify PEM private key (paired with --ssl-cert)
--hot-update         hot update (on by default): watch for a new exe, swap the shell, then roll-restart workers
--no-hot-update      disable hot update
--update-dir=dir     directory to drop new versions into (put a file with the same name as the business exe; defaults to <exe>.new)
--verbose            print every proxied request and probe
```

**Hot update (zero-downtime version swap)**: after compiling, copy the new exe to `<business exe>.new` (or drop it into `--update-dir`); lwhyper makes a decision after about 4 seconds and swaps the shell, then **restarts workers one at a time** (at least N-1 serving at any moment); if the new version fails to start it rolls back automatically and keeps a `.bad-<time>` copy. Stopping a worker is a graceful shutdown (worker-side `POST /lw/shutdown` + token), not a force kill. Mechanism and usage in `docs/WHYPER.md` §5.1 (usage) / §5.2 (implementation).

Its own endpoints: `/lw/healthz` (aggregate probe), `/lw/hyper/status` (worker details: port/pid/alive/session count/restarts/sticky session count).

How it works and its boundaries:

- **Stickiness**: the sid is on every API call (`?sid=` / `X-LW-Sid`); new sessions are assigned round-robin and then pinned to the same worker via a table; if lwhyper restarts and loses the table, requests with unknown sids are forwarded round-robin and the worker returns 410 → the browser automatically rebuilds the session (the existing fallback chain);
- **Worker crash**: automatically restarted within the 2-second probe cycle (`restarts` count is visible); sessions on that worker are lost with the process (sessions live in process memory; externalizing them to Redis is not implemented);
- **HTTP scenarios no longer need nginx**; for HTTPS just add `--ssl` to lwhyper (pure FPC built-in, workers still plaintext; self-signed certificate needs zero configuration). A fronting reverse proxy is also supported, but its configuration no longer needs `ip_hash` / a worker list (stickiness is handled by lwhyper);
- Regression: `tests/t_hyper.py` (20 items, requires starting lwhyper manually) + `tests/t_hyper_ws.py` (6 WS tunnel items, fully automated by run_with_server).

Distribution mechanics (why application-level stickiness is required, how the sid table is maintained, probe/warm-up gate/retry semantics, why WebSocket is tunneled at TCP level, single-point-of-failure boundaries) are in **`docs/LOADBALANCE.md`**.

## Roadmap

- ~~Printing and export~~ ✅ Implemented: the `lwreport` report engine (HTML print preview / CSV / XLSX, see the Report Center in `demos/dbaware`). The commercial FastReport library isn't available on this machine, and LazReport is tightly coupled to LCL preview windows/printers (unusable under nogui), so the browser print engine is used instead.
- ~~WebSocket instead of long polling~~ ✅ Implemented (`lwwebsocket`, `tests/t_ws.py`)
- ~~Server-side direct PDF output~~ Temporarily replaced by the browser's "Save as PDF" (fcl-pdf has been verified to embed Chinese TrueType subsets, but in that version ToUnicode/page output is not yet stable)
- ~~Cross-tab session sharing~~ ✅ Implemented (localStorage reuses the sid + `/lw/api/attach` + cursor-based push queue, see above)
- ~~Cluster / load balancing~~ ✅ Two solutions delivered: the **lwhyper dedicated load balancer** (see the "Dedicated load balancer" section, the counterpart of uniGUI Hyper Server) and nginx/Caddy sticky sessions (`ip_hash` in `deploy/nginx.conf`, `/lw/healthz` probes, `--trust-proxy`; externalizing sessions to Redis is not implemented)
- ~~Deepening `lwconvert`~~ ✅ Done (v2: base class rewriting, startup code rewriting, `.lpi` regeneration, support reports, `tests/t_convert.py` end-to-end regression)
- ~~Add renderers for the high-frequency controls among the placeholders~~ ✅ Implemented: `TRadioGroup`/`TCheckGroup`/`TCheckListBox`/`TValueListEditor` (pitfalls 25/42/97) and `TDateEdit`/`TTimeEdit` (pitfalls 55/70) are all ok now, see `docs/CONTROL_MATRIX.md`
- Alpine.js lightweight client ✅ Implemented: the **default rendering layer** `lw-alpine.js`, no ext directory needed; Ext JS is an optional layer that must be explicitly enabled with `--client=ext` (pitfalls 89–97)

## Open-source license

This project is open-sourced under the [MIT License](LICENSE):

```
MIT License

Copyright (c) 2026 szlbz (秋风) QQ:315795176
```

Free to use, modify, and distribute (including commercially), provided the above copyright notice is retained.

### Ext JS (optional dependency) and license notice

- This project **does not ship, bundle, or distribute** any Sencha / Ext JS files (`ext-all.js`, theme CSS, charts packages, etc. are all excluded). If you need the Ext rendering layer, obtain `ext-<version>` yourself from Sencha's official channel and place it in the deployment directory; license compliance for Ext JS is the responsibility of the deployer using it;
- Ext JS is published by Sencha under dual GPLv3 / commercial licensing; the official GPL edition only goes up to 7.0.x, and later versions are commercial-only — when using the GPLv3 edition, comply with its open-source terms (disclosing application source code, etc.); for commercial closed-source distribution, purchase a commercial license;
- The Ext rendering layer scripts `lw.js` / `lw.css` are original code of this project, distributed with this project under MIT, and contain no Sencha code and are not derived from it;
- The framework's default rendering layer is Alpine.js (MIT); **the deployment is fully functional with no ext directory present** (startup auto-detection prefers alpine, and `?client=` can switch per request);
- Other third-party dependencies: Lazarus/FPC is modified GPL (with a runtime linking exception); please pass this on to downstream recipients when distributing.

### Alpine.js (bundled dependency) and license notice

- `src/client/alpine.min.js` (3.14.9, the official CDN build, unmodified) **is distributed with this project** and is the only bundled third-party runtime file in the release package;
- Alpine.js is released under the MIT license (Copyright (c) Caleb Porzio and Alpine.js contributors). To satisfy MIT's "retain the copyright and license notice" requirement, the license notice has been added at the head of the distributed file (with a link to the official LICENSE); please do not remove it when redistributing;
- The project's own `lw-alpine.js` / `lw-alpine.css` are original code distributed under MIT (the file headers contain SPDX declarations);
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