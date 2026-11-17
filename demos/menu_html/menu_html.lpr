program menu_html;

{$mode objfpc}{$H+}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, lwapp, uMenuHtml;

begin
  Application.Initialize;
  Application.Title := 'lazarusWeb · menu_html';
  TLWApp.Register(TMenuHtmlForm);
  TLWApp.Run;
end.
