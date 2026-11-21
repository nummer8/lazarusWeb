{
  lazarusWeb :: treedemo 的数据感知树控件
  ------------------------------------------------------------------
  两个控件都暴露 TDataSource 风格接口：

      DataSource / KeyField / ParentField / TextField

  数据集发生 Post / Delete / Refresh 等变化时，DataLink 收到通知，
  自动按 id + parent_id + name 重建整棵树。

    TLWDBTreeView          继承 TTreeView，节点 Data 存 id
    TLWDBVirtualTreeView   继承 TLazVirtualStringTree，虚拟节点按需取数

  放在 demo 目录而不是框架源码里：框架只需认识 TTreeView /
  TBaseVirtualTree，数据绑定属于业务层。
}
unit uDBTree;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Variants, DB, ComCtrls, laz.virtualtrees;

type
  TDBTreeDataLink = class(TDataLink)
  private
    FOnChange: TNotifyEvent;
  protected
    procedure DataEvent(Event: TDataEvent; Info: Ptrint); override;
  public
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  { 标准 LCL 树 + DataSource }
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
  published
    property DataSource: TDataSource read FDataSource write SetDataSource;
    property KeyField: string read FKeyField write FKeyField;
    property ParentField: string read FParentField write FParentField;
    property TextField: string read FTextField write FTextField;
  end;

  PDBVSTNode = ^TDBVSTNode;
  TDBVSTNode = record
    RecIndex: Integer;
  end;

  { VirtualTreeView + DataSource }
  TLWDBVirtualTreeView = class(TLazVirtualStringTree)
  private
    FDataSource: TDataSource;
    FDataLink: TDBTreeDataLink;
    FKeyField: string;
    FParentField: string;
    FTextField: string;
    FRebuilding: Boolean;
    FKeys: TStringList;
    FTexts: TStringList;
    FCellTexts: TStringList;
    FTextFields: TStringList;
    FChildren: TStringList;
    FRootKeys: TStringList;
    function GetTextFields: string;
    procedure SetDataSource(AValue: TDataSource);
    procedure SetTextFields(const AValue: string);
    procedure DataLinkChanged(Sender: TObject);
    function ChildList(const AKey: string): TStringList;
    procedure BDInitNode(Sender: TBaseVirtualTree; ParentNode, Node: PVirtualNode;
      var InitialStates: TVirtualNodeInitStates);
    procedure BDInitChildren(Sender: TBaseVirtualTree; Node: PVirtualNode;
      var AChildCount: Cardinal);
    procedure BDGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RefreshTree;
    function SelectedKey: string;
    function SelectedText: string;
    function SelectedCell(AColumn: Integer): string;
  published
    property DataSource: TDataSource read FDataSource write SetDataSource;
    property KeyField: string read FKeyField write FKeyField;
    property ParentField: string read FParentField write FParentField;
    property TextField: string read FTextField write FTextField;
    { 多列字段：用分号分隔，如 'name;id;note'；未设置时等价于只有 TextField }
    property TextFields: string read GetTextFields write SetTextFields;
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

procedure TLWDBTreeView.RefreshTree;
var
  ds: TDataSet;
  fKey, fParent, fText: TField;
  keys, parents: TStringList;
  i, j: Integer;
  n, p: TTreeNode;
  pid: PInt64;
  s: string;
begin
  if FRebuilding or (csDestroying in ComponentState) then Exit;
  FRebuilding := True;
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
    for i := 0 to Items.Count - 1 do
      Items[i].Expanded := True;
  finally
    FRebuilding := False;
  end;
end;

{ ==================== TLWDBVirtualTreeView ==================== }

constructor TLWDBVirtualTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDataLink := TDBTreeDataLink.Create;
  FDataLink.OnChange := @DataLinkChanged;
  FKeyField := 'id';
  FParentField := 'parent_id';
  FTextField := 'name';
  FKeys := TStringList.Create;
  FTexts := TStringList.Create;
  FCellTexts := TStringList.Create;
  FTextFields := TStringList.Create;
  FTextFields.Delimiter := ';';
  FTextFields.StrictDelimiter := True;
  FChildren := TStringList.Create;
  FRootKeys := TStringList.Create;
  NodeDataSize := SizeOf(TDBVSTNode);
  OnInitNode := @BDInitNode;
  OnInitChildren := @BDInitChildren;
  OnGetText := @BDGetText;
end;

destructor TLWDBVirtualTreeView.Destroy;
var
  i: Integer;
begin
  FDataLink.Free;
  for i := 0 to FChildren.Count - 1 do
    FChildren.Objects[i].Free;
  for i := 0 to FCellTexts.Count - 1 do
    FCellTexts.Objects[i].Free;
  FChildren.Free;
  FRootKeys.Free;
  FTexts.Free;
  FCellTexts.Free;
  FTextFields.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TLWDBVirtualTreeView.DataLinkChanged(Sender: TObject);
begin
  if (csDestroying in ComponentState) then Exit;
  if (FDataSource <> nil) and (FDataSource.DataSet <> nil) and
     (FDataSource.DataSet.State in [dsEdit, dsInsert]) then Exit;
  RefreshTree;
end;

procedure TLWDBVirtualTreeView.SetDataSource(AValue: TDataSource);
begin
  if FDataSource = AValue then Exit;
  FDataSource := AValue;
  FDataLink.DataSource := AValue;
  RefreshTree;
end;

function TLWDBVirtualTreeView.GetTextFields: string;
begin
  Result := FTextFields.DelimitedText;
end;

procedure TLWDBVirtualTreeView.SetTextFields(const AValue: string);
begin
  FTextFields.Delimiter := ';';
  FTextFields.StrictDelimiter := True;
  FTextFields.DelimitedText := AValue;
  RefreshTree;
end;

function TLWDBVirtualTreeView.ChildList(const AKey: string): TStringList;
var
  i: Integer;
  l: TStringList;
begin
  i := FChildren.IndexOf(AKey);
  if i >= 0 then
    Exit(TStringList(FChildren.Objects[i]));
  l := TStringList.Create;
  FChildren.AddObject(AKey, l);
  Result := l;
end;

procedure TLWDBVirtualTreeView.RefreshTree;
var
  ds: TDataSet;
  fKey, fParent: TField;
  fields: array of TField;
  key, parentKey: string;
  cells, l: TStringList;
  i, j, colCount: Integer;
begin
  if FRebuilding or (csDestroying in ComponentState) then Exit;
  FRebuilding := True;
  try
    for i := 0 to FChildren.Count - 1 do
      FChildren.Objects[i].Free;
    for i := 0 to FCellTexts.Count - 1 do
      FCellTexts.Objects[i].Free;
    FChildren.Clear;
    FKeys.Clear;
    FTexts.Clear;
    FCellTexts.Clear;
    FRootKeys.Clear;
    { VST 会缓存根节点数和每个节点的子数；只把 RootNodeCount 设成
      同一个值不会重建已有虚拟节点，新增/删除的数据看不出来。
      先清零强制丢弃全部缓存节点，下面再按新数据重建。 }
    RootNodeCount := 0;

    ds := nil;
    if FDataSource <> nil then
      ds := FDataSource.DataSet;
    if (ds = nil) or (not ds.Active) then
    begin
      RootNodeCount := 0;
      Exit;
    end;
    fKey := ds.FindField(FKeyField);
    fParent := ds.FindField(FParentField);
    if (fKey = nil) or (fParent = nil) then
    begin
      RootNodeCount := 0;
      Exit;
    end;
    { TextFields 优先；未设置时退回单列 TextField }
    colCount := FTextFields.Count;
    if colCount < 1 then colCount := 1;
    SetLength(fields, colCount);
    for j := 0 to colCount - 1 do
    begin
      if FTextFields.Count > 0 then
        fields[j] := ds.FindField(FTextFields[j])
      else
        fields[j] := ds.FindField(FTextField);
      if fields[j] = nil then
      begin
        RootNodeCount := 0;
        Exit;
      end;
    end;

    ds.DisableControls;
    try
      ds.First;
      while not ds.EOF do
      begin
        key := fKey.AsString;
        FKeys.Add(key);
        cells := TStringList.Create;
        for j := 0 to colCount - 1 do
          cells.Add(fields[j].AsString);
        FCellTexts.AddObject(key, cells);
        FTexts.Add(cells[0]);   { SelectedText 仍返回第一列 }
        ChildList(key);   { 确保每个 key 都有子列表，OnInitChildren 直接取用 }
        if fParent.IsNull then
          FRootKeys.Add(key)
        else
        begin
          parentKey := fParent.AsString;
          if parentKey <> '' then
            ChildList(parentKey).Add(key);
        end;
        ds.Next;
      end;
    finally
      ds.EnableControls;
    end;
    RootNodeCount := FRootKeys.Count;
  finally
    FRebuilding := False;
  end;
end;

procedure TLWDBVirtualTreeView.BDInitNode(Sender: TBaseVirtualTree;
  ParentNode, Node: PVirtualNode; var InitialStates: TVirtualNodeInitStates);
var
  d: PDBVSTNode;
  key: string;
  idx: Integer;
begin
  d := PDBVSTNode(Sender.GetNodeData(Node));
  if ParentNode = nil then
  begin
    if Node^.Index >= FRootKeys.Count then Exit;
    key := FRootKeys[Node^.Index];
  end
  else
  begin
    idx := PDBVSTNode(Sender.GetNodeData(ParentNode))^.RecIndex;
    if (idx < 0) or (idx >= FKeys.Count) then Exit;
    key := ChildList(FKeys[idx])[Node^.Index];
  end;
  idx := FKeys.IndexOf(key);
  d^.RecIndex := idx;
  if ChildList(key).Count > 0 then
    Include(InitialStates, ivsHasChildren);
end;

procedure TLWDBVirtualTreeView.BDInitChildren(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var AChildCount: Cardinal);
var
  d: PDBVSTNode;
  idx: Integer;
begin
  d := PDBVSTNode(Sender.GetNodeData(Node));
  AChildCount := 0;
  idx := d^.RecIndex;
  if (idx >= 0) and (idx < FKeys.Count) then
    AChildCount := ChildList(FKeys[idx]).Count;
end;

procedure TLWDBVirtualTreeView.BDGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  idx: Integer;
  cells: TStringList;
begin
  idx := PDBVSTNode(Sender.GetNodeData(Node))^.RecIndex;
  if (idx < 0) or (idx >= FCellTexts.Count) then Exit;
  cells := TStringList(FCellTexts.Objects[idx]);
  if (Column >= 0) and (Column < cells.Count) then
    CellText := cells[Column];
end;

function TLWDBVirtualTreeView.SelectedKey: string;
var
  n: PVirtualNode;
  idx: Integer;
begin
  Result := '';
  n := GetFirstSelected;
  if n = nil then Exit;
  idx := PDBVSTNode(GetNodeData(n))^.RecIndex;
  if (idx >= 0) and (idx < FKeys.Count) then
    Result := FKeys[idx];
end;

function TLWDBVirtualTreeView.SelectedText: string;
begin
  Result := SelectedCell(0);
end;

function TLWDBVirtualTreeView.SelectedCell(AColumn: Integer): string;
var
  n: PVirtualNode;
  idx: Integer;
  cells: TStringList;
begin
  Result := '';
  n := GetFirstSelected;
  if n = nil then Exit;
  idx := PDBVSTNode(GetNodeData(n))^.RecIndex;
  if (idx < 0) or (idx >= FCellTexts.Count) then Exit;
  cells := TStringList(FCellTexts.Objects[idx]);
  if (AColumn >= 0) and (AColumn < cells.Count) then
    Result := cells[AColumn];
end;

initialization
  RegisterClass(TLWDBTreeView);

end.
