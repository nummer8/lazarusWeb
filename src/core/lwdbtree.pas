{
  lazarusWeb :: lwdbtree
  ------------------------------------------------------------------
  数据感知 TreeView（DataSource -> 节点）。与 lwdbgrid / lwdbnav 同级，
  属于框架的控件层；运行时由 lwwriter 序列化成前端 kind='tree'。

    TLWDBTreeView = TTreeView + TDataSource

  published 属性：

    DataSource    TDataSource，绑定后自动跟随数据集变化
    KeyField      主键字段名，默认 'id'
    ParentField   父键字段名，默认 'parent_id'（NULL 表示根节点）
    TextField     显示字段名，默认 'name'
    TextFields    多列字段名，分号分隔（如 'name;id;note'）。
                  多于一项时 lwwriter 会下发 vcols + 每个节点的 cols，
                  浏览器端按多列（表格状）渲染；留空 = 原来的单列。
    ColumnTitles  多列标题，分号分隔（如 '名称;ID;备注'）；留空则用字段名

  DataLink 监听 deDataSetChange / deRecordChange / deUpdateRecord /
  deUpdateState，数据集 Post / Delete / Refresh 之后自动重建节点；
  数据集处于 dsEdit / dsInsert 时不重建（否则会取消编辑状态）。

  公开方法：

    RefreshTree              按数据集重建全部节点（重建后按主键恢复选中）
    NodeKey(N)               取某个 TTreeNode 的主键
    SelectedKey              当前选中行的主键，空串表示没选中
    SelectKey(AKey)          按主键选中节点（找不到返回 False）

  本单元不依赖 VirtualTreeView，nogui / 无 VST 的工程可以直接用。
  VirtualTreeView 版本见 lwdbvst.pas（需要 LW_VIRTUALTREEVIEW）。

  设计期：lwdesign 包把 TLWDBTreeView 注册到组件面板 "lazarusWeb" 页，
  图标见 design/icons/TLWDBTreeView.png。
}
unit lwdbtree;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DB, ComCtrls;

type
  { 只把 DataSource 的必要事件转成一个 OnChange 回调：
    对 deDataSetChange 全集做过滤，避免游标每动一下就重建树 }
  TDBTreeDataLink = class(TDataLink)
  private
    FOnChange: TNotifyEvent;
  protected
    procedure DataEvent(Event: TDataEvent; Info: Ptrint); override;
  public
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TLWDBTreeView = class(TTreeView)
  private
    FDataSource: TDataSource;
    FDataLink: TDBTreeDataLink;
    FKeyField: string;
    FParentField: string;
    FTextField: string;
    FTextFields: string;
    FColumnTitles: string;
    { TextFields / ColumnTitles 的解析结果（分号分隔，避免每次序列化都拆串）}
    FFieldList: TStringList;
    FTitleList: TStringList;
    { 多列文本缓存：Sorted，Values[主键] = 各列文本（#1 分隔）。
      节点只存主键，多列文本不能挂在 TTreeNode 上，所以重建时按行缓存一份，
      序列化时按主键取 —— 不在 lwwriter 里逐节点查库。 }
    FCellCache: TStringList;
    FRebuilding: Boolean;
    procedure SetDataSource(AValue: TDataSource);
    procedure SetTextFields(AValue: string);
    procedure SetColumnTitles(AValue: string);
    procedure DataLinkChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RefreshTree;
    function NodeKey(N: TTreeNode): string;
    { 按主键选中节点；返回 True 表示找到。
      RefreshTree 之后节点对象全部重建，选中态本来会丢，用它对上 key 恢复。 }
    function SelectKey(const AKey: string): Boolean;
    function SelectedKey: string;
    { 多列支持：列数 / 列标题 / 某节点某列文本。
      ColumnCount <= 1 时按单列处理，CellText(0) 就是节点 Text。 }
    function ColumnCount: Integer;
    function ColumnTitle(ACol: Integer): string;
    function CellText(N: TTreeNode; ACol: Integer): string;
  published
    property DataSource: TDataSource read FDataSource write SetDataSource;
    property KeyField: string read FKeyField write FKeyField;
    property ParentField: string read FParentField write FParentField;
    property TextField: string read FTextField write FTextField;
    property TextFields: string read FTextFields write SetTextFields;
    property ColumnTitles: string read FColumnTitles write SetColumnTitles;
  end;

implementation

{ ==================== 小工具 ==================== }

{ TextFields / ColumnTitles 都是"分号分隔"的短串，用 DelimitedText 解析；
  字段名与列标题里不会出现引号，无需操心转义。 }
procedure SplitSemi(const AValue: string; ADest: TStringList);
begin
  ADest.Clear;
  if Trim(AValue) = '' then Exit;
  ADest.Delimiter := ';';
  ADest.StrictDelimiter := True;
  ADest.DelimitedText := AValue;
end;

{ 取列文本缓存里的第 AIndex 段。用手工扫 #1 而不是 TStringList.DelimitedText：
  后者会解析引号，字段值里出现 " 就会整行错位。 }
function CellAt(const S: string; AIndex: Integer): string;
var
  i, n, start: Integer;
begin
  Result := '';
  if AIndex < 0 then Exit;
  start := 1;
  n := 0;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = #1) then
    begin
      if n = AIndex then
        Exit(Copy(S, start, i - start));
      Inc(n);
      start := i + 1;
    end;
end;

{ ==================== DataLink ==================== }

procedure TDBTreeDataLink.DataEvent(Event: TDataEvent; Info: Ptrint);
begin
  inherited DataEvent(Event, Info);
  if Event in [deDataSetChange, deRecordChange, deUpdateRecord, deUpdateState] then
    if Assigned(FOnChange) then
      FOnChange(Self);
end;

{ ==================== TLWDBTreeView ==================== }

constructor TLWDBTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDataLink := TDBTreeDataLink.Create;
  FDataLink.OnChange := @DataLinkChanged;
  FKeyField := 'id';
  FParentField := 'parent_id';
  FTextField := 'name';
  FFieldList := TStringList.Create;
  FTitleList := TStringList.Create;
  FCellCache := TStringList.Create;
  { 主键当 key 存列文本，二分查找；重复主键不可能出现，忽略即可 }
  FCellCache.Sorted := True;
  FCellCache.CaseSensitive := False;
  FCellCache.Duplicates := dupIgnore;
end;

destructor TLWDBTreeView.Destroy;
begin
  FDataLink.Free;
  FFieldList.Free;
  FTitleList.Free;
  FCellCache.Free;
  inherited Destroy;
end;

procedure TLWDBTreeView.SetTextFields(AValue: string);
begin
  AValue := Trim(AValue);
  if FTextFields = AValue then Exit;
  FTextFields := AValue;
  SplitSemi(FTextFields, FFieldList);
  { 列变了：缓存要按新字段重建（数据源未打开时 RefreshTree 内部会直接返回）}
  if not (csDestroying in ComponentState) then
    RefreshTree;
end;

procedure TLWDBTreeView.SetColumnTitles(AValue: string);
begin
  if FColumnTitles = AValue then Exit;
  FColumnTitles := AValue;
  SplitSemi(FColumnTitles, FTitleList);
end;

function TLWDBTreeView.ColumnCount: Integer;
begin
  Result := FFieldList.Count;
end;

function TLWDBTreeView.ColumnTitle(ACol: Integer): string;
begin
  Result := '';
  if (ACol < 0) or (ACol >= FFieldList.Count) then Exit;
  if (ACol < FTitleList.Count) and (Trim(FTitleList[ACol]) <> '') then
    Result := Trim(FTitleList[ACol])
  else
    Result := FFieldList[ACol];
end;

function TLWDBTreeView.CellText(N: TTreeNode; ACol: Integer): string;
begin
  Result := '';
  if (N = nil) or (ACol < 0) then Exit;
  if FFieldList.Count <= 1 then
  begin
    { 单列：ColumnCount=1 时前端不按多列渲染，这里只给个合理值 }
    if ACol = 0 then Result := N.Text;
    Exit;
  end;
  if ACol = 0 then
  begin
    { 第 0 列恒与树显示文本一致（前端多列布局也是用 text 画第一列）}
    Result := N.Text;
    Exit;
  end;
  Result := CellAt(FCellCache.Values[NodeKey(N)], ACol);
end;

procedure TLWDBTreeView.DataLinkChanged(Sender: TObject);
begin
  { 编辑/插入态不要重建：RefreshTree 会移动数据集游标，
    那会把 Append/Insert 状态取消掉。等 Post 后再刷。 }
  if (csDestroying in ComponentState) then Exit;
  if (FDataSource <> nil) and (FDataSource.DataSet <> nil) and
     (FDataSource.DataSet.State in [dsEdit, dsInsert]) then Exit;
  RefreshTree;
end;

procedure TLWDBTreeView.SetDataSource(AValue: TDataSource);
begin
  if FDataSource = AValue then Exit;
  FDataSource := AValue;
  FDataLink.DataSource := AValue;
  RefreshTree;
end;

function TLWDBTreeView.NodeKey(N: TTreeNode): string;
begin
  Result := '';
  if (N = nil) or (N.Data = nil) then Exit;
  Result := IntToStr(PInt64(N.Data)^);
end;

function TLWDBTreeView.SelectedKey: string;
begin
  Result := NodeKey(Selected);
end;

function TLWDBTreeView.SelectKey(const AKey: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if AKey = '' then Exit;
  for i := 0 to Items.Count - 1 do
    if NodeKey(Items[i]) = AKey then
    begin
      Selected := Items[i];
      Items[i].MakeVisible;
      Result := True;
      Exit;
    end;
end;

procedure TLWDBTreeView.RefreshTree;
var
  ds: TDataSet;
  fKey, fParent, fText: TField;
  fields: array of TField;
  keys, parents: TStringList;
  i, j, k: Integer;
  n, p: TTreeNode;
  pid: PInt64;
  s, oldKey, cells: string;
begin
  if FRebuilding or (csDestroying in ComponentState) then Exit;
  FRebuilding := True;
  { 重建会丢掉所有 TTreeNode，先记住当前选中行的主键，重建后按主键选回来 }
  oldKey := SelectedKey;
  FCellCache.Clear;
  Items.BeginUpdate;
  try
    for i := 0 to Items.Count - 1 do
      if Items[i].Data <> nil then
        Dispose(PInt64(Items[i].Data));
    Items.Clear;

    ds := nil;
    if FDataSource <> nil then
      ds := FDataSource.DataSet;
    if (ds = nil) or (not ds.Active) then Exit;
    fKey := ds.FindField(FKeyField);
    fParent := ds.FindField(FParentField);
    fText := ds.FindField(FTextField);
    if (fKey = nil) or (fParent = nil) or (fText = nil) then Exit;

    { 多列：按 TextFields 找字段。字段不存在时该列留空，不影响建树。 }
    SetLength(fields, 0);
    if FFieldList.Count > 1 then
    begin
      SetLength(fields, FFieldList.Count);
      for k := 0 to FFieldList.Count - 1 do
        fields[k] := ds.FindField(FFieldList[k]);
    end;

    keys := TStringList.Create;
    parents := TStringList.Create;
    try
      ds.DisableControls;
      try
        ds.First;
        while not ds.EOF do
        begin
          s := fKey.AsString;
          n := Items.Add(nil, fText.AsString);
          New(pid);
          pid^ := StrToInt64Def(s, 0);
          n.Data := pid;
          keys.AddObject(s, TObject(n));
          { 同一遍把各列文本按主键缓存下来（序列化时按主键取，不再查库）}
          if Length(fields) > 0 then
          begin
            cells := '';
            for k := 0 to High(fields) do
            begin
              if k > 0 then cells := cells + #1;
              if fields[k] <> nil then
                cells := cells + fields[k].AsString;
            end;
            FCellCache.Values[s] := cells;
          end;
          if fParent.IsNull then
            parents.Add('')
          else
            parents.Add(fParent.AsString);
          ds.Next;
        end;
        { 第二遍挂父子关系：第一遍时父节点可能还没建出来 }
        for i := 0 to keys.Count - 1 do
        begin
          s := parents[i];
          if s = '' then Continue;
          j := keys.IndexOf(s);
          if j < 0 then Continue;
          n := TTreeNode(keys.Objects[i]);
          p := TTreeNode(keys.Objects[j]);
          n.MoveTo(p, naAddChild);
        end;
      finally
        ds.EnableControls;
      end;
    finally
      keys.Free;
      parents.Free;
    end;
    { 默认全展开：数据感知树每次重建都会丢掉展开状态，
       统一展开比记住旧状态更符合“点开就看到全貌”的预期 }
    for i := 0 to Items.Count - 1 do
      Items[i].Expanded := True;
  finally
    Items.EndUpdate;
    FRebuilding := False;
  end;
  { 恢复选中：被删掉的 key 找不到时就是“无选中”，正好符合删除后的预期 }
  if oldKey <> '' then
    SelectKey(oldKey);
end;

initialization
  RegisterClass(TLWDBTreeView);

end.
