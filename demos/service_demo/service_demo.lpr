{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: service_demo 主程序

  一个 exe，两种形态（前台行为与现有 demo 一字不差）：
    前台：service_demo.exe --port=8081
    服务：service_demo.exe --install 后由 SCM 以 --run 启动
}
program service_demo;

{$codepage utf8}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, DaemonApp, lwapp, uServiceForm, uServiceDaemon, uServiceMapper
  {$IFDEF MSWINDOWS}, SysUtils, Windows{$ENDIF};

{$IFDEF MSWINDOWS}
var
  ServiceManagerError: DWORD = 0;

{ DaemonApp 内部用 SC_MANAGER_ALL_ACCESS 打开 SCM；非提升进程会得到
  OS Code 5 = ERROR_ACCESS_DENIED。若不提前拦截，FCL 会先抛 EOSError，
  随后错误日志路径再抛一个误导性的 EInOutError: Disk Full。
  这里只做预检并给出明确提示，不改变 DaemonApp 的正常安装/卸载流程。 }
function CanManageWindowsServices: Boolean;
var
  Mgr: THandle;
begin
  Mgr := OpenSCManager(nil, nil, SC_MANAGER_ALL_ACCESS);
  Result := Mgr <> 0;
  if Result then
    CloseServiceHandle(Mgr)
  else
    ServiceManagerError := GetLastError;
end;
{$ENDIF}

begin
  if WantDaemonApp then
  begin
    {$IFDEF MSWINDOWS}
    { 安装/卸载需要管理员令牌；提前拦住，避免 FCL 抛出
      EOSError(OS Code 5) 后又跟一个误导性的 EInOutError: Disk Full。 }
    if NeedsServiceManagerAccess and (not CanManageWindowsServices) then
    begin
      WriteLn('ERROR: cannot open Windows Service Control Manager (OS Code '
        + IntToStr(ServiceManagerError) + ').');
      if ServiceManagerError = ERROR_ACCESS_DENIED then
        WriteLn('Please run this terminal as Administrator before --install / --uninstall.');
      ExitCode := 1;
      Exit;
    end;
    {$ENDIF}
    { 服务形态：DaemonApp 原生处理 --install/--uninstall/--run。
      Mapper 由 lfm 资源流式创建（见 uServiceMapper）；缺了它 DaemonApp
      会报 "No daemon mapper class registered"。
      DaemonApp 的 Application 与 Forms 的 Application 同名，必须完全限定。 }
    RegisterServiceDaemon;
    RegisterServiceMapper;
    DaemonApp.Application.Initialize;
    DaemonApp.Application.Run;    { install/uninstall 后立即返回；--run 阻塞到 Stop }
  end
  else
  begin
    { 前台形态：与 gallery/hello 等所有现有 demo 一字不差 —— GUI 构建
      照常显示服务端面板，nogui 构建同线程 accept。GServiceMode 默认 False。 }
    Application.Initialize;
    Application.Title := 'lazarusWeb · 服务演示';
    TLWApp.Register(TServiceForm);
    TLWApp.Run;
  end;
end.
