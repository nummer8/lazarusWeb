program reportsplug;
{ 进程级插件演示 :: 报表插件（独立 exe）

  同 notesplug / dashplug：这是一个完整的 lazarusWeb 服务，
  编译期只链入自己的模块单元（宿主不链接本单元）。
  宿主通过 lwroute 把 /p/reports/... 反向代理到这里。
}
{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, umod_reports;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb 插件：报表汇总';
  { 只注册本插件：默认主窗体 = 第一个注册的窗体（Reports） }
  RegisterModule;
  TLWApp.Run;
end.
