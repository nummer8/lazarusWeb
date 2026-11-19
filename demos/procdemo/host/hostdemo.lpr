program hostdemo;
{ 进程级插件演示 :: 主框架（宿主）

  不链接任何插件单元。插件 = 独立 exe：
    ../notesplug/notesplug.exe  127.0.0.1:8871
    ../dashplug/dashplug.exe    127.0.0.1:8872
  宿主 hostdemo.ini 里 plugin.<名>=host:port 登记，lwroute 反向代理。
}
{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, uhost;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb 主框架（进程级插件演示）';
  RegisterHost;
  TLWApp.Run;
end.
