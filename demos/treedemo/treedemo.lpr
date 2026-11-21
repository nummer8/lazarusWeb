program treedemo;

{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, uTreeMain;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb · TreeView / VirtualTreeView';
  TLWApp.Register(TTreeDemoForm);
  TLWApp.Run;
end.
