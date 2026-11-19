unit umod_dashboard;
{ 插件模块 1：仪表盘页面 + /lw/ajax/dashboard_stats

  约定（生成器按此识别模块）：
    - 单元 interface 段声明 procedure RegisterModule;
    - 实现里注册窗体 / AJAX 端点，不碰主程序。
  新增模块只需复制本文件改名字，再跑 tools/lwplugins.py 重生成 lwmodules.pas。

  界面两种写法都行：
    - umod_notes.pas + umod_notes.lfm：Lazarus 常规做法，IDE 里拖控件；
    - 本文件：纯代码建窗，适合动态生成或没有 .lfm 的场景。 }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls,
  lwform, lwapp, lwajax;

type
  TDashboardForm = class(TLWForm)
  private
    FStartTick: QWord;
    FRefreshCount: Integer;
    FLblModule: TLabel;
    FLblHits: TLabel;
    FLblUptime: TLabel;
    FBar: TProgressBar;
    FMemo: TMemo;
    FBtnRefresh: TButton;
    FBtnNotes: TButton;
    FBtnReports: TButton;
    FBtnHome: TButton;
    procedure BuildUI;
    procedure RefreshStats(Sender: TObject);
    procedure OpenNotes(Sender: TObject);
    procedure OpenReports(Sender: TObject);
    procedure OpenHome(Sender: TObject);
  public
    procedure AfterConstruction; override;
  end;

  TDashboardAjax = class
  public
    procedure Stats(A: TLWAjaxContext);
  end;

procedure RegisterModule;

implementation

var
  GAjax: TDashboardAjax = nil;
  GAjaxCalls: Integer = 0;

procedure TDashboardForm.BuildUI;

  function AddLabel(const AName, ACap: string; L, T, W, H: Integer): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Name := AName;        { 先 Name 后 Caption：SetName 会回填文本 }
    Result.Parent := Self;
    Result.SetBounds(L, T, W, H);
    Result.Caption := ACap;
  end;

  { 指标卡：面板 + 标题 + 数值，数值 label 通过 out 返回给调用方 }
  function AddCard(const AName, ACap: string; L: Integer; out AValue: TLabel): TPanel;
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
  { 空窗体是 LCL 默认尺寸，装不下这些控件 }
  if Width < 760 then Width := 760;
  if Height < 560 then Height := 560;
  Caption := '模块仪表盘（插件）';
  if Name = '' then Name := 'Dashboard';

  AddLabel('lblTitle', '模块仪表盘 — 本页面由插件 umod_dashboard 提供', 24, 20, 700, 26);
  AddLabel('lblSub', '主程序里没有这个窗体，它只调用了 RegisterAllModules。', 24, 44, 700, 18);

  AddCard('cardModule', '当前模块', 24, FLblModule);
  AddCard('cardHits', 'AJAX 调用次数', 264, FLblHits);
  AddCard('cardUptime', '进程运行时长', 504, FLblUptime);

  FBar := TProgressBar.Create(Self);
  FBar.Name := 'barHealth';
  FBar.Parent := Self;
  FBar.SetBounds(24, 172, 700, 18);
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.Position := 40;

  FBtnRefresh := TButton.Create(Self);
  FBtnRefresh.Name := 'btnRefresh';
  FBtnRefresh.Parent := Self;
  FBtnRefresh.SetBounds(24, 204, 140, 30);
  FBtnRefresh.Caption := '刷新指标';
  FBtnRefresh.OnClick := @RefreshStats;

  { 跨插件导航：本进程只有 Dashboard。另两个插件与宿主首页都不在本进程，
    靠各 ini 的 page.<注册名>=<URL> 映射，OpenForm 回退成整页跳转。
    三个插件页的导航按钮因此完全对称：另两个插件 + 返回首页 }
  FBtnNotes := TButton.Create(Self);
  FBtnNotes.Name := 'btnOpenNotes';
  FBtnNotes.Parent := Self;
  FBtnNotes.SetBounds(176, 204, 140, 30);
  FBtnNotes.Caption := '打开便签页';
  FBtnNotes.OnClick := @OpenNotes;

  FBtnReports := TButton.Create(Self);
  FBtnReports.Name := 'btnOpenReports';
  FBtnReports.Parent := Self;
  FBtnReports.SetBounds(328, 204, 140, 30);
  FBtnReports.Caption := '打开报表页';
  FBtnReports.OnClick := @OpenReports;

  FBtnHome := TButton.Create(Self);
  FBtnHome.Name := 'btnHome';
  FBtnHome.Parent := Self;
  FBtnHome.SetBounds(480, 204, 140, 30);
  FBtnHome.Caption := '返回首页';
  FBtnHome.OnClick := @OpenHome;

  FMemo := TMemo.Create(Self);
  FMemo.Name := 'memoLog';
  FMemo.Parent := Self;
  FMemo.SetBounds(24, 248, 700, 220);
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.Lines.Add('插件自检：');
  FMemo.Lines.Add('  1) 本窗体的控件全部由插件代码创建，没有 .lfm；');
  FMemo.Lines.Add('  2) 事件仍由框架派发 —— 点"刷新指标"看服务端计数与日志；');
  FMemo.Lines.Add('  3) /lw/ajax/dashboard_stats 由本插件注册；');
  FMemo.Lines.Add('  4) 三个插件页的导航一致：「打开便签页」「打开报表页」「返回首页」，');
  FMemo.Lines.Add('     都走 TLWApp.OpenForm(注册名)，本进程没有目标窗体时按 ini 的');
  FMemo.Lines.Add('     page.<注册名>=<URL> 回退成整页跳转。返回首页 = page.Host=/ 。');

  RefreshStats(nil);
end;

procedure TDashboardForm.AfterConstruction;
begin
  { inherited 会走 TCustomForm.AfterConstruction -> DoCreate(OnCreate)，
    先让它跑完，再判断"设计期是不是已经有控件" }
  inherited AfterConstruction;
  if csDesigning in ComponentState then Exit;
  if ControlCount > 0 then Exit;
  FStartTick := GetTickCount64;
  BuildUI;
end;

procedure TDashboardForm.RefreshStats(Sender: TObject);
var
  secs: QWord;
begin
  Inc(FRefreshCount);
  secs := (GetTickCount64 - FStartTick) div 1000;
  FLblModule.Caption := 'umod_dashboard';
  FLblUptime.Caption := IntToStr(secs) + ' 秒';
  FLblHits.Caption := IntToStr(GAjaxCalls);
  { 进度条只是顺手证明控件能正常下发与回写 }
  FBar.Position := (FRefreshCount * 7) mod 101;
  FMemo.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  刷新：进程已运行 ' +
    IntToStr(secs) + ' 秒，AJAX 累计 ' + IntToStr(GAjaxCalls) + ' 次');
end;

procedure TDashboardForm.OpenNotes(Sender: TObject);
var
  stamp: string;
begin
  stamp := FormatDateTime('hh:nn:ss', Now);
  if TLWApp.OpenForm('Notes') then
    FMemo.Lines.Add(stamp + '  已打开便签页')
  else
    FMemo.Lines.Add(stamp + '  打开失败，已注册窗体：' + TLWApp.FormNames);
end;

procedure TDashboardForm.OpenReports(Sender: TObject);
var
  stamp: string;
begin
  stamp := FormatDateTime('hh:nn:ss', Now);
  if TLWApp.OpenForm('Reports') then
    FMemo.Lines.Add(stamp + '  已打开报表页')
  else
    FMemo.Lines.Add(stamp + '  打开失败，未登记 page.Reports');
end;

procedure TDashboardForm.OpenHome(Sender: TObject);
var
  stamp: string;
begin
  stamp := FormatDateTime('hh:nn:ss', Now);
  if TLWApp.OpenForm('Host') then
    FMemo.Lines.Add(stamp + '  已返回首页')
  else
    FMemo.Lines.Add(stamp + '  打开失败，未登记 page.Host');
end;

procedure TDashboardAjax.Stats(A: TLWAjaxContext);begin
  Inc(GAjaxCalls);
  A.Json('{"ok":true,"module":"dashboard","ajaxCalls":' + IntToStr(GAjaxCalls) +
    ',"serverTime":"' + FormatDateTime('yyyy-mm-dd', Now) + 'T' +
    FormatDateTime('hh:nn:ss', Now) + '"}');
end;

procedure RegisterModule;
begin
  { 显式注册名：与窗体 Name 保持一致，URL 用 /?form=Dashboard 或 --form=Dashboard }
  TLWApp.RegisterForm('Dashboard', TDashboardForm);
  if GAjax = nil then
    GAjax := TDashboardAjax.Create;
  TLWApp.AddAjax('dashboard_stats', @GAjax.Stats);
end;

end.
