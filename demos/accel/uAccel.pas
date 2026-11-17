{
  lazarusWeb :: uAccel
  ------------------------------------------------------------------
  LCL 加速键（Caption 里的 &）浏览器端渲染审计。

  LCL 的规则是按控件分家的，这个窗体把每一类都摆一个出来：

    解析 & 的（ShowAccelChar 默认 True）
      TLabel          '用户名(&U)：'          -> 下划线 U
      TStaticText     '状态(&S)：'            -> 下划线 S
      TPanel          '面板(&Q)'              -> 下划线 Q（要显式 ShowAccelChar=True）
      TGroupBox       '分组(&G)'              -> 下划线 G
      TButton         '确定(&O)'              -> 下划线 O，Alt+O 触发
      TBitBtn         '取消(&C)'
      TCheckBox       '启用(&E)'
      TRadioButton    '甲(&A)'
      TRadioGroup     标题 + 各选项（内部是真 TRadioButton）
      TCheckGroup     标题 + 各选项（内部是真 TCheckBox）
      TPageControl    TabSheet.Caption
      TTabControl     Tabs[i]
      TMenuItem       主菜单与各级子项

    不解析 & 的（LCL 也是原样显示，别"顺手"改掉）
      TListBox / TComboBox / TCheckListBox 的 Items（字符串列表，不是 Caption）
      TStatusBar.Panels[i].Text
      TForm.Caption（窗口标题）
      TPanel 的 Caption —— TCustomPanel.ShowAccelChar 的默认值是 **False**
        （extctrls.pp，跟 TLabel 的 True 不一样），所以面板标题里的 & 在
        LCL 里就是字面量。这个窗体两个面板并排：左边不设（原样），
        右边显式 ShowAccelChar=True（解析），服务端下发的 acc 字段就这么用的。
      其它把 ShowAccelChar 显式关掉的控件

  两个转义也要对：'A && B' 显示成 'A & B'，'C & D' 里的孤立 & 原样保留。
}
unit uAccel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus,
  Buttons, CheckLst, lwform;

type
  TAccelForm = class(TLWForm)
    btnOk: TButton;
    lblLog: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure EchoClick(Sender: TObject);
  end;

implementation

{$R *.lfm}

function NewLabel(AOwner: TComponent; AParent: TWinControl;
  AX, AY, AW: Integer; const ACap: string): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AParent;
  Result.Left := AX;
  Result.Top := AY;
  Result.Width := AW;
  Result.Height := 20;
  Result.AutoSize := False;
  Result.Caption := ACap;
end;

procedure TAccelForm.EchoClick(Sender: TObject);
begin
  if Sender is TControl then
    lblLog.Caption := '点击：' + TControl(Sender).Name + ' / ' + TControl(Sender).Caption;
end;

procedure TAccelForm.FormCreate(Sender: TObject);

  function MakeButton(AX, AY: Integer; const ACap: string): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Self;
    Result.Left := AX;
    Result.Top := AY;
    Result.Width := 150;
    Result.Height := 32;
    Result.Caption := ACap;
    Result.OnClick := @EchoClick;
  end;

var
  st: TStaticText;
  pnl: TPanel;
  gb: TGroupBox;
  chk: TCheckBox;
  rb: TRadioButton;
  bb: TBitBtn;
  rg: TRadioGroup;
  cg: TCheckGroup;
  clb: TCheckListBox;
  cb: TComboBox;
  lb: TListBox;
  pc: TPageControl;
  ts: TTabSheet;
  tc: TTabControl;
  mm: TMainMenu;
  mi, sub: TMenuItem;
  sb: TStatusBar;
begin
  Caption := 'lazarusWeb · 加速键审计（&Caption）';
  ClientWidth := 780;
  ClientHeight := 640;

  { ---- 标签类 ---- }
  NewLabel(Self, Self, 16, 12, 300, 'A 用户名(&U)：');
  NewLabel(Self, Self, 16, 36, 300, 'B 字面 & 号（ShowAccelChar=False）').ShowAccelChar := False;
  NewLabel(Self, Self, 16, 60, 300, 'C 转义 && 显示成 &');

  st := TStaticText.Create(Self);
  st.Parent := Self;
  st.Left := 16; st.Top := 84; st.Width := 300; st.Height := 24;
  st.BorderStyle := sbsSingle;
  st.Caption := 'D 状态(&S)：就绪';

  { ---- 容器类 ---- }
  { TPanel：ShowAccelChar 默认 False -> & 原样；显式 True 才会解析 }
  pnl := TPanel.Create(Self);
  pnl.Parent := Self;
  pnl.Left := 16; pnl.Top := 116; pnl.Width := 145; pnl.Height := 44;
  pnl.Caption := 'E 面板(&P)';

  pnl := TPanel.Create(Self);
  pnl.Parent := Self;
  pnl.Left := 171; pnl.Top := 116; pnl.Width := 145; pnl.Height := 44;
  pnl.ShowAccelChar := True;
  pnl.Caption := 'I 面板(&Q)';

  gb := TGroupBox.Create(Self);
  gb.Parent := Self;
  gb.Left := 16; gb.Top := 168; gb.Width := 300; gb.Height := 92;
  gb.Caption := 'F 分组(&G)';

  chk := TCheckBox.Create(Self);
  chk.Parent := gb;
  chk.Left := 16; chk.Top := 22; chk.Width := 200; chk.Height := 22;
  chk.Caption := '启用(&E)';
  chk.OnClick := @EchoClick;

  rb := TRadioButton.Create(Self);
  rb.Parent := gb;
  rb.Left := 16; rb.Top := 50; rb.Width := 200; rb.Height := 22;
  rb.Caption := '甲(&A)';
  rb.OnClick := @EchoClick;

  { ---- 按钮类 ---- }
  btnOk := MakeButton(340, 12, '确定(&O)');
  bb := TBitBtn.Create(Self);
  bb.Parent := Self;
  bb.Left := 340; bb.Top := 52; bb.Width := 150; bb.Height := 32;
  bb.Caption := '取消(&C)';
  bb.OnClick := @EchoClick;

  { ---- 组（标题与选项都是 Caption 语义） ---- }
  rg := TRadioGroup.Create(Self);
  rg.Parent := Self;
  rg.Left := 340; rg.Top := 96; rg.Width := 200; rg.Height := 84;
  rg.Caption := 'G 颜色(&C)';
  rg.Items.Add('红(&R)');
  rg.Items.Add('绿(&G)');
  rg.ItemIndex := 0;
  rg.OnClick := @EchoClick;

  cg := TCheckGroup.Create(Self);
  cg.Parent := Self;
  cg.Left := 340; cg.Top := 188; cg.Width := 200; cg.Height := 72;
  cg.Caption := 'H 语言(&L)';
  cg.Items.Add('Pascal(&P)');
  cg.Items.Add('C(&C)');

  { ---- 字符串列表：LCL 不解析 & ---- }
  clb := TCheckListBox.Create(Self);
  clb.Parent := Self;
  clb.Left := 16; clb.Top := 276; clb.Width := 200; clb.Height := 76;
  clb.Items.Add('X & Y');
  clb.Items.Add('Z && W');

  cb := TComboBox.Create(Self);
  cb.Parent := Self;
  cb.Left := 232; cb.Top := 276; cb.Width := 180; cb.Height := 26;
  cb.Items.Add('A & B');
  cb.Items.Add('C && D');
  cb.ItemIndex := 0;

  lb := TListBox.Create(Self);
  lb.Parent := Self;
  lb.Left := 16; lb.Top := 364; lb.Width := 200; lb.Height := 68;
  lb.Items.Add('L1 & 原样');
  lb.Items.Add('L2 && 两个');

  { ---- 页签 ---- }
  pc := TPageControl.Create(Self);
  pc.Parent := Self;
  pc.Left := 232; pc.Top := 364; pc.Width := 260; pc.Height := 120;
  ts := TTabSheet.Create(Self);
  ts.PageControl := pc;
  ts.Caption := '页一(&1)';
  NewLabel(Self, ts, 12, 12, 180, '页一内容（无 &）');
  ts := TTabSheet.Create(Self);
  ts.PageControl := pc;
  ts.Caption := '页二(&2)';

  tc := TTabControl.Create(Self);
  tc.Parent := Self;
  tc.Left := 508; tc.Top := 364; tc.Width := 240; tc.Height := 120;
  tc.Tabs.Add('标签一(&T)');
  tc.Tabs.Add('标签二(&U)');

  { ---- 主菜单 ---- }
  mm := TMainMenu.Create(Self);
  mi := TMenuItem.Create(mm);
  mi.Caption := '文件(&F)';
  mm.Items.Add(mi);
  sub := TMenuItem.Create(mm);
  sub.Caption := '打开(&O)';
  sub.OnClick := @EchoClick;
  mi.Add(sub);
  sub := TMenuItem.Create(mm);
  sub.Caption := '另存为(&A)';
  sub.OnClick := @EchoClick;
  mi.Add(sub);
  sub := TMenuItem.Create(mm);
  sub.Caption := 'A && B';
  sub.OnClick := @EchoClick;
  mi.Add(sub);
  sub := TMenuItem.Create(mm);
  sub.Caption := '-';
  mi.Add(sub);
  sub := TMenuItem.Create(mm);
  sub.Caption := '退出(&X)';
  mi.Add(sub);
  Menu := mm;

  { ---- 状态栏：Text 不是 Caption，不解析 ---- }
  sb := TStatusBar.Create(Self);
  sb.Parent := Self;
  sb.SimplePanel := False;
  while sb.Panels.Count < 2 do
    sb.Panels.Add;
  sb.Panels[0].Width := 260;
  sb.Panels[0].Text := '状态栏 & 原样';
  sb.Panels[1].Text := '第二格';

  lblLog := NewLabel(Self, Self, 16, 500, 720, '（等待点击）');
end;

end.
