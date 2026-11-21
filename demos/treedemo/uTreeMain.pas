{
  lazarusWeb :: TreeView / VirtualTreeView 数据感知 + 增删改演示
  ------------------------------------------------------------------
  一个窗体、三个页签，三棵树都来自 exe 同目录的 treeview_demo.db
  （首次运行自动建表并灌示例数据）：

    · TreeView 页签        TLWDBTreeView         ← tv_nodes
    · VirtualTreeView 页签 TLWDBVirtualTreeView  ← vst_nodes（单列）
    · 多列页签             TLWDBVirtualTreeView  ← vst_nodes（名称/ID/备注）

  两棵树都暴露 DataSource / KeyField / ParentField / TextField，
  数据集 Post / Delete / Refresh 之后由 DataLink 自动重建节点，
  并按主键恢复选中（RefreshTree 内部记住旧 key）。

  三个页签的 CRUD 操作完全一致：

    新增子节点 → 浏览器输入框问名称，新行挂到“当前选中行”下面，
                 建好自动选中它，可以接着往下加
    改名…      → 浏览器输入框（预填当前名称）
    改备注…    → 浏览器输入框（预填当前备注）
    删除选中   → 删掉该行，并清掉它留下的孤儿子孙

  为什么改/增用浏览器输入框而不是编辑框：
    nogui 下 TEdit 的文本存在 widget 里，非活动 TTabSheet 上的 TEdit
    （服务端 Handle 没建）跨请求存不住 —— 点“保存”时读到的永远是空串，
    会把库里的名字写空。InputQuery 在 lwdlg 里被接到浏览器，值随对话框
    答复直接回传到事件里，不经过控件的 Text，稳。

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
  DB, sqldb, sqlite3conn, Dialogs, lwform, lwdlg, lwdbtree, lwdbvst;

type

  { TTreeDemoForm }

  TTreeDemoForm = class(TLWForm)
    FVst: TLWDBVirtualTreeView;
    FVstMulti: TLWDBVirtualTreeView;
    pcMain: TPageControl;
    tsTree: TTabSheet;
    tsVirtual: TTabSheet;
    tsVstMulti: TTabSheet;
    { 第 1 页 }
    lblTreeTip: TLabel;
    btnTreeAdd: TButton;
    btnTreeDelete: TButton;
    btnTreeReload: TButton;
    lblTvCur: TLabel;
    btnTreeRename: TButton;
    btnTreeNote: TButton;
    tvDb: TLWDBTreeView;
    mmoTv: TLabel;
    { 第 2 页 }
    lblVstTip: TLabel;
    btnVstAdd: TButton;
    btnVstDelete: TButton;
    btnVstReload: TButton;
    lblVstCur: TLabel;
    btnVstRename: TButton;
    btnVstNote: TButton;
    mmoVst: TLabel;
    { 第 3 页 }
    lblVstMultiTip: TLabel;
    btnVstMultiAdd: TButton;
    btnVstMultiDelete: TButton;
    btnVstMultiReload: TButton;
    lblMultiCur: TLabel;
    btnMultiRename: TButton;
    btnMultiNote: TButton;
    lblVstMultiDetail: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure tvDbClick(Sender: TObject);
    procedure vstDbClick(Sender: TObject);
    procedure vstMultiClick(Sender: TObject);
    procedure btnTreeReloadClick(Sender: TObject);
    procedure btnVstReloadClick(Sender: TObject);
    procedure btnVstMultiReloadClick(Sender: TObject);
    procedure btnTreeAddClick(Sender: TObject);
    procedure btnVstAddClick(Sender: TObject);
    procedure btnVstMultiAddClick(Sender: TObject);
    procedure btnTreeDeleteClick(Sender: TObject);
    procedure btnVstDeleteClick(Sender: TObject);
    procedure btnVstMultiDeleteClick(Sender: TObject);
    procedure btnTreeRenameClick(Sender: TObject);
    procedure btnVstRenameClick(Sender: TObject);
    procedure btnMultiRenameClick(Sender: TObject);
    procedure btnTreeNoteClick(Sender: TObject);
    procedure btnVstNoteClick(Sender: TObject);
    procedure btnMultiNoteClick(Sender: TObject);
  private
    FConn: TSQLite3Connection;
    FTrans: TSQLTransaction;
    FtQry: TSQLQuery;
    FtDs: TDataSource;
    FvQry: TSQLQuery;
    FvDs: TDataSource;
    //FVst: TLWDBVirtualTreeView;
    //FVstMulti: TLWDBVirtualTreeView;
    procedure SetupData;
    procedure SetupDatasets;
    procedure ReloadData;
    { 浏览器输入框：取消返回 False，值放在 AValue（已 Trim）。
      注意参数必须是 var 而不是 out —— out 会让 FPC 在入口处终结化
      AValue，调用方传进来的默认值先被清空，对话框就变成空白预填。 }
    function AskText(const ACaption, APrompt, ADefault: string;
      var AValue: string): Boolean;
    procedure AddNode(const ATable: string; AQuery: TSQLQuery;
      const AParentKey, AName: string);
    procedure DeleteNode(const ATable: string; AQuery: TSQLQuery; const AId: string);
    procedure CleanOrphans(const ATable: string);
    { 只更新一列（'name' 或 'note'）：独立查询写库，再让数据集与树刷新 }
    procedure UpdateField(const ATable, AId, AField, AValue: string);
    procedure RefreshTable(const ATable: string);
    function FetchNote(const ATable, AId: string): string;
    procedure ShowTreeInfo;
    procedure ShowVstInfo;
    procedure ShowMultiInfo;
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

  //FVst := TLWDBVirtualTreeView.Create(Self);
  //FVst.Parent := tsVirtual;
  //FVst.Left := 8;
  //FVst.Top := 110;
  //FVst.Width := 460;
  //FVst.Height := 480;
  FVst.Header.Columns.Add.Text := '名称';
  FVst.Header.Columns[0].Width := 420;
  FVst.KeyField := 'id';
  FVst.ParentField := 'parent_id';
  FVst.TextField := 'name';
  FVst.AutoExpand := True;
  FVst.DataSource := FvDs;
  FVst.OnClick := @vstDbClick;

  { 第三页：同一份 vst_nodes 数据的多列 VirtualTreeView。
    列的顺序与 TextFields 一一对应：名称 / ID / 备注。 }
  //FVstMulti := TLWDBVirtualTreeView.Create(Self);
  //FVstMulti.Parent := tsVstMulti;
  //FVstMulti.Left := 8;
  //FVstMulti.Top := 110;
  //FVstMulti.Width := 940;
  //FVstMulti.Height := 330;
  FVstMulti.Header.Columns.Add.Text := '名称';
  FVstMulti.Header.Columns[0].Width := 400;
  FVstMulti.Header.Columns.Add.Text := 'ID';
  FVstMulti.Header.Columns[1].Width := 100;
  FVstMulti.Header.Columns.Add.Text := '备注';
  FVstMulti.Header.Columns[2].Width := 400;
  FVstMulti.KeyField := 'id';
  FVstMulti.ParentField := 'parent_id';
  FVstMulti.TextFields := 'name;id;note';
  FVstMulti.AutoExpand := True;
  FVstMulti.DataSource := FvDs;
  FVstMulti.OnClick := @vstMultiClick;

  tvDb.KeyField := 'id';
  tvDb.ParentField := 'parent_id';
  tvDb.TextField := 'name';
  tvDb.DataSource := FtDs;

  ReloadData;
  lblTreeTip.Caption := 'TLWDBTreeView ← tv_nodes（电子产品数据）';
  lblVstTip.Caption := 'TLWDBVirtualTreeView ← vst_nodes（部门人员数据）';
  lblVstMultiTip.Caption :=
    'TLWDBVirtualTreeView ← vst_nodes（名称 / ID / 备注）：选中一行后可改、可增、可删';
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
  ShowTreeInfo;
  ShowVstInfo;
  ShowMultiInfo;
  if lblTvCur.Caption = '当前行：（未选中）' then
    lblTvCur.Caption := '当前行：（未选中）· 点左边的树选一行';
end;

{ 浏览器输入框：lwdlg 把 LCL 的 InputQuery 接到前端，
  值随对话框答复直接回到这里，不经过任何控件的 Text。 }
function TTreeDemoForm.AskText(const ACaption, APrompt, ADefault: string;
  var AValue: string): Boolean;
begin
  AValue := ADefault;
  Result := InputQuery(ACaption, APrompt, AValue);
  if Result then
    AValue := Trim(AValue);
end;

procedure TTreeDemoForm.AddNode(const ATable: string; AQuery: TSQLQuery;
  const AParentKey, AName: string);
var
  nid, pid: Integer;
  nodeName: string;
begin
  { 用数据集 Append/Post 新增，DataLink 收到 deUpdateRecord 后自动重建树。
    不直接 ExecuteDirect，否则绑定数据集感知不到变化。
    AParentKey = 当前选中行的主键：有值就挂到该行下面，空值则作为根节点。 }
  pid := StrToIntDef(AParentKey, 0);

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

  nodeName := Trim(AName);
  if nodeName = '' then
  begin
    if AQuery = FtQry then
      nodeName := '电子产品 ' + IntToStr(nid)
    else
      nodeName := '部门成员 ' + IntToStr(nid);
  end;

  AQuery.Append;
  AQuery.FieldByName('id').AsInteger := nid;
  if pid > 0 then
    AQuery.FieldByName('parent_id').AsInteger := pid
  else
    AQuery.FieldByName('parent_id').Clear;
  AQuery.FieldByName('name').AsString := nodeName;
  AQuery.FieldByName('note').AsString := '由新增按钮写入';
  AQuery.Post;
  FTrans.CommitRetaining;
  { sqoAutoApplyUpdates + CommitRetaining 下 DataLink 的 deUpdateRecord
    不一定到达；这里显式重建一次，外部代码直接 Post 时仍由 DataLink 自动刷 }
  AQuery.Refresh;
  RefreshTable(ATable);
  { 新节点直接选中：用户可以立刻在它下面继续加，或者改/删，
    否则重建后选中态丢失，“新增”按钮看起来像没反应 }
  if AQuery = FtQry then
  begin
    tvDb.SelectKey(IntToStr(nid));
    ShowTreeInfo;
    mmoTv.Caption := mmoTv.Caption + ' ｜ 已新增 id=' + IntToStr(nid) +
      '（挂在 id=' + IntToStr(pid) + ' 下）';
  end
  else
  begin
    if FVst <> nil then
      FVst.SelectKey(IntToStr(nid));
    if FVstMulti <> nil then
      FVstMulti.SelectKey(IntToStr(nid));
    ShowVstInfo;
    ShowMultiInfo;
    mmoVst.Caption := '已新增 id=' + IntToStr(nid) + '（挂在 id=' + IntToStr(pid) + ' 下）';
    lblVstMultiDetail.Caption := mmoVst.Caption;
  end;
end;

{ 清掉 parent 已不存在的孤儿行（父节点被删后，它的整棵子树都成了孤儿）。
  一条 DELETE 只清一层（子查询按语句开始时的快照求值），所以循环到没有孤儿为止。 }
procedure TTreeDemoForm.CleanOrphans(const ATable: string);
var
  q: TSQLQuery;
  n, i: Integer;
begin
  q := TSQLQuery.Create(nil);
  try
    q.Database := FConn;
    q.Transaction := FTrans;
    q.SQL.Text := 'SELECT COUNT(*) AS n FROM ' + ATable +
      ' WHERE parent_id IS NOT NULL AND parent_id NOT IN (SELECT id FROM ' + ATable + ')';
    for i := 1 to 32 do
    begin
      q.Open;
      n := q.FieldByName('n').AsInteger;
      q.Close;
      if n = 0 then Break;
      FConn.ExecuteDirect('DELETE FROM ' + ATable +
        ' WHERE parent_id IS NOT NULL AND parent_id NOT IN (SELECT id FROM ' + ATable + ')');
      FTrans.CommitRetaining;
    end;
  finally
    q.Free;
  end;
end;

procedure TTreeDemoForm.DeleteNode(const ATable: string; AQuery: TSQLQuery;
  const AId: string);
begin
  if AId = '' then Exit;
  { 选中行用 DataSet.Delete（演示 DataLink 跟随数据集变化），
    随后把它留下的孤儿子孙一并清掉，不留看不见的残行 }
  if AQuery.Locate('id', StrToInt64Def(AId, 0), []) then
  begin
    AQuery.Delete;
    FTrans.CommitRetaining;
    CleanOrphans(ATable);
    AQuery.Refresh;
    RefreshTable(ATable);
  end;
end;

procedure TTreeDemoForm.UpdateField(const ATable, AId, AField, AValue: string);
var
  q: TSQLQuery;
begin
  if AId = '' then Exit;
  q := TSQLQuery.Create(nil);
  try
    q.Database := FConn;
    q.Transaction := FTrans;
    q.SQL.Text := 'UPDATE ' + ATable + ' SET ' + AField + '=:v WHERE id=:id';
    q.ParamByName('v').AsString := AValue;
    q.ParamByName('id').AsString := AId;
    q.ExecSQL;
    FTrans.CommitRetaining;
  finally
    q.Free;
  end;
  RefreshTable(ATable);
end;

{ 刷库 + 刷树：RefreshTree 内部按主键恢复选中，所以改完仍是同一行 }
procedure TTreeDemoForm.RefreshTable(const ATable: string);
begin
  if ATable = 'tv_nodes' then
  begin
    FtQry.Refresh;
    tvDb.RefreshTree;
    ShowTreeInfo;
  end
  else
  begin
    FvQry.Refresh;
    if FVst <> nil then
      FVst.RefreshTree;
    if FVstMulti <> nil then
      FVstMulti.RefreshTree;
    ShowVstInfo;
    ShowMultiInfo;
  end;
end;

{ 独立查询读备注：不要 Locate 绑定数据集，否则 DataLink 会在事件处理中
  重入刷新、把选中节点清掉 }
function TTreeDemoForm.FetchNote(const ATable, AId: string): string;
var
  q: TSQLQuery;
begin
  Result := '';
  if AId = '' then Exit;
  q := TSQLQuery.Create(nil);
  try
    q.Database := FConn;
    q.Transaction := FTrans;
    q.SQL.Text := 'SELECT note FROM ' + ATable + ' WHERE id=:id';
    q.ParamByName('id').AsString := AId;
    q.Open;
    if not q.IsEmpty then
      Result := q.FieldByName('note').AsString
    else
      Result := '（未找到）';
    q.Close;
  finally
    q.Free;
  end;
end;

procedure TTreeDemoForm.ShowTreeInfo;
var
  key, note, nodeName: string;
begin
  key := tvDb.NodeKey(tvDb.Selected);
  if key = '' then
  begin
    lblTvCur.Caption := '当前行：（未选中）· 点左边的树选一行';
    Exit;
  end;
  nodeName := tvDb.Selected.Text;
  note := FetchNote('tv_nodes', key);
  { 详情用 TLabel.Caption 显示：nogui 下数据集刷新可能重建 TMemo 的
    Lines 对象，写完马上变空；Caption 存在 LCL 对象自身，稳定可靠。 }
  lblTvCur.Caption := '当前行：id=' + key + ' ｜ 名称：' + nodeName +
    ' ｜ 备注：' + note;
  mmoTv.Caption := '控件：TLWDBTreeView（DataSource → tv_nodes）' + sLineBreak +
    'id：' + key + sLineBreak +
    '名称：' + nodeName + sLineBreak +
    '备注：' + note + sLineBreak + sLineBreak +
    '选中一行后：改名…/改备注… 会弹出浏览器输入框；' + sLineBreak +
    '新增子节点会挂到这一行下面并自动选中新行；' + sLineBreak +
    '删除选中会连同它的下级节点一起删掉。';
end;

procedure TTreeDemoForm.ShowVstInfo;
var
  key, note: string;
begin
  if FVst = nil then Exit;
  key := FVst.SelectedKey;
  if key = '' then
  begin
    lblVstCur.Caption := '当前行：（未选中）· 点左边的树选一行';
    Exit;
  end;
  note := FetchNote('vst_nodes', key);
  lblVstCur.Caption := '当前行：id=' + key + ' ｜ 名称：' + FVst.SelectedText +
    ' ｜ 备注：' + note;
  mmoVst.Caption := '控件：TLWDBVirtualTreeView（DataSource → vst_nodes）' + sLineBreak +
    'id：' + key + sLineBreak +
    '名称：' + FVst.SelectedText + sLineBreak +
    '备注：' + note + sLineBreak + sLineBreak +
    '选中一行后：改名…/改备注… 会弹出浏览器输入框；' + sLineBreak +
    '新增子节点会挂到这一行下面并自动选中新行；' + sLineBreak +
    '删除选中会连同它的下级节点一起删掉。';
end;

{ 多列页：第 0 列是名称、第 1 列是 ID、第 2 列是备注，直接取单元格，
  不再额外查库（库已被 Refresh 过，单元格就是最新值） }
procedure TTreeDemoForm.ShowMultiInfo;
var
  key, note: string;
begin
  if FVstMulti = nil then Exit;
  key := FVstMulti.SelectedKey;
  if key = '' then
  begin
    lblMultiCur.Caption := '当前行：（未选中）· 点上面的多列树选一行';
    Exit;
  end;
  note := FVstMulti.SelectedCell(2);
  lblMultiCur.Caption := '当前行：id=' + key + ' ｜ 名称：' + FVstMulti.SelectedCell(0) +
    ' ｜ 备注：' + note;
  lblVstMultiDetail.Caption := '控件：TLWDBVirtualTreeView（TextFields=name;id;note）' +
    sLineBreak +
    'id：' + key + sLineBreak +
    '名称：' + FVstMulti.SelectedCell(0) + sLineBreak +
    '备注：' + note + sLineBreak + sLineBreak +
    '选中一行后：改名…/改备注… 会弹出浏览器输入框；' + sLineBreak +
    '新增子节点会挂到这一行下面并自动选中新行；' + sLineBreak +
    '删除选中会连同它的下级节点一起删掉。';
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
  ShowMultiInfo;
end;

procedure TTreeDemoForm.btnTreeReloadClick(Sender: TObject);
begin
  ReloadData;
end;

procedure TTreeDemoForm.btnVstReloadClick(Sender: TObject);
begin
  ReloadData;
end;

procedure TTreeDemoForm.btnVstMultiReloadClick(Sender: TObject);
begin
  ReloadData;
end;

procedure TTreeDemoForm.btnTreeAddClick(Sender: TObject);
var
  key, vName: string;
begin
  key := tvDb.NodeKey(tvDb.Selected);
  vName := '新节点';
  if not AskText('新增子节点', '新节点名称（会挂到当前行下面）：', vName, vName) then
  begin
    mmoTv.Caption := '已取消新增。';
    Exit;
  end;
  AddNode('tv_nodes', FtQry, key, vName);
end;

procedure TTreeDemoForm.btnVstAddClick(Sender: TObject);
var
  key, vName: string;
begin
  if FVst = nil then Exit;
  key := FVst.SelectedKey;
  vName := '新节点';
  if not AskText('新增子节点', '新节点名称（会挂到当前行下面）：', vName, vName) then
  begin
    mmoVst.Caption := '已取消新增。';
    Exit;
  end;
  AddNode('vst_nodes', FvQry, key, vName);
end;

procedure TTreeDemoForm.btnVstMultiAddClick(Sender: TObject);
var
  key, vName: string;
begin
  if FVstMulti = nil then Exit;
  key := FVstMulti.SelectedKey;
  vName := '新节点';
  if not AskText('新增子节点', '新节点名称（会挂到当前行下面）：', vName, vName) then
  begin
    lblVstMultiDetail.Caption := '已取消新增。';
    Exit;
  end;
  AddNode('vst_nodes', FvQry, key, vName);
end;

procedure TTreeDemoForm.btnTreeDeleteClick(Sender: TObject);
var
  key: string;
begin
  key := tvDb.NodeKey(tvDb.Selected);
  if key = '' then
  begin
    mmoTv.Caption := '请先点选一行，再点“删除选中”。';
    Exit;
  end;
  DeleteNode('tv_nodes', FtQry, key);
  mmoTv.Caption := '已删除 id=' + key + '（连同它的下级节点）';
end;

procedure TTreeDemoForm.btnVstDeleteClick(Sender: TObject);
var
  key: string;
begin
  if FVst = nil then Exit;
  key := FVst.SelectedKey;
  if key = '' then
  begin
    mmoVst.Caption := '请先点选一行，再点“删除选中”。';
    Exit;
  end;
  DeleteNode('vst_nodes', FvQry, key);
  mmoVst.Caption := '已删除 id=' + key + '（连同它的下级节点）';
end;

procedure TTreeDemoForm.btnVstMultiDeleteClick(Sender: TObject);
var
  key: string;
begin
  if FVstMulti = nil then Exit;
  key := FVstMulti.SelectedKey;
  if key = '' then
  begin
    lblVstMultiDetail.Caption := '请先点选一行，再点“删除选中”。';
    Exit;
  end;
  DeleteNode('vst_nodes', FvQry, key);
  lblVstMultiDetail.Caption := '已删除 id=' + key + '（连同它的下级节点）';
end;

procedure TTreeDemoForm.btnTreeRenameClick(Sender: TObject);
var
  key, v: string;
begin
  key := tvDb.NodeKey(tvDb.Selected);
  if key = '' then
  begin
    mmoTv.Caption := '请先点选一行，再点“改名…”。';
    Exit;
  end;
  v := tvDb.Selected.Text;
  if not AskText('改名', 'id=' + key + ' 的新名称：', v, v) then
  begin
    mmoTv.Caption := '已取消改名。';
    Exit;
  end;
  if v = '' then
  begin
    mmoTv.Caption := '名称不能为空，未修改。';
    Exit;
  end;
  UpdateField('tv_nodes', key, 'name', v);
  tvDb.SelectKey(key);
  ShowTreeInfo;
  mmoTv.Caption := mmoTv.Caption + sLineBreak + sLineBreak + '已改名：id=' + key + ' → ' + v;
end;

procedure TTreeDemoForm.btnVstRenameClick(Sender: TObject);
var
  key, v: string;
begin
  if FVst = nil then Exit;
  key := FVst.SelectedKey;
  if key = '' then
  begin
    mmoVst.Caption := '请先点选一行，再点“改名…”。';
    Exit;
  end;
  v := FVst.SelectedText;
  if not AskText('改名', 'id=' + key + ' 的新名称：', v, v) then
  begin
    mmoVst.Caption := '已取消改名。';
    Exit;
  end;
  if v = '' then
  begin
    mmoVst.Caption := '名称不能为空，未修改。';
    Exit;
  end;
  UpdateField('vst_nodes', key, 'name', v);
  if FVst <> nil then
    FVst.SelectKey(key);
  if FVstMulti <> nil then
    FVstMulti.SelectKey(key);
  ShowVstInfo;
  mmoVst.Caption := mmoVst.Caption + sLineBreak + sLineBreak + '已改名：id=' + key + ' → ' + v;
end;

procedure TTreeDemoForm.btnMultiRenameClick(Sender: TObject);
var
  key, v: string;
begin
  if FVstMulti = nil then Exit;
  key := FVstMulti.SelectedKey;
  if key = '' then
  begin
    lblVstMultiDetail.Caption := '请先点选一行，再点“改名…”。';
    Exit;
  end;
  v := FVstMulti.SelectedCell(0);
  if not AskText('改名', 'id=' + key + ' 的新名称：', v, v) then
  begin
    lblVstMultiDetail.Caption := '已取消改名。';
    Exit;
  end;
  if v = '' then
  begin
    lblVstMultiDetail.Caption := '名称不能为空，未修改。';
    Exit;
  end;
  UpdateField('vst_nodes', key, 'name', v);
  if FVst <> nil then
    FVst.SelectKey(key);
  if FVstMulti <> nil then
    FVstMulti.SelectKey(key);
  ShowMultiInfo;
  lblVstMultiDetail.Caption := lblVstMultiDetail.Caption + sLineBreak + sLineBreak +
    '已改名：id=' + key + ' → ' + v;
end;

procedure TTreeDemoForm.btnTreeNoteClick(Sender: TObject);
var
  key, v: string;
begin
  key := tvDb.NodeKey(tvDb.Selected);
  if key = '' then
  begin
    mmoTv.Caption := '请先点选一行，再点“改备注…”。';
    Exit;
  end;
  v := FetchNote('tv_nodes', key);
  if not AskText('改备注', 'id=' + key + ' 的新备注（可留空）：', v, v) then
  begin
    mmoTv.Caption := '已取消改备注。';
    Exit;
  end;
  UpdateField('tv_nodes', key, 'note', v);
  tvDb.SelectKey(key);
  ShowTreeInfo;
  mmoTv.Caption := mmoTv.Caption + sLineBreak + sLineBreak + '已改备注：id=' + key;
end;

procedure TTreeDemoForm.btnVstNoteClick(Sender: TObject);
var
  key, v: string;
begin
  if FVst = nil then Exit;
  key := FVst.SelectedKey;
  if key = '' then
  begin
    mmoVst.Caption := '请先点选一行，再点“改备注…”。';
    Exit;
  end;
  v := FetchNote('vst_nodes', key);
  if not AskText('改备注', 'id=' + key + ' 的新备注（可留空）：', v, v) then
  begin
    mmoVst.Caption := '已取消改备注。';
    Exit;
  end;
  UpdateField('vst_nodes', key, 'note', v);
  if FVst <> nil then
    FVst.SelectKey(key);
  if FVstMulti <> nil then
    FVstMulti.SelectKey(key);
  ShowVstInfo;
  mmoVst.Caption := mmoVst.Caption + sLineBreak + sLineBreak + '已改备注：id=' + key;
end;

procedure TTreeDemoForm.btnMultiNoteClick(Sender: TObject);
var
  key, v: string;
begin
  if FVstMulti = nil then Exit;
  key := FVstMulti.SelectedKey;
  if key = '' then
  begin
    lblVstMultiDetail.Caption := '请先点选一行，再点“改备注…”。';
    Exit;
  end;
  v := FVstMulti.SelectedCell(2);
  if not AskText('改备注', 'id=' + key + ' 的新备注（可留空）：', v, v) then
  begin
    lblVstMultiDetail.Caption := '已取消改备注。';
    Exit;
  end;
  UpdateField('vst_nodes', key, 'note', v);
  if FVst <> nil then
    FVst.SelectKey(key);
  if FVstMulti <> nil then
    FVstMulti.SelectKey(key);
  ShowMultiInfo;
  lblVstMultiDetail.Caption := lblVstMultiDetail.Caption + sLineBreak + sLineBreak +
    '已改备注：id=' + key;
end;

end.
