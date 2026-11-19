program notesplug;
{ 进程级插件演示 :: 便签插件（独立 exe）

  这是一个完整的 lazarusWeb 服务：编译期只链入自己的模块单元
  （这是"插件 exe 自己怎么构建"，与宿主无关 —— 宿主不链接本单元）。
  宿主通过 lwroute 把 /p/notes/... 反向代理到这里。
}
{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, umod_notes;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb 插件：便签';
  { 只注册本插件：默认主窗体 = 第一个注册的窗体（Notes） }
  RegisterModule;
  TLWApp.Run;
end.
