# lazarusWeb: Running the Server as a Windows Service

> Let your business exe **register itself as a real Windows service** (managed by SCM, auto-start on boot, configurable auto-restart on crash),
> without any third-party wrapper like nssm or Task Scheduler. The same exe retains its original foreground execution mode,
> and GUI builds still display the server panel—service support does not change the behavior of any existing demo.
>
> Starting from 2026-11-20, the framework provides `TLWApp.RunService` / `TLWApp.StopService` entry points.
> A complete runnable example is in `demos/service_demo/`. This document is based on that demo, and the commands can be copied directly.
>
> Chinese usage guide. For deployment overview, see `deploy/README.md` §6.2; for Linux/macOS systemd, see §6.1 of the same file;
> for source-level pitfall records, see `NOTES.md`.

---

## 1. What It Can and Cannot Do

| Can | Description |
|---|---|
| Register / uninstall service | `--install` / `--uninstall`, register once with administrator privileges, writes to SCM |
| Auto-start on boot | `StartType=stAuto` in the mapper, runs automatically on boot |
| Standard service operations | `sc.exe start/stop/query`, or PowerShell `Start-Service`, etc. |
| Graceful stop | `sc.exe stop` wakes up the accept loop, waits for requests to finish before exiting |
| Auto-restart on crash | Works with service "failure recovery" (`sc.exe failure` or services.msc) to restart automatically |
| Foreground compatible | Without service parameters, behaves exactly as before; GUI builds display the panel |

| Cannot / Note | Description |
|---|---|
| No desktop session | Services run in Session 0, no graphical desktop; service mode forces `NoUI=True`, no panel displayed |
| Installation requires admin | Opening SCM requires `SC_MANAGER_ALL_ACCESS`; normal privileges will be rejected |
| `--run` is only for SCM | Manually executing `--run` in a non-SCM environment will exit directly; do not type it manually |
| Foreground and service are mutually exclusive | Both cannot occupy the same port (e.g., 8081) simultaneously; otherwise the later one cannot bind to the port |

---

## 2. Quick Start (Get Running in Five Minutes)

The following assumes Lazarus/FPC is installed (this document uses `C:\111\lazarus\lazbuild.exe`), and the project is at `C:\lazarusWeb`.

### 2.1 Compile (nogui widgetset)

cmd and PowerShell use the same syntax:

```bat
cd C:\lazarusWeb\demos\service_demo
build.bat
```

`build.bat` automatically finds `lazbuild.exe` (probes `%ProgramFiles%\Lazarus`, `%LocalAppData%\Lazarus`, `C:\111\lazarus` in order, and falls back to PATH), and compiles `service_demo.exe` with the nogui widgetset.

### 2.2 Install the Service (as Administrator)

**You must open the terminal as Administrator** (cmd or PowerShell both work).

```bat
service_demo.exe --install
```

After success, a new service appears in SCM:

- Service name: `lazarusWebService`
- Display name: `lazarusWeb Service Demo`
- Start type: Automatic (auto-start on boot)
- Run command: `"C:\lazarusWeb\demos\service_demo\service_demo.exe" --run`
  (`--run` is automatically written by DaemonApp during installation; only SCM uses it)

### 2.3 Start and Access

```bat
sc.exe start lazarusWebService
sc.exe query lazarusWebService
```

After seeing `STATE : 4 RUNNING`, open in your browser:

```
http://127.0.0.1:8081
```

You should see the lazarusWeb main form (the service_demo default form `TServiceForm`, with a Ping button to verify round-trip).

The port comes from `demos/service_demo/service_demo.ini` (`port=8081`).

---

## 3. Install / Uninstall / Operations: Complete Commands for cmd and PowerShell

**Installation, uninstallation, start, and stop all require an Administrator terminal.**

### 3.1 cmd.exe (Run as Administrator)

```bat
cd /d C:\lazarusWeb\demos\service_demo

service_demo.exe --install            :: Register service lazarusWebService (auto-start on boot)
sc.exe start lazarusWebService        :: Start
sc.exe query lazarusWebService        :: Check status (STATE : 4 RUNNING is normal)
sc.exe stop lazarusWebService         :: Stop (graceful: waits for accept loop to finish)
service_demo.exe --uninstall          :: Uninstall

:: Additional operations
sc.exe qc lazarusWebService                                        :: Check configuration (including BINARY_PATH_NAME / START_TYPE)
sc.exe failure lazarusWebService reset= 0 actions= restart/0       :: Set auto-restart on crash
```

> In cmd, `sc` is just `sc.exe`, no alias issues; but for consistency, it is still recommended to write `sc.exe`.

### 3.2 PowerShell (Run as Administrator `Windows PowerShell`)

```powershell
Set-Location C:\lazarusWeb\demos\service_demo

.\service_demo.exe --install          # Register service lazarusWebService (auto-start on boot)
sc.exe start lazarusWebService        # Start
sc.exe query lazarusWebService        # Check status (STATE : 4 RUNNING)
sc.exe stop lazarusWebService         # Stop (graceful)
.\service_demo.exe --uninstall        # Uninstall

# Equivalent native PowerShell cmdlets (more PS-style, choose one):
Start-Service lazarusWebService
Get-Service lazarusWebService         # Status : Running
Stop-Service lazarusWebService
```

> **⚠️ Must-read for PowerShell users**: `sc` in PowerShell is an **alias** for `Set-Content`,
> not a service control command. Typing `sc start lazarusWebService` will be interpreted as
> "write the contents of the file `start` into lazarusWebService"—**silently creating a garbage file, the service is not started at all,
> and there is no SCM output** (this is a pitfall actually encountered in practice). In PowerShell, you must write `sc.exe`,
> or use the native `Start-Service` / `Get-Service` / `Stop-Service`.
>
> Also, in PowerShell, to execute a program in the current directory, you need the `.\` prefix (write `.\service_demo.exe --install`).
> Writing `service_demo.exe` directly will be treated as a command name and searched in PATH, resulting in "not recognized".

### 3.3 Key Differences Between the Two Terminals

| Item | cmd.exe | PowerShell |
|---|---|---|
| `sc start ...` | Normal (it is `sc.exe`) | **Dangerous**: `sc` is an alias for `Set-Content`, will write a file |
| Correct service command | `sc.exe start ...` | `sc.exe start ...` or `Start-Service ...` |
| Execute current directory exe | `service_demo.exe --install` | `.\service_demo.exe --install` (requires `.\`) |
| Change directory | `cd /d path` | `Set-Location path` or `cd path` |

---

## 4. Configuration

When started as a service, the process's current working directory (cwd) is usually `C:\Windows\System32`.
**Therefore, all paths are resolved relative to the exe's directory** (the framework handles this; in the configuration, also use absolute paths
or paths relative to the exe directory, do not use paths relative to cwd).

`demos/service_demo/service_demo.ini`:

```ini
; Browser rendering layer: alpine = Alpine.js (built-in, no ext-<version> directory needed)
client=alpine
port=8081
; For service deployment, it is recommended to enable file logging (Windows services have no console, screen logs are invisible)
log=service_demo.log
```

- `port`: Listening port, default 8081; after changing, you need to `sc.exe stop` / `start` to restart the service for it to take effect.
- `log`: Log file. The framework supports this key starting from 2026-11-20; relative paths are expanded relative to the exe directory
  (`service_demo.log` → `C:\lazarusWeb\demos\service_demo\service_demo.log`).
  **Services have no console, so be sure to enable file logging**, otherwise there is no way to investigate errors.
- `client`: Rendering layer, `alpine` (default) or `ext`.

Configuration loading order: built-in defaults → INI file → command line; command line always wins.
Automatically searches for `<exe-name>.ini` or `lazarusWeb.ini` in the exe directory/current directory;
you can also explicitly specify with `--config=<path>`.

---

## 5. Command-Line Branching: Foreground vs. Service (Same exe)

The main program decides which branch to take based on parameters:

| Parameter | Branch | Description |
|---|---|---|
| No parameters / `--port=8081` and other normal parameters | Foreground `TLWApp.Run` | Consistent with all existing demos; GUI builds display the panel, nogui builds accept on the same thread |
| `--install` / `-i` | DaemonApp | Register service (administrator) |
| `--uninstall` / `-u` | DaemonApp | Uninstall service (administrator) |
| `--run` / `-r` | DaemonApp | Service run mode, **should only be called by SCM through ImagePath** |

- Foreground branch: `GServiceMode=False`, `Application.Title`, GUI panel as usual.
- Service branch: `GServiceMode=True`, forces `NoUI=True`, runs `RunService` in a worker thread.
- `--service` is also recognized as the service branch (historical compatibility alias), but documentation and operations uniformly use `--install/--uninstall/--run`.

**Note**: `--install` / `--uninstall` will first pre-check permissions with `OpenSCManager(SC_MANAGER_ALL_ACCESS)`.
Normal privileges will print a clear ASCII prompt and exit with `ExitCode=1`, without throwing a bunch of confusing exceptions (see §7.1 for details).

---

## 6. Auto-Start on Boot and Failure Recovery

### 6.1 Auto-Start on Boot

The service start type comes from `WinBindings.StartType = stAuto` in `uServiceMapper.lfm`.
DaemonApp registers accordingly during `--install`, so **it auto-starts on boot immediately after installation**, no additional settings needed.

View/modify start type:

```bat
sc.exe qc lazarusWebService                       :: View START_TYPE
sc.exe config lazarusWebService start= disabled   :: Disable auto-start (note the space after start=)
sc.exe config lazarusWebService start= auto       :: Restore automatic
```

### 6.2 Auto-Restart on Crash

The service itself calls `Halt(1)` when the worker exits abnormally, so SCM sees the real stopped state (no "fake alive" empty shell).
Combined with failure recovery, it can restart automatically:

```bat
:: Command-line setting: restart after 0 seconds on failure, reset counter after 0 seconds
sc.exe failure lazarusWebService reset= 0 actions= restart/0
```

Or open `services.msc` → find `lazarusWebService` → Properties → "Recovery" tab,
set "First failure/Second failure" to "Restart the Service".

---

## 7. Troubleshooting (Including Real Pitfalls Encountered in This Practice)

### 7.1 Installation Error "Access Denied / Disk Full"

**Symptom**: Executing `--install` with normal privileges first shows `EOSError: System error. (OS Code 5): Access denied`,
then `EInOutError: Disk Full`.

**Cause**: Opening SCM requires `SC_MANAGER_ALL_ACCESS`; the second "Disk Full" is a **misleading secondary exception** arising from the FPC error log
path, the disk is not actually full.

**Solution**: Execute in an Administrator terminal. The current demo pre-checks permissions before entering DaemonApp;
normal privileges directly print `Please run this terminal as Administrator before --install / --uninstall.`
and exit, no longer showing those two confusing exceptions.

### 7.2 Browser Refuses Connection After Start—PowerShell `sc` Alias Pitfall

**Symptom**: After `sc start lazarusWebService`, there is no output, and the browser cannot open.

**Cause**: In PowerShell, `sc` is an alias for `Set-Content`. The command actually means "write the contents of the file `start`
into lazarusWebService". The service was never started, and garbage files `start` / `query` were left behind.

**Solution**: Always use `sc.exe start lazarusWebService` or `Start-Service lazarusWebService`,
and delete the mistakenly created `start` / `query` files.

### 7.3 Service Shows "Running" but Browser Cannot Open—Fake Alive

**Symptom**: `services.msc` / `sc.exe query` shows Running, but `netstat -ano | findstr :8081`
shows no listener, and the browser refuses connection.

**Three-piece diagnostic set** (check in order):

```bat
sc.exe query lazarusWebService                         :: Is the state really Running
netstat -ano | findstr :8081                           :: Is the port LISTENING
type C:\lazarusWeb\demos\service_demo\service_demo.log :: Log
type C:\lazarusWeb\demos\service_demo\service_demo.diag :: Diagnostic file (see below)
```

**Fixed pitfall one: daemon's OnStart not bound (CreateNew trap)**

- FPC `DaemonApp` creates the daemon instance with `DaemonClass.CreateNew(Self,0)`
  (`daemonapp.pp:1044`), and `TDataModule.CreateNew` internally calls `inherited Create`,
  **which does not call the subclass's overridden `Create`**.
- If you put `OnStart:=@...` in `Create`, it will not be bound → `OnStart=nil` → worker does not start →
  service is fake alive. The official TDaemon example puts events in the `.lfm` precisely to avoid this.
- The fix in this demo: `uServiceDaemon.pas` extracts `BindEvents`, overrides `CreateNew`
  and binds events both there and in `Create`.
- **How to determine**: Whether `service_demo.diag` is generated. If the file is completely absent, it means OnStart was not triggered.

**Fixed pitfall two: worker did not register the main form (no form specified)**

- After the fake-alive issue is fixed, the browser may show `Cannot create session: no form specified`.
- Cause: The foreground branch calls `TLWApp.Register(TServiceForm)` in the `lpr`; the service worker directly calls
  `RunService`, skipping this step, so `GOrder` is empty → `DefaultForm=''` → error when creating a session
  (`lwhttp.pas:1490`).
- Fix: `TLWWorkerThread.Execute` adds `TLWApp.Register(TServiceForm)` before `RunService`.
- **Lesson**: Any new entry point that bypasses `TLWApp.Run` (such as `RunService`) must register the main form itself.

**Other common causes**:

| Symptom | Cause | Solution |
|---|---|---|
| Port occupied | Foreground `service_demo.exe` is still running, occupying 8081 | Stop the foreground process, or change the ini port and restart the service |
| Log/diag in System32 | Used relative paths | Use absolute paths in the exe directory (the framework resolves `log=` relative to the exe directory) |
| exe cannot be overwritten (error code 5) | Service process is locking the exe | First `sc.exe stop`, confirm no `service_demo.exe` remains before compiling/overwriting |

### 7.4 Diagnostic File `service_demo.diag`

During fake-alive diagnosis, `uServiceDaemon.pas` uses `Diag()` to write a bare text file in the exe directory that does not depend on the logging system,
recording key nodes by time. When the service is normal, the content is roughly:

```
19:16:32  DoStart entered (OnStart triggered)
19:16:32  worker thread started
19:16:32  worker.Execute entered, about to call TLWApp.RunService
```

- If `DoStart entered` is present → OnStart is bound (pitfall one avoided).
- If `worker.Execute entered` is present → worker thread is running.
- If the port is still unreachable, check the exception details in `service_demo.log`.

This file is harmless to functionality; once stable, you can delete the `Diag()` calls and recompile.

---

## 8. How It Works (Read When Adapting Your Own Program)

### 8.1 Two Framework-Level Entry Points (`src/core/lwapp.pas`)

- **`TLWApp.RunService`**: Sets `GServiceMode=True`, `ExitCode=0`, calls `Run`.
  In service mode, fatal errors inside `Run` (configuration not found, root does not exist) do not `Halt` (that would bypass SCM's
  Stop protocol); instead, they log and throw `ELWServiceAbort`, which `RunService` catches and finishes normally.
  `GCfg.NoUI := GServiceMode` makes the service use same-thread accept (no desktop session, cannot open GUI panel).
- **`TLWApp.StopService`**: Sets `GStopRequested`, calls `Server.Stop` to wake up the `RunService` blocked in accept,
  so it goes through finally to release the server and return. Idempotent, and can handle the race condition where "SCM stops too early,
  the server has not been created yet".
- The `Run` body is unchanged; `GServiceMode` defaults to False → existing demos (including GUI versions) behave exactly the same.

### 8.2 Service Host Layer (`demos/service_demo/`)

| File | Purpose |
|---|---|
| `service_demo.lpr` | Branches by parameters: foreground goes to `TLWApp.Run`; service goes to DaemonApp native `--install/--uninstall/--run`; performs admin pre-check before installation |
| `uServiceDaemon.pas` | `TLWServiceDaemon` (TDaemon subclass) + worker thread; `DoStart` starts worker to call `RunService`, `DoStop` calls `StopService` then `WaitFor`; overrides `CreateNew` to bind events; worker registers `TServiceForm` |
| `uServiceMapper.pas` + `.lfm` | `TDaemonMapper` required by DaemonApp; `.lfm` defines service name `lazarusWebService`, display name, `DaemonClassName=TLWServiceDaemon`, `StartType=stAuto`. **lfm is required**: pure code mapper will report "No streaming method available" |
| `uServiceForm.pas` | Default main form `TServiceForm` for the service example (controls built in pure code, with a Ping button), registered in the worker |
| `service_demo.ini` | Port, log, rendering layer configuration |
| `build.bat` | nogui widgetset build script |

### 8.3 Key Design Constraints

1. **Blocking loop must be in a worker thread**: `RunService` blocks in accept and must never be placed in the `TDaemon.Execute`
   main thread, otherwise the service will no longer respond to SCM's Stop control.
2. **Graceful stop**: In `DoStop`, `StopService` wakes up accept → `WaitFor` waits for `RunService` to finish,
   ensuring requests are processed and the server object is released before reporting stopped to SCM.
3. **Event binding must be in `CreateNew`**: See §7.3 pitfall one.
4. **New entry points must register forms**: See §7.3 pitfall two.
5. **Use FPC's built-in DaemonApp (fcl-extra)**, not the IDE's lazdaemon package—the latter's
   `lazdaemonapp.ppu` is compiled with the win32 widgetset and conflicts with nogui builds.

### 8.4 Startup Chain (SCM Perspective)

```
sc.exe start lazarusWebService
  → SCM starts the process with "exe --run"
  → lpr: WantDaemonApp=True → registers daemon class/mapper → DaemonApp.Application.Run
  → DoRun: RunDaemonsRun → RunDaemons → creates daemon instance (CreateNew) → StartServiceCtrlDispatcher
  → SCM callback ServiceMainEntry → Application.Main → FindDaemonDef(service name)
  → Controller.Main → TDaemonThread.Execute → FDaemon.Start → OnStart(DoStart)
  → DoStart: starts worker thread
  → worker.Execute: Register(TServiceForm) → RunService → Run → binds port, accept
  → Browser http://127.0.0.1:8081
```

Stop is the reverse: `sc.exe stop` → `DoStop` → `StopService` wakes up accept → `WaitFor` → SCM reports Stopped.

---

## 9. Moving the Service Solution to Your Own Project

1. Copy the entire `demos/service_demo/` directory as a template, and rename the project.
2. `service_demo.lpr` (rename to your project): keep the parameter branching and admin pre-check; in the foreground branch, replace
   `TServiceForm` with your main form.
3. `uServiceDaemon.pas`: In the worker, `TLWApp.Register(YourMainFormClass)` + `RunService`;
   keep the `CreateNew` event binding and `GStoppingBySCM` anti-fake-alive logic.
4. `uServiceMapper.pas` + `.lfm`: Change the service name, `DaemonClassName`, `DisplayName`.
   `.lfm` cannot be omitted (pure code mapper reports "No streaming method available").
5. `build.bat`: Confirm compilation with the nogui widgetset.
6. Administrator `--install`, `sc.exe start`, browser verification; use `service_demo.diag` / logs for troubleshooting.

> If your program originally has GUI panel requirements: keep the GUI widgetset for the foreground build (display panel),
> and use nogui for the service build (no panel). The two are distinguished by `GServiceMode` and do not affect each other.

---

## 10. Comparison with Other Hosting Methods

| Method | Suitable Scenarios | Additional Dependencies |
|---|---|---|
| exe built-in service in this section | Single exe deployment, no third-party installation, Windows service semantics required (auto-start on boot/standard operations) | None (FPC built-in DaemonApp) |
| systemd (deploy/README.md §6.1) | Linux / macOS | System built-in |
| nssm / Task Scheduler | Wrap any exe, no code changes at all | Requires nssm installation |
| lwhyper (deploy/README.md §4.1) | Cluster + worker crash guard + reverse proxy + hot update | Framework built-in |

If you need crash auto-restart without configuring failure recovery, you can directly use lwhyper hosting (see `WHYPER.md`).

---

## 11. Verification Checklist

```bat
:: 1. Is the service running
sc.exe query lazarusWebService                          :: STATE : 4 RUNNING

:: 2. Is the port listening
netstat -ano | findstr :8081                            :: LISTENING present

:: 3. Is HTTP reachable
curl --noproxy '*' http://127.0.0.1:8081/lw/healthz     :: 200

:: 4. Logs and diagnostics
type C:\lazarusWeb\demos\service_demo\service_demo.log
type C:\lazarusWeb\demos\service_demo\service_demo.diag  :: Should have DoStart / worker.Execute lines

:: 5. Process should disappear after graceful stop
sc.exe stop lazarusWebService
tasklist /FI "IMAGENAME eq service_demo.exe"             :: No service_demo process
```

Open `http://127.0.0.1:8081` in the browser, click the Ping button, and you should see a round-trip response—the service version is now fully working.