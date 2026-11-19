program dashplug;
{ 进程级插件演示 :: 仪表盘插件（独立 exe）

  同 notesplug：完整 lazarusWeb 服务，只链入自己的模块单元。
  宿主通过 lwroute 把 /p/dash/... 反向代理到这里。
}
{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, umod_dashboard;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb 插件：仪表盘';
  RegisterModule;
  TLWApp.Run;
end.
