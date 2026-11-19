unit umod_notes;
{ 插件模块 2：便签页面 + /lw/ajax/notes_export

  这个模块用 Lazarus 的标准做法：界面放 umod_notes.lfm（IDE 里双击就能拖控件），
  单元里用 $R *.lfm 指令把它嵌进可执行文件 —— 与普通 LCL 工程完全一样，
  不需要往 .lpi 里单独登记资源。

  字段与方法都放在类声明的默认可见性（published）段，LCL 的 TReader
  才能在装载 .lfm 时把组件和事件接上。 }
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  lwform, lwapp, lwajax, lwpluginutil;

type
  TNotesForm = class(TLWForm)
    lblTitle: TLabel;
    lblSub: TLabel;
    lblTitleCap: TLabel;
    edTitle: TEdit;
    lblTextCap: TLabel;
    memoText: TMemo;
    btnSave: TButton;
    btnClear: TButton;
    lblStatus: TLabel;
    lblListCap: TLabel;
    lstNotes: TListBox;
    btnBack: TButton;
    btnOpenReports: TButton;
    btnHome: TButton;
    procedure btnSaveClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure btnBackClick(Sender: TObject);
    procedure btnOpenReportsClick(Sender: TObject);
    procedure btnHomeClick(Sender: TObject);
  public
    procedure AfterConstruction; override;
  end;

  TNotesAjax = class
  public
    procedure Export(A: TLWAjaxContext);
  end;

procedure RegisterModule;

implementation

{ 把同目录的 umod_notes.lfm 编进 exe 的资源段；LCL 的 TForm.Create
  按类名去找这份资源，因此插件窗体只要被 uses 进来就能加载界面。 }
{$R *.lfm}

var
  GAjax: TNotesAjax = nil;
  GNotes: TStringList = nil;

procedure TNotesForm.AfterConstruction;
begin
  inherited AfterConstruction;
  if csDesigning in ComponentState then Exit;
  { .lfm 已经把控件和事件装好了，这里只做运行期状态初始化 }
  lstNotes.Items.Clear;
  lblStatus.Caption := '等待操作';
  edTitle.Text := '';
  memoText.Lines.Clear;
end;

procedure TNotesForm.btnSaveClick(Sender: TObject);
var
  t: string;
begin
  t := Trim(edTitle.Text);
  if t = '' then
  begin
    lblStatus.Caption := '标题不能为空';
    Exit;
  end;
  if GNotes = nil then
    GNotes := TStringList.Create;
  GNotes.Add(t);
  lstNotes.Items.Add(IntToStr(GNotes.Count) + '. ' + t);
  lblStatus.Caption := '已保存「' + t + '」，共 ' + IntToStr(GNotes.Count) + ' 条';
  edTitle.Text := '';
  memoText.Lines.Clear;
end;

procedure TNotesForm.btnClearClick(Sender: TObject);
begin
  edTitle.Text := '';
  memoText.Lines.Clear;
  lblStatus.Caption := '已清空输入（列表保留）';
end;

procedure TNotesForm.btnBackClick(Sender: TObject);
begin
  if not TLWApp.OpenForm('Dashboard') then
    lblStatus.Caption := '返回失败：没有注册名为 Dashboard 的窗体';
end;

{ 跨插件导航与仪表盘、报表两页一致：另两个插件 + 返回首页。
  独立 exe 形态下本进程只有 Notes，目标窗体不在本进程，
  由 ini 的 page.<注册名>=<URL> 回退成整页跳转。 }
procedure TNotesForm.btnOpenReportsClick(Sender: TObject);
begin
  if not TLWApp.OpenForm('Reports') then
    lblStatus.Caption := '打开失败：未登记 page.Reports';
end;

procedure TNotesForm.btnHomeClick(Sender: TObject);
begin
  if not TLWApp.OpenForm('Host') then
    lblStatus.Caption := '打开失败：未登记 page.Host';
end;

procedure TNotesAjax.Export(A: TLWAjaxContext);
var
  i: Integer;
  items: string;
  n: Integer;
begin
  n := 0;
  if GNotes <> nil then
    n := GNotes.Count;
  items := '';
  for i := 0 to n - 1 do
  begin
    if items <> '' then
      items := items + ',';
    items := items + '"' + JsonEscape(GNotes[i]) + '"';
  end;
  A.Json('{"ok":true,"module":"notes","count":' + IntToStr(n) +
    ',"items":[' + items + ']}');
end;

procedure RegisterModule;
begin
  TLWApp.RegisterForm('Notes', TNotesForm);
  if GNotes = nil then
    GNotes := TStringList.Create;
  if GAjax = nil then
    GAjax := TNotesAjax.Create;
  TLWApp.AddAjax('notes_export', @GAjax.Export);
end;

end.
