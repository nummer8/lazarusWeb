# lazarusWeb：把服务端跑成 Windows 服务

> 让业务 exe **自己注册成真正的 Windows 服务**（SCM 管理、开机自启、崩溃可配自动拉起），
> 不需要 nssm / 任务计划等任何第三方包装器。同一个 exe 保留原来的前台运行方式，
> GUI 构建照样显示服务端面板——服务支持不改变任何现有 demo 的行为。
>
> 框架从 2026-11-20 起提供 `TLWApp.RunService` / `TLWApp.StopService` 两个入口。
> 新建工程向导的**第一框（1/3）**已可直接选「服务(daemon)模式」，一键生成宿主层
> （`tools\lwnew --service` 等价）；完整可运行示例仍在 `demos/service_demo/`，
> 本文以该 demo 为蓝本，命令可直接照抄。
>
> 中文使用篇。部署总览见 `deploy/README.md` §6.2；Linux/macOS 用 systemd 见同文件 §6.1；
> 源码级踩坑记录见 `NOTES.md`。

---

## 1. 它能做什么 / 不能做什么

| 能 | 说明 |
|---|---|
| 注册 / 卸载服务 | `--install` / `--uninstall`，管理员权限一次注册，写入 SCM |
| 开机自启 | mapper 里 `StartType=stAuto`，开机自动运行 |
| 标准服务运维 | `sc.exe start/stop/query`，或 PowerShell `Start-Service` 等 |
| 优雅停止 | `sc.exe stop` 唤醒 accept 循环，等请求收尾后再退出 |
| 崩溃可拉起 | 配合服务"故障恢复"（`sc.exe failure` 或 services.msc）自动重启 |
| 前台兼容 | 不带服务参数时与旧版一字不差，GUI 构建显示面板 |

| 不能 / 注意 | 说明 |
|---|---|
| 无桌面会话 | 服务以 Session 0 运行，没有图形桌面；服务模式强制 `NoUI=True`，不显示面板 |
| 安装要管理员 | 打开 SCM 需要 `SC_MANAGER_ALL_ACCESS`，普通权限会被拒 |
| `--run` 只给 SCM | 手工执行 `--run` 在非 SCM 环境会直接退出，不要手动敲 |
| 前台与服务二选一 | 两者不能同时占同一个端口（如 8081），否则后起的绑不上端口 |

---

## 2. 快速上手（五分钟跑通）

以下假设已装好 Lazarus/FPC（本文用 `C:\111\lazarus\lazbuild.exe`），工程在 `C:\lazarusWeb`。

### 2.1 先有一个"服务模式"工程

三条路都能得到"同一个 exe 既可前台运行又可注册成服务"的工程，但**产物文件名并不相同**：

- 向导 / `lwnew --service` 生成 `uDaemon.pas` + `uMapper.pas`（服务定义写在代码里，**无 `.lfm`**）+ `lazarusWeb.ini`；
- 抄 demo 得到的是 `uServiceDaemon.pas` + `uServiceMapper.pas` + `uServiceMapper.lfm` + `service_demo.ini`。

下文命令以 demo 为例；生成工程把命令里的 `service_demo` 换成你的工程名即可。

| 路 | 做法 | 适用 |
|---|---|---|
| **A. IDE 向导（推荐）** | 装好 `lwdesign` 包后 **文件 → 新建 → 项目 → lazarusWeb**，第 1 框选 **服务(daemon)模式**，第 2 框选工程类型（部署用 `nogui`），第 3 框选模板，Ctrl+S 落盘 | 日常开发，在 IDE 里直接改代码 |
| **B. 命令行 `lwnew --service`** | `tools\lwnew.exe --name=MyApp --dir=C:\work\MyApp --units=C:\lazarusWeb\src\core --service` | CI / 脚本 / 不想开 IDE |
| **C. 抄 `demos/service_demo`** | 整目录复制后改工程名，按 §9 逐文件替换 | 想从现成 demo 手工改，或参考最原始的写法 |

向导/`lwnew` 生成的服务工程目录：

```
MyApp.lpr   MyApp.lpi   umain.pas  umain.lfm
uDaemon.pas     ← 守护类 TLWServiceDaemon + worker 线程
uMapper.pas     ← TDaemonMapper 子类，服务名 MyAppService、StartType=stAuto
lazarusWeb.ini  ← port= / log= / client=
build.bat  build.sh  favicon.ico  lw\
```

> 这三个附加文件在向导里是**内存虚拟工程文件**，Ctrl+S 那一刻一次性落盘，
> 内容在落盘前就已完整正确（`uMapper.pas` 用代码构造 `DaemonDefs`，
> 不需要 `.lfm`）。

### 2.2 编译（nogui widgetset）

cmd 与 PowerShell 写法相同：

```bat
cd C:\lazarusWeb\demos\service_demo
build.bat
```

`build.bat` 会自动找 `lazbuild.exe`（依次探测 `%ProgramFiles%\Lazarus`、
`%LocalAppData%\Lazarus`、`C:\111\lazarus`，最后兜底 PATH），以 nogui widgetset
编译出 `service_demo.exe`。向导 / `lwnew` 生成的工程目录里也有同样一份
`build.bat`，`cd` 进去直接跑即可（等价于 `lazbuild -B --ws=nogui MyApp.lpi`）。

### 2.3 安装服务（管理员身份）

**必须以管理员身份打开终端**（cmd 或 PowerShell 均可）。

```bat
:: demo
service_demo.exe --install
:: 向导生成的服务工程（exe 名 = 工程名）
MyApp.exe --install
```

成功后 SCM 里多出一个服务：

- 服务名：demo 是 `lazarusWebService`；`lwnew --service` 生成的是 **`<--name 指定的工程名>Service`**（如 `MyAppService`）；**IDE 向导生成的恒为 `LWApp1Service`**（向导在保存前用占位名 `LWApp1` 生成，保存后不随新工程名重写，见 `SERVICE_NAMING.md`）
- 显示名：demo 是 `lazarusWeb Service Demo`；生成工程是 **`lazarusWeb · <工程名> Service`**（IDE 向导同样是 `lazarusWeb · LWApp1 Service`）
- 启动类型：自动（开机自启）
- 运行命令：`"<exe 全路径>" --run`（`--run` 由 DaemonApp 在安装时自动写入，只需 SCM 用）

### 2.4 启动并访问

```bat
sc.exe start lazarusWebService        :: 或 MyAppService
sc.exe query lazarusWebService
```

看到 `STATE : 4 RUNNING` 后，浏览器打开：

```
http://127.0.0.1:8081
```

应显示 lazarusWeb 主窗体（service_demo 的默认窗体 `TServiceForm`，带一个 Ping 按钮可验证往返）。

端口来自 `demos/service_demo/service_demo.ini`（`port=8081`）；生成的工程则来自
`lazarusWeb.ini`（`port=` 与向导里填的一致，`lwnew` 默认 8090）。`lwconfig` 的查找顺序是
`<exe目录>\<exe名>.ini` → `<exe目录>\lazarusWeb.ini` → 当前目录下同名两个，所以
两种命名都能用。

---

## 3. 安装 / 卸载 / 运维：cmd 与 PowerShell 完整命令

**只有 `--install` / `--uninstall` 会预检管理员权限**（源码 `uServiceDaemon.pas` 的 `NeedsServiceManagerAccess` 只覆盖这两个参数）。
`sc.exe start/stop/query` 属于 SCM 操作，通常不需要管理员终端（受组策略限制时另说）；
`--run` 由 SCM 以 LocalSystem 启动，更不需要当前用户提权。为避免歧义，下面的运维示例仍统一用管理员终端。

### 3.1 cmd.exe（以管理员身份运行）

```bat
cd /d C:\lazarusWeb\demos\service_demo

service_demo.exe --install            :: 注册服务 lazarusWebService（开机自启）
sc.exe start lazarusWebService        :: 启动
sc.exe query lazarusWebService        :: 查状态（STATE : 4 RUNNING 为正常）
sc.exe stop lazarusWebService         :: 停止（优雅：等 accept 循环收尾）
service_demo.exe --uninstall          :: 卸载

:: 附加运维
sc.exe qc lazarusWebService                                        :: 查配置（含 BINARY_PATH_NAME / START_TYPE）
sc.exe failure lazarusWebService reset= 0 actions= restart/0       :: 设崩溃后自动重启
```

> cmd 里 `sc` 就是 `sc.exe`，没有别名问题；但为统一仍建议写 `sc.exe`。

### 3.2 PowerShell（以管理员身份运行 `Windows PowerShell`）

```powershell
Set-Location C:\lazarusWeb\demos\service_demo

.\service_demo.exe --install          # 注册服务 lazarusWebService（开机自启）
sc.exe start lazarusWebService        # 启动
sc.exe query lazarusWebService        # 查状态（STATE : 4 RUNNING）
sc.exe stop lazarusWebService         # 停止（优雅收尾）
.\service_demo.exe --uninstall        # 卸载

# 等价的 PowerShell 原生 cmdlet（更 PS 风格，任选其一）：
Start-Service lazarusWebService
Get-Service lazarusWebService         # Status : Running
Stop-Service lazarusWebService
```

> **⚠️ PowerShell 用户必看**：`sc` 在 PowerShell 里是 `Set-Content` 的**别名**，
> 不是服务控制命令。敲 `sc start lazarusWebService` 会被解释成
> "把文件 `start` 的内容写成 lazarusWebService"——**静默创建一个垃圾文件，服务根本没启动，
> 也没有任何 SCM 输出**（这是实测踩过的坑）。PowerShell 里必须写 `sc.exe`，
> 或改用原生 `Start-Service` / `Get-Service` / `Stop-Service`。
>
> 另外 PowerShell 执行当前目录的程序要带 `.\` 前缀（写 `.\service_demo.exe --install`），
> 直接写 `service_demo.exe` 会被当成命令名去 PATH 里找而报"无法识别"。

### 3.3 两种终端的关键区别

| 项目 | cmd.exe | PowerShell |
|---|---|---|
| `sc start ...` | 正常（就是 `sc.exe`） | **危险**：`sc` 是 `Set-Content` 别名，会写文件 |
| 正确服务命令 | `sc.exe start ...` | `sc.exe start ...` 或 `Start-Service ...` |
| 执行当前目录 exe | `service_demo.exe --install` | `.\service_demo.exe --install`（要带 `.\`） |
| 切换目录 | `cd /d 路径` | `Set-Location 路径` 或 `cd 路径` |

---

## 4. 配置

服务方式启动时，进程的当前工作目录（cwd）通常是 `C:\Windows\System32`。
**因此所有路径都按 exe 所在目录解析**（框架已按此处理，配置里也请用绝对路径
或相对 exe 目录的路径，不要写相对 cwd 的路径）。

`demos/service_demo/service_demo.ini`：

```ini
; 浏览器渲染层：alpine = Alpine.js（内置，不需要 ext-<版本> 目录）
client=alpine
port=8081
; 服务化部署建议开文件日志（Windows 服务没有控制台，屏幕日志看不见）
log=service_demo.log
```

- `port`：监听端口，**demo 的 ini 写 8081；框架与 `lwnew` 的内置默认都是 8090**；改后需 `sc.exe stop` / `start` 重启服务生效。
- `log`：日志文件。框架从 2026-11-20 起支持该键，相对路径按 exe 目录展开
  （`service_demo.log` → `C:\lazarusWeb\demos\service_demo\service_demo.log`）。
  **服务没有控制台，务必开文件日志**，否则出错时无从查证。
- `client`：渲染层，`alpine` 或 `ext`。**内置默认是 `ext`**（`lwapp.pas` 的 `GCfg.DefaultClient`）；
  部署带 alpine 前端资源时会自动探测并切到 `alpine`，显式 `client=` / `--client=` 优先。demo 的 ini 显式写了 `alpine`。

配置加载顺序：内置默认值 → INI 文件 → 命令行，命令行永远赢。
自动查找 exe 目录/当前目录下的 `<exe名>.ini` 或 `lazarusWeb.ini`；
也可用 `--config=<路径>` 显式指定。

---

## 5. 命令行分流：前台 vs 服务（同一个 exe）

主程序按参数决定走哪条分支：

| 参数 | 分支 | 说明 |
|---|---|---|
| 无参数 / `--port=8081` 等普通参数 | 前台 `TLWApp.Run` | 与所有现有 demo 一致；GUI 构建显示面板，nogui 构建同线程 accept |
| `--install` / `-i` | DaemonApp | 注册服务（管理员） |
| `--uninstall` / `-u` | DaemonApp | 卸载服务（管理员） |
| `--run` / `-r` | DaemonApp | 服务运行模式，**只应由 SCM 通过 ImagePath 调用** |

- 前台分支：`GServiceMode=False`，`Application.Title`、GUI 面板照旧。
- 服务分支：`GServiceMode=True`，强制 `NoUI=True`，由 worker 线程跑 `RunService`。
- `--service` **只在 demo 的** `uServiceDaemon.pas` 里被识别为服务分支（历史兼容别名）；
  向导 / `lwnew --service` 生成的 `uDaemon.pas` **不识别**这个参数（`--service` 在那里只是**生成期**开关）。
  运维统一用 `--install/--uninstall/--run`。

**注意**：`--install` / `--uninstall` 会先用 `OpenSCManager(SC_MANAGER_ALL_ACCESS)` 预检权限，
普通权限会打印清晰的 ASCII 提示并 `ExitCode=1` 退出，不会抛一堆费解的异常（详见 §7.1）。

---

## 6. 开机自启与故障恢复

### 6.1 开机自启

服务的启动类型来自 mapper 里的 `WinBindings.StartType = stAuto`（demo 在
`uServiceMapper.lfm` 里，向导生成的工程在 `uMapper.pas` 的 `Create` 里）。
`--install` 时 DaemonApp 据此注册，故**装完即开机自启**，无需额外设置。

查看/修改启动类型：

```bat
sc.exe qc lazarusWebService                       :: 看 START_TYPE
sc.exe config lazarusWebService start= disabled   :: 禁用自启（注意 start= 后有空格）
sc.exe config lazarusWebService start= auto       :: 恢复自动
```

### 6.2 崩溃自动拉起

服务本身在 worker 非正常退出时会 `Halt(1)` 让 SCM 看到真实停止状态（不留"假活"空壳）。
配合故障恢复即可自动重启：

```bat
:: 命令行设置：失败后 0 秒重启，计数 0 秒内重置
sc.exe failure lazarusWebService reset= 0 actions= restart/0
```

或打开 `services.msc` → 找到 `lazarusWebService` → 属性 → "恢复"选项卡，
把"第一次失败/第二次失败"设为"重新启动服务"。

---

## 7. 排障（含本次实测踩过的真实坑）

### 7.1 安装报错"拒绝访问 / Disk Full"

**现象**：普通权限执行 `--install`，先 `EOSError: System error. (OS Code 5): 拒绝访问`，
再 `EInOutError: Disk Full`。

**原因**：打开 SCM 需要 `SC_MANAGER_ALL_ACCESS`；第二个 "Disk Full" 是 FPC 错误日志
路径上冒出的**误导性次生异常，磁盘并没有满**。

**解决**：用管理员身份的终端执行。现在的 demo 会在进入 DaemonApp 前预检权限，
普通权限直接打印 `Please run this terminal as Administrator before --install / --uninstall.`
并退出，不再出现那两层费解异常。

### 7.2 启动后浏览器拒绝连接——PowerShell `sc` 别名坑

**现象**：`sc start lazarusWebService` 后没有任何输出，浏览器打不开。

**原因**：PowerShell 里 `sc` 是 `Set-Content` 的别名，该命令实际是"把文件 `start`
的内容写成 lazarusWebService"，服务从未启动，还留下垃圾文件 `start` / `query`。

**解决**：一律用 `sc.exe start lazarusWebService` 或 `Start-Service lazarusWebService`，
删除误建的 `start` / `query` 文件。

### 7.3 服务显示"正在运行"但浏览器打不开——假活

**现象**：`services.msc` / `sc.exe query` 显示 Running，但 `netstat -ano | findstr :8081`
无监听、浏览器拒绝连接。

**诊断三件套**（依次看）：

```bat
sc.exe query lazarusWebService                         :: 状态是否真 Running
netstat -ano | findstr :8081                           :: 端口有没有 LISTENING
type C:\lazarusWeb\demos\service_demo\service_demo.log :: 日志
type C:\lazarusWeb\demos\service_demo\service_demo.diag :: 诊断文件（见下）
```

**已修复的坑一：daemon 的 OnStart 没绑上（CreateNew 陷阱）**

- FPC `DaemonApp` 用 `DaemonClass.CreateNew(Self,0)` 创建 daemon 实例
  （`daemonapp.pp:1044`），而 `TDataModule.CreateNew` 内部走 `inherited Create`，
  **不会调用子类 override 的 `Create`**。
- 若把 `OnStart:=@...` 写在 `Create` 里就会漏绑 → `OnStart=nil` → worker 不启动 →
  服务假活。官方 TDaemon 示例把事件写在 `.lfm` 里正是为了绕开这一点。
- 本 demo 的修法：`uServiceDaemon.pas` 提取 `BindEvents`，override `CreateNew`
  并在其中（以及 `Create` 中）都绑定事件。
- **判断方法**：`service_demo.diag` 是否生成。若完全没有该文件，说明 OnStart 没触发。

**已修复的坑二：worker 没注册主窗体（no form specified）**

- 服务假活修好后，浏览器可能出现 `无法创建会话：no form specified`。
- 原因：前台分支在 `lpr` 里调了 `TLWApp.Register(TServiceForm)`；服务 worker 直接调
  `RunService` 跳过了这一步，`GOrder` 为空 → `DefaultForm=''` → 建会话时报错
  （`lwhttp.pas:1490`）。
- 修法：`TLWWorkerThread.Execute` 在 `RunService` 前补 `TLWApp.Register(TServiceForm)`。
- **教训**：任何绕过 `TLWApp.Run` 的新入口（如 `RunService`）都必须自己 `Register` 主窗体。

**其它常见原因**：

| 现象 | 原因 | 处理 |
|---|---|---|
| 端口被占用 | 前台 `service_demo.exe` 还开着，抢了 8081 | 停掉前台进程，或改 ini 端口后重启服务 |
| 日志/diag 在 System32 | 用了相对路径 | 用 exe 目录的绝对路径（框架已按 exe 目录解析 `log=`） |
| exe 无法覆盖（error code 5） | 服务进程锁着 exe | 先 `sc.exe stop`，确认无 `service_demo.exe` 残留再编译/覆盖 |

### 7.4 诊断文件 `service_demo.diag`

定位假活期间，`uServiceDaemon.pas` 用 `Diag()` 往 exe 目录写一个不依赖日志系统的裸文本文件，
按时间记录关键节点。服务正常时内容大致为：

```
19:16:32  DoStart 进入（OnStart 已触发）
19:16:32  worker 线程已 Start
19:16:32  worker.Execute 进入，即将调用 TLWApp.RunService
```

- 有 `DoStart 进入` → OnStart 已绑（坑一已避开）。
- 有 `worker.Execute 进入` → worker 线程在跑。
- 若端口仍不通，再看 `service_demo.log` 里的异常详情。

该文件对功能无害，稳定后可删掉 `Diag()` 调用再重新编译。

---

## 8. 工作原理（想改造自己的程序时读）

### 8.1 框架层两个入口（`src/core/lwapp.pas`）

- **`TLWApp.RunService`**：置 `GServiceMode=True`，`ExitCode=0`，调用 `Run`。
  服务模式下 `Run` 内的致命错误（配置找不到、root 不存在）不 `Halt`（那会绕过 SCM 的
  Stop 协议），改为记日志 + 抛 `ELWServiceAbort`，由 `RunService` 吞掉后正常收尾。
  `GCfg.NoUI := GServiceMode` 让服务走同线程 accept（没有桌面会话，不能开 GUI 面板）。
- **`TLWApp.StopService`**：置 `GStopRequested`，调 `Server.Stop` 唤醒阻塞在 accept 的
  `RunService`，使其走 finally 释放服务器后返回。幂等，且能处理"SCM 停得太早、
  服务器还没建好"的竞态。
- `Run` 主体一字未改，`GServiceMode` 默认 False → 现有 demo（含 GUI 版）行为完全不变。

### 8.2 服务宿主层（`demos/service_demo/`）

| 文件 | 作用 |
|---|---|
| `service_demo.lpr` | 按参数分流：前台走 `TLWApp.Run`；服务走 DaemonApp 原生 `--install/--uninstall/--run`；安装前做管理员预检 |
| `uServiceDaemon.pas` | `TLWServiceDaemon`（TDaemon 子类）+ worker 线程；`DoStart` 起 worker 调 `RunService`，`DoStop` 调 `StopService` 再 `WaitFor`；override `CreateNew` 绑事件；worker 内 `Register(TServiceForm)` |
| `uServiceMapper.pas` + `.lfm` | DaemonApp 必需的 `TDaemonMapper`；`.lfm` 定义服务名 `lazarusWebService`、显示名、`DaemonClassName=TLWServiceDaemon`、`StartType=stAuto`。demo 保留了 `.lfm` 是因为它先用设计器起的头；**纯代码构造同样可行**——向导 / `lwnew` 生成的 `uMapper.pas` 就没有 `.lfm`：override `Create` 里 `inherited CreateNew(AOwner, 0)` 跳过 `InitInheritedComponent`，再用 `TDaemonDef(DaemonDefs.Add)` 逐个赋值（见坑 195） |
| `uServiceForm.pas` | 服务示例的默认主窗体 `TServiceForm`（纯代码建控件，带 Ping 按钮），worker 里注册它 |
| `service_demo.ini` | 端口、日志、渲染层配置 |
| `build.bat` | nogui widgetset 编译脚本 |

### 8.3 关键设计约束

1. **阻塞循环必须在 worker 线程**：`RunService` 阻塞在 accept，绝不能放 `TDaemon.Execute`
   主线程，否则服务不再响应 SCM 的 Stop 控制。
2. **优雅停止**：`DoStop` 里 `StopService` 唤醒 accept → `WaitFor` 等 `RunService` 收尾，
   保证请求处理完、服务器对象释放后再向 SCM 报停止。
3. **事件绑定要在 `CreateNew`**：见 §7.3 坑一。
4. **新入口要注册窗体**：见 §7.3 坑二。
5. **用 FPC 自带 DaemonApp（fcl-extra）**，不用 IDE 的 lazdaemon 包——后者的
   `lazdaemonapp.ppu` 是 win32 widgetset 编译的，与 nogui 构建冲突。

### 8.4 启动链路（SCM 视角）

```
sc.exe start lazarusWebService
  → SCM 以 "exe --run" 启动进程
  → lpr: WantDaemonApp=True → 注册 daemon 类/mapper → DaemonApp.Application.Run
  → DoRun: RunDaemonsRun → RunDaemons → 建 daemon 实例(CreateNew) → StartServiceCtrlDispatcher
  → SCM 回调 ServiceMainEntry → Application.Main → FindDaemonDef(服务名)
  → Controller.Main → TDaemonThread.Execute → FDaemon.Start → OnStart(DoStart)
  → DoStart: 起 worker 线程
  → worker.Execute: Register(TServiceForm) → RunService → Run → 绑定端口、accept
  → 浏览器 http://127.0.0.1:8081
```

停止是逆向：`sc.exe stop` → `DoStop` → `StopService` 唤醒 accept → `WaitFor` → SCM 报 Stopped。

---

## 9. 把服务方案搬到自己的工程

### 9.1 首选：让向导直接生成（不需要搬运）

装好 `lwdesign` 包后 **文件 → 新建 → 项目 → lazarusWeb**，**第 1 框（1/3）选
「服务(daemon)模式」**，后面两框照旧（第 2 框部署选 `nogui`，第 3 框选常规/插件）。
Ctrl+S 落盘后目录里已经有 `uDaemon.pas` / `uMapper.pas` / `lazarusWeb.ini`，
`build.bat` 的末尾还带三行服务提示（`--install` / `sc.exe start` / `--uninstall`）。

命令行等价物：

```bat
tools\lwnew.exe --name=MyApp --dir=C:\work\MyApp --units=C:\lazarusWeb\src\core --service
```

生成的这套东西已经是"你自己的工程"：主窗体是 `umain.pas`（可随意改名）。
服务名要分两条路看：**命令行 `lwnew --name=MyApp` 生成 `MyAppService`；IDE 向导
生成的是固定 `LWApp1Service`**（保存时改工程名不会重写 `uMapper.pas`）。要改服务名/
显示名，直接改 `uMapper.pas` 里的 `DD.Name` / `DD.DisplayName`，然后**卸载并重新安装**
（服务名注册在 SCM 里，不是运行时读配置），详见 `SERVICE_NAMING.md`。

### 9.2 备选：从 `demos/service_demo` 手工搬

1. 复制 `demos/service_demo/` 整个目录作为模板，改工程名。
2. `service_demo.lpr`（改名为你的工程）：保留按参数分流与管理员预检；前台分支把
   `TServiceForm` 换成你的主窗体。
3. `uServiceDaemon.pas`：worker 里 `TLWApp.Register(你的主窗体类)` + `RunService`；
   保留 `CreateNew` 事件绑定与 `GStoppingBySCM` 防假活逻辑。
4. `uServiceMapper.pas` + `.lfm`：改服务名、`DaemonClassName`、`DisplayName`。
   demo 的 mapper 带 `.lfm`；如果你不想维护资源文件，也可以照向导生成的样子
   改成纯代码（`inherited CreateNew(AOwner, 0)` + `DaemonDefs.Add`，见坑 195），
   那样一个 `.pas` 就够了。
5. `build.bat`：确认以 nogui widgetset 编译。
6. 管理员 `--install`，`sc.exe start`，浏览器验证；用 `service_demo.diag` / 日志排障。

> 若你的程序本来就有 GUI 面板需求：前台构建保留 GUI widgetset（显示面板），
> 服务构建用 nogui（无面板）。二者靠 `GServiceMode` 区分，互不影响。

---

## 10. 与其他宿主方式对比

| 方式 | 适用场景 | 额外依赖 |
|---|---|---|
| 本节 exe 自带服务 | 单 exe 部署、不想装第三方、要 Windows 服务语义（开机自启/标准运维） | 无（FPC 自带 DaemonApp） |
| systemd（deploy/README.md §6.1） | Linux / macOS | 系统自带 |
| nssm / 任务计划 | 包装任意 exe、完全不改代码 | 需安装 nssm |
| lwhyper（deploy/README.md §4.1） | 集群 + worker 崩溃守护 + 反向代理 + 热更新 | 框架自带 |

需要崩溃自动拉起又不想配故障恢复时，可直接用 lwhyper 托管（见 `WHYPER.md`）。

---

## 11. 验证清单

```bat
:: 1. 服务是否在跑
sc.exe query lazarusWebService                          :: STATE : 4 RUNNING

:: 2. 端口是否监听
netstat -ano | findstr :8081                            :: 有 LISTENING

:: 3. HTTP 是否通
curl --noproxy '*' http://127.0.0.1:8081/lw/healthz     :: 200

:: 4. 日志与诊断
type C:\lazarusWeb\demos\service_demo\service_demo.log
type C:\lazarusWeb\demos\service_demo\service_demo.diag  :: 应有 DoStart / worker.Execute 行

:: 5. 优雅停止后进程应消失
sc.exe stop lazarusWebService
tasklist /FI "IMAGENAME eq service_demo.exe"             :: 无 service_demo 进程
```

浏览器打开 `http://127.0.0.1:8081`，点 Ping 按钮应看到往返响应——至此服务版完全跑通。
