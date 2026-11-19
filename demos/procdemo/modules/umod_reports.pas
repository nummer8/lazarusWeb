unit umod_reports;
{ 插件模块 3：报表页面 + /lw/ajax/reports_summary

  与 umod_dashboard 同一写法：纯代码建窗，没有 .lfm。
  模块契约只有一条 —— interface 段声明 procedure RegisterModule;
  实现里自己注册窗体与 AJAX 端点，不碰主程序。

  这个插件演示第三类职责：只读汇总。数据写死在插件进程里，
  页面负责展示，/lw/ajax/reports_summary 给外部脚本取同一份数。
  两个按钮用 TLWApp.OpenForm('注册名') 跳到另外两个插件页 ——
  本进程没有那些窗体，框架按 ini 的 page.<名>=<URL> 回退成整页跳转。 }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls,
  lwform, lwapp, lwajax, lwpluginutil;

type
  TReportsForm = class(TLWForm)
  private
    FLoadCount: Integer;
    FLblRevenue: TLabel;
    FLblCost: TLabel;
    FLblProfit: TLabel;
    FMemoRows: TMemo;
    FLblStatus: TLabel;
    FBtnReload: TButton;
    FBtnDash: TButton;
    FBtnNotes: TButton;
    FBtnHome: TButton;
    procedure BuildUI;
    procedure Reload(Sender: TObject);
    procedure OpenDash(Sender: TObject);
    procedure OpenNotes(Sender: TObject);
    procedure OpenHome(Sender: TObject);
  public
    procedure AfterConstruction; override;
  end;

  TReportsAjax = class
  public
    procedure Summary(A: TLWAjaxContext);
  end;

procedure RegisterModule;

implementation

const
  { 演示数据：固定在插件进程里，重点在"业务数据归插件自己所有" }
  ROW_COUNT = 4;
  ROW_NAME: array[0..ROW_COUNT - 1] of string =
    ('华东', '华南', '华北', '西部');
  ROW_REVENUE: array[0..ROW_COUNT - 1] of Integer =
    (128000, 96000, 74000, 42000);
  ROW_COST: array[0..ROW_COUNT - 1] of Integer =
    (82000, 61000, 52000, 31000);

var
  GAjax: TReportsAjax = nil;

{ 合计在这里算，页面与 AJAX 用同一份逻辑，避免两处对不上 }
function SumRevenue: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ROW_COUNT - 1 do
    Result := Result + ROW_REVENUE[i];
end;

function SumCost: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ROW_COUNT - 1 do
    Result := Result + ROW_COST[i];
end;

function Money(AValue: Integer): string;
begin
  Result := FormatFloat('#,##0', AValue);
end;

procedure TReportsForm.BuildUI;

  function AddLabel(const AName, ACap: string; L, T, W, H: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Name := AName;        { 先 Name 后 Caption：SetName 会回填文本 }
    Result.Parent := Self;
    Result.SetBounds(L, T, W, H);
    Result.Caption := ACap;
  end;

  { 指标卡：面板 + 标题 + 数值，数值 label 通过 out 返回 }
  function AddCard(const AName, ACap: string; L: Integer;
    out AValue: TLabel): TPanel;
  var
    cap: TLabel;
  begin
    Result := TPanel.Create(Self);
    Result.Name := AName;
    Result.Parent := Self;
    Result.SetBounds(L, 64, 220, 90);
    Result.BevelOuter := bvNone;
    cap := TLabel.Create(Self);
    cap.Name := AName + 'Cap';
    cap.Parent := Result;
    cap.SetBounds(14, 12, 190, 18);
    cap.Caption := ACap;
    AValue := TLabel.Create(Self);
    AValue.Name := AName + 'Value';
    AValue.Parent := Result;
    AValue.SetBounds(14, 38, 190, 34);
    AValue.Caption := '-';
  end;

begin
  if Width < 760 then Width := 760;
  if Height < 560 then Height := 560;
  Caption := '报表汇总（插件）';
  if Name = '' then Name := 'Reports';

  AddLabel('lblTitle', '报表汇总 — 本页面由插件 umod_reports 提供', 24, 20, 700, 26);
  AddLabel('lblSub', '第三个插件进程：只读汇总 + /lw/ajax/reports_summary 导出同一份数据。',
    24, 44, 700, 18);

  AddCard('cardRevenue', '累计收入', 24, FLblRevenue);
  AddCard('cardCost', '累计成本', 264, FLblCost);
  AddCard('cardProfit', '累计毛利', 504, FLblProfit);

  FBtnReload := TButton.Create(Self);
  FBtnReload.Name := 'btnReload';
  FBtnReload.Parent := Self;
  FBtnReload.SetBounds(24, 172, 140, 30);
  FBtnReload.Caption := '重新汇总';
  FBtnReload.OnClick := @Reload;

  { 跨进程跳转：本进程没有 Dashboard / Notes，OpenForm 走 ini 的 page.* 映射 }
  FBtnDash := TButton.Create(Self);
  FBtnDash.Name := 'btnOpenDash';
  FBtnDash.Parent := Self;
  FBtnDash.SetBounds(176, 172, 140, 30);
  FBtnDash.Caption := '打开仪表盘';
  FBtnDash.OnClick := @OpenDash;

  FBtnNotes := TButton.Create(Self);
  FBtnNotes.Name := 'btnOpenNotes';
  FBtnNotes.Parent := Self;
  FBtnNotes.SetBounds(328, 172, 140, 30);
  FBtnNotes.Caption := '打开便签页';
  FBtnNotes.OnClick := @OpenNotes;

  FBtnHome := TButton.Create(Self);
  FBtnHome.Name := 'btnHome';
  FBtnHome.Parent := Self;
  FBtnHome.SetBounds(480, 172, 140, 30);
  FBtnHome.Caption := '返回首页';
  FBtnHome.OnClick := @OpenHome;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Name := 'lblStatus';
  FLblStatus.Parent := Self;
  FLblStatus.SetBounds(632, 179, 96, 18);
  FLblStatus.Caption := '等待汇总';

  FMemoRows := TMemo.Create(Self);
  FMemoRows.Name := 'memoRows';
  FMemoRows.Parent := Self;
  FMemoRows.SetBounds(24, 216, 700, 264);
  FMemoRows.ScrollBars := ssAutoVertical;
  FMemoRows.Font.Name := 'Consolas';
  FMemoRows.ParentFont := False;

  Reload(nil);
end;

procedure TReportsForm.AfterConstruction;
begin
  inherited AfterConstruction;
  if csDesigning in ComponentState then Exit;
  if ControlCount > 0 then Exit;
  BuildUI;
end;

procedure TReportsForm.Reload(Sender: TObject);
var
  i, profit: Integer;
begin
  Inc(FLoadCount);
  FLblRevenue.Caption := Money(SumRevenue);
  FLblCost.Caption := Money(SumCost);
  FLblProfit.Caption := Money(SumRevenue - SumCost);

  FMemoRows.Lines.BeginUpdate;
  try
    FMemoRows.Lines.Clear;
    FMemoRows.Lines.Add('区域      收入          成本          毛利');
    FMemoRows.Lines.Add('----------------------------------------------');
    for i := 0 to ROW_COUNT - 1 do
    begin
      profit := ROW_REVENUE[i] - ROW_COST[i];
      FMemoRows.Lines.Add(Format('%-8s %10s %13s %13s',
        [ROW_NAME[i], Money(ROW_REVENUE[i]), Money(ROW_COST[i]), Money(profit)]));
    end;
    FMemoRows.Lines.Add('----------------------------------------------');
    FMemoRows.Lines.Add(Format('%-8s %10s %13s %13s',
      ['合计', Money(SumRevenue), Money(SumCost), Money(SumRevenue - SumCost)]));
  finally
    FMemoRows.Lines.EndUpdate;
  end;

  FLblStatus.Caption := '第 ' + IntToStr(FLoadCount) + ' 次汇总';
end;

procedure TReportsForm.OpenDash(Sender: TObject);
begin
  if not TLWApp.OpenForm('Dashboard') then
    FLblStatus.Caption := '跳转失败：未登记 page.Dashboard';
end;

procedure TReportsForm.OpenNotes(Sender: TObject);
begin
  if not TLWApp.OpenForm('Notes') then
    FLblStatus.Caption := '跳转失败：未登记 page.Notes';
end;

procedure TReportsForm.OpenHome(Sender: TObject);
begin
  if not TLWApp.OpenForm('Host') then
    FLblStatus.Caption := '跳转失败：未登记 page.Host';
end;

procedure TReportsAjax.Summary(A: TLWAjaxContext);
var
  i: Integer;
  rows: string;
begin
  rows := '';
  for i := 0 to ROW_COUNT - 1 do
  begin
    if rows <> '' then
      rows := rows + ',';
    rows := rows + '{"region":"' + JsonEscape(ROW_NAME[i]) +
      '","revenue":' + IntToStr(ROW_REVENUE[i]) +
      ',"cost":' + IntToStr(ROW_COST[i]) +
      ',"profit":' + IntToStr(ROW_REVENUE[i] - ROW_COST[i]) + '}';
  end;
  A.Json('{"ok":true,"module":"reports","rows":[' + rows + ']' +
    ',"totalRevenue":' + IntToStr(SumRevenue) +
    ',"totalCost":' + IntToStr(SumCost) +
    ',"totalProfit":' + IntToStr(SumRevenue - SumCost) +
    ',"serverTime":"' + FormatDateTime('yyyy-mm-dd', Now) + 'T' +
    FormatDateTime('hh:nn:ss', Now) + '"}');
end;

procedure RegisterModule;
begin
  { 显式注册名：跨插件跳转用 OpenForm('Reports') 也认这个名字 }
  TLWApp.RegisterForm('Reports', TReportsForm);
  if GAjax = nil then
    GAjax := TReportsAjax.Create;
  TLWApp.AddAjax('reports_summary', @GAjax.Summary);
end;

end.
