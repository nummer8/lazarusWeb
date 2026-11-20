{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: service_demo 服务守护

  演示如何把 lazarusWeb 服务端装成真正的 Windows 服务（SCM 管理，
  开机自启、崩溃可配自动重启），同一个 exe 也保留前台运行能力。

  命令行分流（-i/--install、-u/--uninstall、-r/--run 由 DaemonApp 原生处理，
  这样 mapper 里的 StartType=stAuto 开机自启等配置才生效）：
    service_demo.exe --install       注册服务（开机自启，需管理员）
    service_demo.exe --uninstall     卸载服务（需管理员）
    service_demo.exe --run           服务模式（由 SCM 通过 ImagePath 调用）
    service_demo.exe --port=8081     前台运行（与旧版完全一致，GUI 构建显示面板）

  注意：--install/--uninstall 必须管理员权限（OpenSCManager 要
  SC_MANAGER_ALL_ACCESS）；主程序会先预检并给出清晰提示，避免 FCL 连抛
  EOSError(OS Code 5) 与误导性的 EInOutError: Disk Full。

  机制：
    - 用 FPC 自带的 DaemonApp（fcl-extra）——不依赖 IDE 的 lazdaemon 包，
      避免 win32 版 lazdaemonapp.ppu 与 nogui widgetset 冲突。
    - TDaemon.OnStart 起 worker 线程调 TLWApp.RunService（阻塞在 accept）；
      TDaemon.OnStop 调 TLWApp.StopService 唤醒它，再 WaitFor 等正常收尾。
      阻塞循环绝不放 TDaemon.Execute 主线程，否则服务不再响应 SCM 控制。
    - 纯代码注册守护类 + 事件（mapper 的 lfm 见 uServiceMapper）。
}
unit uServiceDaemon;

{$mode objfpc}{$H+}

interface

{ 是否应走 DaemonApp（服务管理命令或服务运行模式）。
  False = 前台运行，主程序走原来的 TLWApp.Run。 }
function WantDaemonApp: Boolean;

{ 仅 --install / --uninstall 需要打开 SCM（SC_MANAGER_ALL_ACCESS）。
  --run 是 SCM 以 LocalSystem 启动的，不需要当前用户提权。 }
function NeedsServiceManagerAccess: Boolean;

{ 注册守护类；必须在 DaemonApp.Application.Initialize 之前调用 }
procedure RegisterServiceDaemon;

implementation

uses
  Classes, SysUtils, DaemonApp, lwapp, lwrlog, uServiceForm;

const
  { 诊断文件：绕过 LWLog（服务 cwd=System32、日志系统可能没起来），
    直接写 exe 目录的绝对路径。定位"服务假活"用；稳定后可删。 }
  DIAG_FILE = 'service_demo.diag';

procedure Diag(const AMsg: string);
var
  F: TextFile;
  P: string;
begin
  try
    P := IncludeTrailingPathDelimiter(
           ExtractFileDir(ExpandFileName(ParamStr(0)))) + DIAG_FILE;
    AssignFile(F, P);
    {$I-}
    if FileExists(P) then Append(F) else Rewrite(F);
    Writeln(F, FormatDateTime('hh:nn:ss', Now) + '  ' + AMsg);
    CloseFile(F);
    {$I+}
  except
    { 诊断失败绝不能影响服务 }
  end;
end;

var
  { SCM 正常 Stop 时置 True：此时 worker 退出是预期内，不要 Halt。
    其它任何原因导致 worker 结束（配置错误、端口被占用等）都视为服务
    已失效，必须让进程退出，否则 SCM 永远显示 Running 的"假活"。 }
  GStoppingBySCM: Boolean = False;

type
  TLWWorkerThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TLWServiceDaemon = class(TDaemon)
  private
    FWorker: TLWWorkerThread;
    procedure BindEvents;
  public
    constructor Create(AOwner: TComponent); override;
    { 关键：FPC 框架用 DaemonClass.CreateNew(Self,0) 创建 daemon 实例，
      TDataModule.CreateNew 内部走 inherited Create，**不会调用 override 的
      Create**。必须 override CreateNew 并在其中绑定 OnStart/OnStop，
      否则 FOnStart=nil，DoStart 永不触发（服务"假活"：SCM 显示 Running，
      但没有 worker、不监听端口）。 }
    constructor CreateNew(AOwner: TComponent; CreateMode: Integer); override;
    procedure DoStart(Sender: TCustomDaemon; var OK: Boolean);
    procedure DoStop(Sender: TCustomDaemon; var OK: Boolean);
  end;

{ ---------------- worker 线程 ---------------- }

procedure TLWWorkerThread.Execute;
begin
  Diag('worker.Execute 进入，即将调用 TLWApp.RunService');
  { 服务模式和前台一样必须先注册主窗体：Run 内部用 GOrder[0] 设 DefaultForm，
    不注册则 DefaultForm=''，建会话时报 "no form specified"。前台分支在 lpr
    里调了 TLWApp.Register(TServiceForm)，这里 worker 走的是另一条分支，需补上。 }
  TLWApp.Register(TServiceForm);
  try
    { 阻塞直到 StopService 唤醒；RunService 内部不 Halt、走正常收尾 }
    TLWApp.RunService;
    Diag('TLWApp.RunService 已返回');
  except
    on E: Exception do
    begin
      Diag('worker 异常: ' + E.ClassName + ': ' + E.Message);
      LWLog('[service] worker 线程异常: ' + E.ClassName + ': ' + E.Message);
    end;
  end;
  LWLog('[service] worker 线程已退出');
  { 非 SCM 主动停止（如端口被占用、根目录不存在导致 RunService 提前返回），
    服务器其实已经死了。若此时还给 SCM 留一个空壳主进程，services.msc
    会一直显示"正在运行"却没人监听端口。直接 Halt 让 SCM 看到真实状态，
    配合故障恢复(sc.exe failure restart)还能自动拉起。 }
  if not GStoppingBySCM then
  begin
    LWLog('[service] worker 非正常退出，终止服务进程（避免 SCM 假活）');
    Halt(1);
  end;
end;

{ ---------------- TDaemon ---------------- }

procedure TLWServiceDaemon.BindEvents;
begin
  { 纯代码绑定事件（mapper 的 lfm 只声明守护类，不声明事件）。
    必须从 Create 和 CreateNew 两处都调用：框架实际走 CreateNew。 }
  OnStart := @DoStart;
  OnStop := @DoStop;
end;

constructor TLWServiceDaemon.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BindEvents;
end;

constructor TLWServiceDaemon.CreateNew(AOwner: TComponent; CreateMode: Integer);
begin
  inherited CreateNew(AOwner, CreateMode);
  BindEvents;
end;

procedure TLWServiceDaemon.DoStart(Sender: TCustomDaemon; var OK: Boolean);
begin
  Diag('DoStart 进入（OnStart 已触发）');
  LWLog('[service] 收到 SCM Start，启动 lazarusWeb worker 线程');
  FWorker := TLWWorkerThread.Create(True);   { 挂起，先设属性再 Start }
  FWorker.FreeOnTerminate := False;
  FWorker.Start;
  Diag('worker 线程已 Start');
  OK := True;
end;

procedure TLWServiceDaemon.DoStop(Sender: TCustomDaemon; var OK: Boolean);
begin
  GStoppingBySCM := True;   { 标记：worker 随后的退出是 SCM 正常流程，不要 Halt }
  LWLog('[service] 收到 SCM Stop，请求 lazarusWeb 优雅退出');
  { 唤醒阻塞在 accept 循环的 RunService；早停竞态由 lwapp 内部兜底 }
  TLWApp.StopService;
  if FWorker <> nil then
  begin
    FWorker.WaitFor;    { 等 RunService 走完 finally、释放服务器 }
    FWorker.Free;
    FWorker := nil;
  end;
  LWLog('[service] 已停止');
  OK := True;
end;

procedure RegisterServiceDaemon;
begin
  RegisterDaemonClass(TLWServiceDaemon);
end;

{ ---------------- 命令行分流 ---------------- }

function NeedsServiceManagerAccess: Boolean;
var
  i: Integer;
  arg: string;
begin
  Result := False;
  for i := 1 to ParamCount do
  begin
    arg := LowerCase(ParamStr(i));
    if (arg = '--install') or (arg = '-i') or
       (arg = '--uninstall') or (arg = '-u') then
      Exit(True);
  end;
end;

function WantDaemonApp: Boolean;
var
  i: Integer;
  arg: string;
begin
  Result := False;
  for i := 1 to ParamCount do
  begin
    arg := LowerCase(ParamStr(i));
    { DaemonApp 原生命令 + 服务运行模式：都交给它处理 }
    if (arg = '--install') or (arg = '-i') or
       (arg = '--uninstall') or (arg = '-u') or
       (arg = '--run') or (arg = '-r') or
       (arg = '--service') then
      Exit(True);
  end;
  { 其余（无参数 / --port= 等）一律前台运行，行为与旧版一致 }
end;

end.
