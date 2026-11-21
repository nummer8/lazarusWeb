{
  lazarusWeb :: TreeView / VirtualTreeView 数据感知组合演示
  ------------------------------------------------------------------
  一个窗体、两个页签、两棵真实 LCL 树，数据都来自 exe 同目录的
  treeview_demo.db（首次运行自动建表并灌示例数据）：

    · TreeView 页签：TLWDBTreeView（继承 TTreeView），绑定 tv_nodes 表
    · VirtualTreeView 页签：TLWDBVirtualTreeView（继承 VirtualTreeView），
      绑定 vst_nodes 表

  两棵树都暴露 DataSource / KeyField / ParentField / TextField：
  数据集 Post / Delete / Reopen 后由 DataLink 自动重建节点。
  页签上的"新增 / 删除 / 重载"按钮用于演示数据集变化会自动反映到树。

  工程定义了 LW_VIRTUALTREEVIEW，lwwriter / lwdispatch 会在编译时
  加入 VirtualTreeView 支持；其它 demo 不受影响。

  构建注意：VirtualTreeView 初始化会加载自带位图资源，nogui widgetset
  下 TIntfImage.LoadFromBitmap 会失败。demo 目录里的 laz.virtualtrees.pas
  是为 nogui 屏蔽这段位图加载的局部副本；用 nogui 构建即可：
    lazbuild -B --ws=nogui treedemo.lpi
}
unit uTreeMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls,
  DB, sqldb, sqlite3conn, lwform, uDBTree;

type
  TTreeDemoForm = class(TLWForm)
    pcMain: TPageControl;
    tsTree: TTabSheet;
    tsVirtual: TTabSheet;
    tsVstMulti: TTabSheet;
    lblTreeTip: TLabel;
    btnTreeReload: TButton;
    btnTreeAdd: TButton;
    btnTreeDelete: TButton;
    tvDb: TLWDBTreeView;
    mmoTv: TLabel;
    lblVstTip: TLabel;
    btnVstReload: TButton;
    btnVstAdd: TButton;
    btnVstDelete: TButton;
    mmoVst: TLabel;
    btnVstMultiReload: TButton;
    lblVstMultiDetail: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure btnTreeReloadClick(Sender: TObject);
    procedure btnTreeAddClick(Sender: TObject);
    procedure btnTreeDeleteClick(Sender: TObject);
    procedure btnVstReloadClick(Sender: TObject);
    procedure btnVstAddClick(Sender: TObject);
    procedure btnVstDeleteClick(Sender: TObject);
    procedure tvDbClick(Sender: TObject);
    procedure vstDbClick(Sender: TObject);
    procedure vstMultiClick(Sender: TObject);
    procedure btnVstMultiReloadClick(Sender: TObject);
  private
    FConn: TSQLite3Connection;
    FTrans: TSQLTransaction;
    FtQry: TSQLQuery;
    FtDs: TDataSource;
    FvQry: TSQLQuery;
    FvDs: TDataSource;
    FVst: TLWDBVirtualTreeView;
    FVstMulti: TLWDBVirtualTreeView;
    procedure SetupData;
    procedure SetupDatasets;
    procedure ReloadData;
    procedure AddNode(const ATable: string; AQuery: TSQLQuery);
    procedure DeleteNode(const ATable: string; AQuery: TSQLQuery; const AId: string);
    procedure ShowTreeInfo;
    procedure ShowVstInfo;
  public
    destructor Destroy; override;
  end;

const
  TV_SQL = 'SELECT id, parent_id, name, note FROM tv_nodes ORDER BY id';
  VST_SQL = 'SELECT id, parent_id, name, note FROM vst_nodes ORDER BY id';

implementation

{$R *.lfm}

destructor TTreeDemoForm.Destroy;
begin
  if FConn <> nil then FConn.Close;
  inherited Destroy;
end;

procedure TTreeDemoForm.FormCreate(Sender: TObject);
begin
  SetupData;
  SetupDatasets;

  FVst := TLWDBVirtualTreeView.Create(Self);
  FVst.Parent := tsVirtual;
  FVst.Left := 8;
  FVst.Top := 40;
  FVst.Width := 460;
  FVst.Height := 520;
  FVst.Header.Columns.Add.Text := '名称';
  FVst.Header.Columns[0].Width := 420;
  FVst.KeyField := 'id';
  FVst.ParentField := 'parent_id';
  FVst.TextField := 'name';
  FVst.DataSource := FvDs;
  FVst.OnClick := @vstDbClick;

  { 第三页：同一 vst_nodes 数据的多列 VirtualTreeView。
    列的顺序与 TextFields 一一对应：名称 / ID / 备注。 }
  FVstMulti := TLWDBVirtualTreeView.Create(Self);
  FVstMulti.Parent := tsVstMulti;
  FVstMulti.Left := 8;
  FVstMulti.Top := 40;
  FVstMulti.Width := 940;
  FVstMulti.Height := 430;
  FVstMulti.Header.Columns.Add.Text := '名称';
  FVstMulti.Header.Columns[0].Width := 400;
  FVstMulti.Header.Columns.Add.Text := 'ID';
  FVstMulti.Header.Columns[1].Width := 100;
  FVstMulti.Header.Columns.Add.Text := '备注';
  FVstMulti.Header.Columns[2].Width := 400;
  FVstMulti.KeyField := 'id';
  FVstMulti.ParentField := 'parent_id';
  FVstMulti.TextFields := 'name;id;note';
  FVstMulti.DataSource := FvDs;
  FVstMulti.OnClick := @vstMultiClick;

  tvDb.KeyField := 'id';
  tvDb.ParentField := 'parent_id';
  tvDb.TextField := 'name';
  tvDb.DataSource := FtDs;

  ReloadData;
  lblTreeTip.Caption := 'TLWDBTreeView ← tv_nodes（电子产品数据）';
  lblVstTip.Caption := 'TLWDBVirtualTreeView ← vst_nodes（部门人员数据）';
end;

procedure TTreeDemoForm.SetupData;
var
  n: Integer;

  procedure Seed(const ATable: string; const ARows: array of string);
  var
    i: Integer;
  begin
    for i := 0 to High(ARows) do
      FConn.ExecuteDirect('INSERT INTO ' + ATable +
        '(id,parent_id,name,note) VALUES(' + ARows[i] + ')');
  end;

begin
  FTrans := TSQLTransaction.Create(Self);
  FConn := TSQLite3Connection.Create(Self);
  FConn.DatabaseName := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'treeview_demo.db';
  FConn.Transaction := FTrans;
  FTrans.Database := FConn;
  FConn.Params.Add('journal_mode=WAL');
  FConn.Open;
  FConn.ExecuteDirect('PRAGMA busy_timeout=10000');

  { 两张独立表：TreeView 用电子产品，VirtualTreeView 用部门人员。
    字符串列一律 VARCHAR(n)，sqlite3conn 会把 TEXT 映射成 ftMemo。 }
  FConn.ExecuteDirect('CREATE TABLE IF NOT EXISTS tv_nodes(' +
    'id INTEGER PRIMARY KEY, parent_id INTEGER, name VARCHAR(80), note VARCHAR(120))');
  FConn.ExecuteDirect('CREATE TABLE IF NOT EXISTS vst_nodes(' +
    'id INTEGER PRIMARY KEY, parent_id INTEGER, name VARCHAR(80), note VARCHAR(120))');
  FTrans.CommitRetaining;

  with TSQLQuery.Create(nil) do
    try
      Database := FConn;
      Transaction := FTrans;
      SQL.Text := 'SELECT COUNT(*) AS n FROM tv_nodes';
      Open;
      n := FieldByName('n').AsInteger;
      Close;
    finally
      Free;
    end;
  if n > 0 then Exit;

  Seed('tv_nodes', [
    '1,NULL,' + QuotedStr('电子配件') + ',' + QuotedStr('根节点'),
    '2,1,' + QuotedStr('USB-C 数据线 ¥29') + ',' + QuotedStr('Type-C 接口 / 1m'),
    '3,1,' + QuotedStr('无线鼠标 ¥89') + ',' + QuotedStr('2.4G 无线'),
    '4,1,' + QuotedStr('机械键盘 ¥399') + ',' + QuotedStr('87 键 / 青轴'),
    '5,NULL,' + QuotedStr('办公用品') + ',' + QuotedStr('根节点'),
    '6,5,' + QuotedStr('A4 复印纸 ¥25') + ',' + QuotedStr('500 张 / 包'),
    '7,5,' + QuotedStr('中性笔 ¥5') + ',' + QuotedStr('0.5mm 黑色')]);

  Seed('vst_nodes', [
    '101,NULL,' + QuotedStr('技术部') + ',' + QuotedStr('根节点'),
    '102,101,' + QuotedStr('开发工程师') + ',' + QuotedStr('后端 / Pascal'),
    '103,101,' + QuotedStr('测试工程师') + ',' + QuotedStr('自动化测试'),
    '104,NULL,' + QuotedStr('市场部') + ',' + QuotedStr('根节点'),
    '105,104,' + QuotedStr('销售经理') + ',' + QuotedStr('华东区'),
    '106,104,' + QuotedStr('市场专员') + ',' + QuotedStr('品牌推广')]);
  FTrans.CommitRetaining;
end;

procedure TTreeDemoForm.SetupDatasets;
begin
  FtQry := TSQLQuery.Create(Self);
  FtQry.Database := FConn;
  FtQry.Transaction := FTrans;
  FtQry.SQL.Text := TV_SQL;
  FtQry.Options := FtQry.Options + [sqoAutoApplyUpdates];
  FtDs := TDataSource.Create(Self);
  FtDs.DataSet := FtQry;

  FvQry := TSQLQuery.Create(Self);
  FvQry.Database := FConn;
  FvQry.Transaction := FTrans;
  FvQry.SQL.Text := VST_SQL;
  FvQry.Options := FvQry.Options + [sqoAutoApplyUpdates];
  FvDs := TDataSource.Create(Self);
  FvDs.DataSet := FvQry;
end;

procedure TTreeDemoForm.ReloadData;
begin
  FtQry.Close;
  FtQry.Open;
  FvQry.Close;
  FvQry.Open;
  { DataLink 会在数据集状态变化时收到通知；这里再显式刷一次，
    保证首次打开时两棵树一定拿到数据 }
  tvDb.RefreshTree;
  if FVst <> nil then
    FVst.RefreshTree;
  if FVstMulti <> nil then
    FVstMulti.RefreshTree;
  mmoTv.Caption := 'tv_nodes：点节点查看记录；新增/删除后树会自动刷新。';
  mmoVst.Caption := 'vst_nodes：点节点查看记录；新增/删除后树会自动刷新。';
  lblVstMultiDetail.Caption := '多列视图：名称 / ID / 备注，点节点查看该行完整信息。';
end;

procedure TTreeDemoForm.AddNode(const ATable: string; AQuery: TSQLQuery);
var
  nid, pid: Integer;
  key, nodeName: string;
begin
  { 用数据集 Append/Post 新增，DataLink 收到 deUpdateRecord 后自动重建树。
    不直接 ExecuteDirect，否则绑定数据集感知不到变化。 }
  pid := 0;
  if AQuery = FtQry then
  begin
    key := tvDb.NodeKey(tvDb.Selected);
    if key <> '' then pid := StrToIntDef(key, 0);
    nodeName := '电子产品 ';
  end
  else
  begin
    if FVst <> nil then
    begin
      key := FVst.SelectedKey;
      if key <> '' then pid := StrToIntDef(key, 0);
    end;
    nodeName := '部门成员 ';
  end;

  with TSQLQuery.Create(nil) do
    try
      Database := FConn;
      Transaction := FTrans;
      SQL.Text := 'SELECT COALESCE(MAX(id),0)+1 AS nid FROM ' + ATable;
      Open;
      nid := FieldByName('nid').AsInteger;
      Close;
    finally
      Free;
    end;

  AQuery.Append;
  AQuery.FieldByName('id').AsInteger := nid;
  if pid > 0 then
    AQuery.FieldByName('parent_id').AsInteger := pid
  else
    AQuery.FieldByName('parent_id').Clear;
  AQuery.FieldByName('name').AsString := nodeName + IntToStr(nid);
  AQuery.FieldByName('note').AsString := '由新增按钮写入';
  AQuery.Post;
  FTrans.CommitRetaining;
  { sqoAutoApplyUpdates + CommitRetaining 下 DataLink 的 deUpdateRecord
    不一定到达；这里显式重建一次，外部代码直接 Post 时仍由 DataLink 自动刷 }
  AQuery.Refresh;
  if AQuery = FtQry then
    tvDb.RefreshTree
  else
  begin
    if FVst <> nil then
      FVst.RefreshTree;
    if FVstMulti <> nil then
      FVstMulti.RefreshTree;
  end;
end;

procedure TTreeDemoForm.DeleteNode(const ATable: string; AQuery: TSQLQuery;
  const AId: string);
begin
  if AId = '' then Exit;
  { DataSet.Delete 触发 DataLink -> 树自动刷新 }
  if AQuery.Locate('id', StrToInt64Def(AId, 0), []) then
  begin
    AQuery.Delete;
    FTrans.CommitRetaining;
    AQuery.Refresh;
    if AQuery = FtQry then
      tvDb.RefreshTree
    else
    begin
      if FVst <> nil then
        FVst.RefreshTree;
      if FVstMulti <> nil then
        FVstMulti.RefreshTree;
    end;
  end;
end;

procedure TTreeDemoForm.ShowTreeInfo;
var
  key, note, nodeName: string;
  q: TSQLQuery;
begin
  key := tvDb.NodeKey(tvDb.Selected);
  if key = '' then Exit;
  nodeName := tvDb.Selected.Text;
  { 用独立查询读备注：不要 Locate 绑定数据集，否则 DataLink 会在事件处理中
    重入刷新、把 tvDb.Selected 清掉，导致访问冲突 }
  q := TSQLQuery.Create(nil);
  try
    q.Database := FConn;
    q.Transaction := FTrans;
    q.SQL.Text := 'SELECT note FROM tv_nodes WHERE id=:id';
    q.ParamByName('id').AsString := key;
    q.Open;
    if q.IsEmpty then
      note := '（未找到）'
    else
      note := q.FieldByName('note').AsString;
    q.Close;
  finally
    q.Free;
  end;
  { 详情用 TLabel.Caption 显示：nogui 下数据集刷新可能重建 TMemo 的
    Lines 对象，写完马上变空；Caption 存在 LCL 对象自身，稳定可靠。 }
  mmoTv.Caption := '控件：TLWDBTreeView（DataSource → tv_nodes） ｜ id：' + key +
    ' ｜ 名称：' + nodeName + ' ｜ 备注：' + note;
end;

procedure TTreeDemoForm.ShowVstInfo;
var
  key: string;
begin
  if FVst = nil then Exit;
  key := FVst.SelectedKey;
  if key = '' then Exit;
  mmoVst.Caption := '控件：TLWDBVirtualTreeView（DataSource → vst_nodes） ｜ id：' + key +
    ' ｜ 名称：' + FVst.SelectedText + ' ｜ 备注：节点文本由 OnGetText 从数据集按需提供';
end;

procedure TTreeDemoForm.tvDbClick(Sender: TObject);
begin
  ShowTreeInfo;
end;

procedure TTreeDemoForm.vstDbClick(Sender: TObject);
begin
  ShowVstInfo;
end;

procedure TTreeDemoForm.vstMultiClick(Sender: TObject);
begin
  if FVstMulti = nil then Exit;
  lblVstMultiDetail.Caption := '选中行 ｜ 名称：' + FVstMulti.SelectedCell(0) +
    ' ｜ ID：' + FVstMulti.SelectedCell(1) +
    ' ｜ 备注：' + FVstMulti.SelectedCell(2);
end;

procedure TTreeDemoForm.btnVstMultiReloadClick(Sender: TObject);
begin
  ReloadData;
end;

procedure TTreeDemoForm.btnTreeReloadClick(Sender: TObject);
begin
  ReloadData;
end;

procedure TTreeDemoForm.btnVstReloadClick(Sender: TObject);
begin
  ReloadData;
end;

procedure TTreeDemoForm.btnTreeAddClick(Sender: TObject);
begin
  AddNode('tv_nodes', FtQry);
end;

procedure TTreeDemoForm.btnTreeDeleteClick(Sender: TObject);
begin
  DeleteNode('tv_nodes', FtQry, tvDb.NodeKey(tvDb.Selected));
end;

procedure TTreeDemoForm.btnVstAddClick(Sender: TObject);
begin
  AddNode('vst_nodes', FvQry);
end;

procedure TTreeDemoForm.btnVstDeleteClick(Sender: TObject);
begin
  if FVst = nil then Exit;
  DeleteNode('vst_nodes', FvQry, FVst.SelectedKey);
end;

end.
