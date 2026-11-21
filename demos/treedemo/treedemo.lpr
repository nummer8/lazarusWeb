program treedemo;

{$mode objfpc}{$H+}

{ Windows 下默认按 GUI 子系统链接 —— 双击 exe / F9 都只有 lazarusWeb 的服务
  面板，不再多一个黑色控制台窗口。日志不受影响：框架的 lwrlog 本来就会写进
    面板（lwpanel），ini 里配 log=<文件> 或命令行 --log=<文件> 还能同时落盘。
  要临时在控制台里看输出（排查启动问题），编译时加 -dTREEDEMO_CONSOLE。 }
{$IFDEF MSWINDOWS}
  {$IFDEF TREEDEMO_CONSOLE}
    {$APPTYPE CONSOLE}
  {$ELSE}
    {$APPTYPE GUI}
  {$ENDIF}
{$ENDIF}

{ 这个 demo 用 VirtualTreeView —— 它是必须真实 GDI/Canvas 的 GUI 控件：
  构造时要把资源位图转成 RawImage，选中/滚动时要窗口度量。框架默认把
   会话窗体（跑在 HTTP 工作线程）路由到无头 widgetset（lwproxyws），
  在那里上面这些操作会抛 FPImageException / EDivByZero。

  所以这里显式打开开关，让工作线程也用真实 widgetset。
  代价是失去框架原本靠"无头路由"提供的线程隔离 —— 本地单用户 demo
  可以接受；正式部署请勿照搬。 }
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, lwproxyws, uTreeMain;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb · TreeView / VirtualTreeView';
  LWProxyUseRealWidgetSet(True);
  TLWApp.Register(TTreeDemoForm);
  TLWApp.Run;
end.
