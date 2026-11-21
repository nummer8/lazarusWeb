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
    FRebuilding: Boolean;
    procedure SetDataSource(AValue: TDataSource);
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
  published
    property DataSource: TDataSource read FDataSource write SetDataSource;
    property KeyField: string read FKeyField write FKeyField;
    property ParentField: string read FParentField write FParentField;
    property TextField: string read FTextField write FTextField;
  end;

implementation

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
end;

destructor TLWDBTreeView.Destroy;
begin
  FDataLink.Free;
  inherited Destroy;
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
  keys, parents: TStringList;
  i, j: Integer;
  n, p: TTreeNode;
  pid: PInt64;
  s, oldKey: string;
begin
  if FRebuilding or (csDestroying in ComponentState) then Exit;
  FRebuilding := True;
  { 重建会丢掉所有 TTreeNode，先记住当前选中行的主键，重建后按主键选回来 }
  oldKey := SelectedKey;
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
