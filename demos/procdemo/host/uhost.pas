unit uhost;
{ 进程级插件演示 :: 主框架页面

  这个 exe 不链接任何插件单元 —— 它只是 lazarusWeb 框架 + 一个导航页。
  插件（notesplug.exe / dashplug.exe）是独立进程，各自监听各自端口；
  本 exe 的 ini 里用 plugin.<名>=host:port 登记，路由由框架的 lwroute
  反向代理完成：浏览器访问 /p/notes/ 即可打开便签插件的页面。
}
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Graphics,
  lwform, lwapp;

type
  THostForm = class(TLWForm)
  private
    FLblTitle: TLabel;
    FLblSub: TLabel;
    FBtnDash: TButton;
    FBtnNotes: TButton;
    FBtnReports: TButton;
    FMemo: TMemo;
    procedure BuildUI;
    procedure OpenDash(Sender: TObject);
    procedure OpenNotes(Sender: TObject);
    procedure OpenReports(Sender: TObject);
  public
    procedure AfterConstruction; override;
  end;

procedure RegisterHost;

implementation

{ 主框架（宿主）注册名：默认主窗体 = 第一个注册的窗体 }
procedure RegisterHost;
begin
  TLWApp.RegisterForm('Host', THostForm);
end;

procedure THostForm.AfterConstruction;
begin
  inherited AfterConstruction;
  if csDesigning in ComponentState then Exit;
  if ControlCount > 0 then Exit;
  BuildUI;
end;

procedure THostForm.BuildUI;
begin
  if Width < 760 then Width := 760;
  if Height < 480 then Height := 480;
  Caption := 'lazarusWeb 主框架（插件是独立 exe）';

  FLblTitle := TLabel.Create(Self);
  FLblTitle.Name := 'lblTitle';
  FLblTitle.Parent := Self;
  FLblTitle.SetBounds(24, 20, 700, 26);
  FLblTitle.Caption := 'lazarusWeb 主框架 —— 本页面不含任何插件单元';
  FLblTitle.Font.Height := -16;
  FLblTitle.Font.Style := [fsBold];
  FLblTitle.ParentFont := False;

  FLblSub := TLabel.Create(Self);
  FLblSub.Name := 'lblSub';
  FLblSub.Parent := Self;
  FLblSub.SetBounds(24, 52, 700, 18);
  FLblSub.Caption := '插件 = 独立 exe（notesplug / dashplug / reportsplug），由 lwroute 按 /p/<名>/ 反向代理。';

  FBtnDash := TButton.Create(Self);
  FBtnDash.Name := 'btnDash';
  FBtnDash.Parent := Self;
  FBtnDash.SetBounds(24, 92, 220, 34);
  FBtnDash.Caption := '打开仪表盘插件（本标签）';
  FBtnDash.OnClick := @OpenDash;

  FBtnNotes := TButton.Create(Self);
  FBtnNotes.Name := 'btnNotes';
  FBtnNotes.Parent := Self;
  FBtnNotes.SetBounds(256, 92, 220, 34);
  FBtnNotes.Caption := '打开便签插件（本标签）';
  FBtnNotes.OnClick := @OpenNotes;

  FBtnReports := TButton.Create(Self);
  FBtnReports.Name := 'btnReports';
  FBtnReports.Parent := Self;
  FBtnReports.SetBounds(488, 92, 236, 34);
  FBtnReports.Caption := '打开报表插件（本标签）';
  FBtnReports.OnClick := @OpenReports;

  FMemo := TMemo.Create(Self);
  FMemo.Name := 'memoLog';
  FMemo.Parent := Self;
  FMemo.SetBounds(24, 140, 700, 280);
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.Lines.Add('工作原理：');
  FMemo.Lines.Add('  1) 每个插件是独立的 lazarusWeb 服务 exe（自己监听 127.0.0.1 上的端口）；');
  FMemo.Lines.Add('  2) 宿主 ini 里登记：plugin.notes=127.0.0.1:8871 / plugin.dash=127.0.0.1:8872');
  FMemo.Lines.Add('     / plugin.reports=127.0.0.1:8873；');
  FMemo.Lines.Add('  3) 浏览器请求 /p/notes/... 时，宿主的 lwroute 剥掉前缀转发给插件进程；');
  FMemo.Lines.Add('  4) 插件页面里的 API 调用按页面路径自动带上 /p/notes/ 前缀，代理后原样回插件；');
  FMemo.Lines.Add('  5) 推送走长轮询（经代理），WebSocket 暂不透传 —— 前端自动回退，功能无损失。');
  FMemo.Lines.Add('  6) 职责划分：插件只负责业务 —— lw.js 等框架静态资源由宿主直出，');
  FMemo.Lines.Add('     不进插件；升级客户端运行时只换宿主一处。');
  FMemo.Lines.Add('');
  FMemo.Lines.Add('点上面的按钮在【本标签】打开插件页面（location.href 同标签跳转）；');
  FMemo.Lines.Add('每个插件页都带「返回首页」（各插件 ini 的 page.Host=/），也能用浏览器「后退」。');
end;

procedure THostForm.OpenDash(Sender: TObject);
begin
  { 同标签跳转：用 location.href 而不是 window.open(...,"_blank")。
    地址栏变成 /p/dash/，插件的 API 仍按页面路径推导 BASE 落回代理前缀；
    浏览器「后退」直接回本宿主页，无需插件知道宿主地址 }
  RunJS('location.href=''/p/dash/''');
end;

procedure THostForm.OpenNotes(Sender: TObject);
begin
  RunJS('location.href=''/p/notes/''');
end;

procedure THostForm.OpenReports(Sender: TObject);
begin
  RunJS('location.href=''/p/reports/''');
end;

end.
