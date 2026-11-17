program mobile_demo;

{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, uMobileMain;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb · mobile_demo';
  TLWApp.Register(TMobileMainForm);
  TLWApp.Run;
end.
