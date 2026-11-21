# lazarusWeb：生成的服务叫什么名字

> 服务(daemon)模式生成的服务名不需要手动填，但**命令行与 IDE 向导的结果不同**：
> 命令行按 `--name` 生成，IDE 向导固定为 `LWApp1Service`。
> 本文说明命名规则、改名步骤与相关运维命令。
>
> 相关文档：`WINDOWS_SERVICE.md`（安装/启停/排障全过程）、`MANUAL.md`「用 IDE 向导新建工程」。
> 记录时间：2026-11-20（按 `C:\3` 一次真实生成结果核对），2026-11-21 补充向导与命令行的差异。

## 1. 命名规则：两条路不一样

通用规则在 `src/core/lwnewproject.pas:379`：

```pascal
function LWServiceName(const O: TLWNewProject): string;
begin
  Result := O.Name + 'Service';
end;
```

由 `LWServiceMapperSource` 写进 mapper 的 `DD.Name`。**与 widgetset 档位无关**
（GUI / nogui 生成的服务名一样），但与"哪条路生成"有关：

| 生成路线 | 传入的 `O.Name` | 生成的服务名 |
|---|---|---|
| 命令行 `tools\lwnew --name=MyApp --service` | `--name` 的值（`tools/lwnew.lpr:102`） | `MyAppService` |
| IDE 新建工程向导 | 占位名 `LWApp1`（`lwdsgnregister.pas:128,429,478`） | **恒为 `LWApp1Service`** |

**IDE 向导的关键坑**：向导在保存前就用占位名 `LWApp1` 算好了 `.lpr` 和 `uMapper.pas`，
用户 Ctrl+S 时另存为别的工程名（如 `MyApp`），并不会重写 mapper 里的 `DD.Name`。
所以"服务名随工程名走"只对命令行成立；用向导时必须自己改 mapper 再重装。

## 2. 实例：`C:\3`（IDE 向导生成，工程名恰好也是 `LWApp1`）

| 项 | 值 | 说明 |
|---|---|---|
| 服务名（SCM 用的名字） | `LWApp1Service` | `sc.exe` / `net start` 用的就是它 |
| 显示名（服务管理器里看到的） | `lazarusWeb · LWApp1 Service` | 给人看的，带框架前缀 |
| 描述 | `lazarusWeb server running as a Windows service` | 服务属性页里的说明 |
| exe | `C:\3\LWApp1.exe` | 服务名与 exe 文件名无关 |
| 启动类型 | 自动（开机自启） | `DD.WinBindings.StartType := stAuto` |

`C:\3\umapper.pas` 第 29-38 行就是这段定义（模板里的文件名是 `uMapper.pas`，
IDE 保存虚拟工程时统一把文件名写成小写，所以磁盘上是 `umapper.pas`）：

```pascal
  DD := TDaemonDef(DaemonDefs.Add);
  DD.DaemonClassName := 'TLWServiceDaemon';
  DD.Name := 'LWApp1Service';
  DD.DisplayName := 'lazarusWeb · LWApp1 Service';
  DD.Description := 'lazarusWeb server running as a Windows service';
  DD.Options := [doAllowStop];
  DD.WinBindings.StartType := stAuto;      { 开机自启 }
  DD.WinBindings.ServiceType := stWin32;
  DD.WinBindings.ErrorSeverity := esIgnore;
  DD.LogStatusReport := False;
```

## 3. 改名字

服务名是**注册进 SCM 的**，不是运行时读配置，所以改名必须重装：

1. 改 mapper 单元里的 `DD.Name`（命令行生成的是 `uMapper.pas`，IDE 向导保存出来的是 `umapper.pas`；`C:\3` 这份在第 31 行；要改显示名就顺带改下一行）；
2. 重新编译；
3. 先卸载旧服务、再装新的：

```bat
LWApp1.exe --uninstall
LWApp1.exe --install
```

只改 exe 文件名、不改 `DD.Name` 是不行的——SCM 里认的是 `DD.Name`。

## 4. 常用运维命令

`build.bat` / `build.sh` 末尾已经写好这三行，可直接照抄：

```bat
C:\3\LWApp1.exe --install        :: 管理员运行
sc.exe start LWApp1Service
C:\3\LWApp1.exe --uninstall      :: 卸载
```

查状态、查真实注册信息：

```bat
sc.exe query LWApp1Service
sc.exe qc LWApp1Service
```

> 注意：PowerShell 里 `sc` 是 `Set-Content` 的别名，服务命令必须写全 `sc.exe`。

## 5. 顺带一个细节：ini 文件名的大小写

源码模板里的常量是驼峰 `lazarusWeb.ini`（`lwnewproject.pas:75`），命令行 `lwnew` 生成时保持这个写法；
**IDE 向导保存虚拟工程时把文件名统一写成小写**，所以 `C:\3` 里看到的是 `lazarusweb.ini`
（同目录的 `lwapp1.lpr` / `umapper.pas` 也是小写）。

Windows 文件系统大小写不敏感，运行期按 `lazarusWeb.ini` 查找仍能读到，**不影响使用**；
如果之后要拷到 Linux 上跑，把它改名成 `lazarusWeb.ini` 即可。

`C:\3\lazarusweb.ini` 当前内容：

```ini
; LWApp1 服务版配置（服务启动时 cwd 常是 System32，勿用相对路径）
client=alpine
port=8090

; Windows 服务没有控制台，建议开文件日志（按 exe 目录解析）
log=LWApp1.log
```

> 用固定名 `lazarusWeb.ini` 是刻意的：向导保存工程前还不知道最终工程名，
> 固定名才能保证「落盘之前就是对的」。查找顺序见 `lwconfig.pas:302-305`
> （`<exe目录>\<exe名>.ini` → `<exe目录>\lazarusWeb.ini` → 当前目录下的同名文件）。
