program acceldemo;

{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

{ 加速键（Caption 里的 &）渲染审计 demo：每一类带 Caption 的控件各摆一个，
  客户端按 LCL 规则把 &X 画成带下划线的 X、&& 画成字面 &。 }

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, uAccel;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb accel';
  TLWApp.Register(TAccelForm);
  TLWApp.Run;
end.
