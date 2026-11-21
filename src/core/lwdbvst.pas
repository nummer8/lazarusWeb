{
  lazarusWeb :: lwdbvst
  ------------------------------------------------------------------
  数据感知 VirtualTreeView：TLWDBVirtualTreeView = TLazVirtualStringTree
  + TDataSource。节点不预先建满，OnInitNode / OnInitChildren / OnGetText
  按需从缓存取数，因此几万行也只建当前可见的虚拟节点。

  published 属性：

    DataSource    TDataSource，绑定后自动跟随数据集变化
    KeyField      主键字段名，默认 'id'
    ParentField   父键字段名，默认 'parent_id'（NULL 表示根节点）
    TextField     显示字段名，默认 'name'
    TextFields    多列字段，分号分隔，如 'name;id;note'；
                  未设置时等价于只有 TextField
    AutoExpand    重建后是否展开全部节点，默认 False。
                  节点是虚拟的，几万行时别开；小树（如目录/部门）开了更好用

  DataLink 监听 deDataSetChange / deRecordChange / deUpdateRecord /
  deUpdateState，数据集 Post / Delete / Refresh 之后自动重建节点；
  数据集处于 dsEdit / dsInsert 时不重建。

  公开方法：

    RefreshTree              按数据集重建（先 RootNodeCount:=0 丢掉虚拟节点
                             缓存，再按主键恢复选中）
    SelectedKey / SelectedText / SelectedCell(AColumn)
                             当前选中行的主键 / 第一列 / 指定列
    SelectKey(AKey)          按主键选中（会展开它的所有祖先）

  坑：VST 的节点是惰性初始化的，GetFirst/GetFirstChild 拿到的节点可能还没
  跑过 OnInitNode，此时 GetNodeData 得到的是未初始化内存。按节点数据做判断
  之前必须先调 InitNode(节点)；另外"展开节点"会新建子节点、重新分配节点内存
  池，之前持有的 PVirtualNode 指针会全部失效 —— 所以本单元一律按主键找节点，
  不在展开前后复用节点指针。

  编译开关 LW_VIRTUALTREEVIEW：
    本单元直接依赖 laz.virtualtrees（VirtualTreeView 组件包），
    只有定义了 LW_VIRTUALTREEVIEW 的工程才应该 uses 它。框架的
    序列化层 lwwriter / lwdispatch 用同一个开关，两边必须一致，
    否则树会按普通 TTreeView 序列化、丢掉多列信息。

  设计期：lwdesign 包（编译选项带 -dLW_VIRTUALTREEVIEW）把本类注册到
  组件面板 "lazarusWeb" 页，图标见 design/icons/TLWDBVirtualTreeView.png。
}
unit lwdbvst;

{$mode objfpc}{$H+}

interface

{$IFDEF LW_VIRTUALTREEVIEW}
uses
  Classes, SysUtils, DB, laz.virtualtrees, lwdbtree;

type
  PDBVSTNode = ^TDBVSTNode;
  TDBVSTNode = record
    { 该虚拟节点对应的数据集记录在 FKeys / FCellTexts 里的下标 }
    RecIndex: Integer;
  end;

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
    FParentKeys: TStringList;
    FAutoExpand: Boolean;
    function GetTextFields: string;
    procedure SetDataSource(AValue: TDataSource);
    procedure SetTextFields(const AValue: string);
    procedure SetAutoExpand(AValue: Boolean);
    procedure DataLinkChanged(Sender: TObject);
    function ChildList(const AKey: string): TStringList;
    function NodeKeyOf(N: PVirtualNode): string;
    function FindNodeByKey(AParent: PVirtualNode; const AKey: string): PVirtualNode;
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
    { 按主键选中节点（并展开它的所有父级）；返回 True 表示找到。
      RefreshTree 会丢弃全部虚拟节点，选中态靠它对上 key 恢复。 }
    function SelectKey(const AKey: string): Boolean;
  published
    property DataSource: TDataSource read FDataSource write SetDataSource;
    property KeyField: string read FKeyField write FKeyField;
    property ParentField: string read FParentField write FParentField;
    property TextField: string read FTextField write FTextField;
    property TextFields: string read GetTextFields write SetTextFields;
    property AutoExpand: Boolean read FAutoExpand write SetAutoExpand;
  end;
{$ENDIF}

implementation

{$IFDEF LW_VIRTUALTREEVIEW}

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
  FParentKeys := TStringList.Create;
  NodeDataSize := SizeOf(TDBVSTNode);
  { 无头 widgetset（nogui / lwproxyws 的工作线程实现）里没有字体度量，
    VST 构造时用 Scale96ToFont 算出来的节点高度会是 0；而它内部的滚屏、
    定位都按节点高度做除法，一选中或一滚动就 EDivByZero。
    这里给一个不依赖字体度量的兜底值（有真实度量时保留原值）。 }
  if DefaultNodeHeight < 1 then
    DefaultNodeHeight := 22;
  OnInitNode := @BDInitNode;
  OnInitChildren := @BDInitChildren;
  OnGetText := @BDGetText;
end;

destructor TLWDBVirtualTreeView.Destroy;
var
  i: Integer;
begin
  { 构造中途抛异常时（VST 的 inherited Create 失败）各列表可能还是 nil，
    FPC 仍会调用析构 —— 这里必须逐个判空，否则会在清理阶段再踩一次 AV，
    把真正的原始异常彻底盖掉。 }
  FDataLink.Free;
  FDataLink := nil;
  if FChildren <> nil then
    for i := 0 to FChildren.Count - 1 do
      FChildren.Objects[i].Free;
  if FCellTexts <> nil then
    for i := 0 to FCellTexts.Count - 1 do
      FCellTexts.Objects[i].Free;
  FreeAndNil(FChildren);
  FreeAndNil(FRootKeys);
  FreeAndNil(FParentKeys);
  FreeAndNil(FTexts);
  FreeAndNil(FCellTexts);
  FreeAndNil(FTextFields);
  FreeAndNil(FKeys);
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

procedure TLWDBVirtualTreeView.SetAutoExpand(AValue: Boolean);
begin
  if FAutoExpand = AValue then Exit;
  FAutoExpand := AValue;
  if FAutoExpand and (RootNodeCount > 0) then
    FullExpand;
end;

function TLWDBVirtualTreeView.NodeKeyOf(N: PVirtualNode): string;
var
  idx: Integer;
begin
  Result := '';
  if N = nil then Exit;
  { VST 的节点可能已经建出来但还没跑过 OnInitNode（惰性初始化），
    此时 GetNodeData 拿到的是未初始化内存，RecIndex 是脏值 —— 不强制
    初始化就按它比较 key 会误命中别人，接着对无效节点做展开就是 AV。 }
  InitNode(N);
  idx := PDBVSTNode(GetNodeData(N))^.RecIndex;
  if (idx >= 0) and (idx < FKeys.Count) then
    Result := FKeys[idx];
end;

function TLWDBVirtualTreeView.FindNodeByKey(AParent: PVirtualNode;
  const AKey: string): PVirtualNode;
var
  n: PVirtualNode;
begin
  Result := nil;
  if AParent = nil then
    n := GetFirst
  else
    n := GetFirstChild(AParent);
  while n <> nil do
  begin
    if NodeKeyOf(n) = AKey then
      Exit(n);
    Result := FindNodeByKey(n, AKey);
    if Result <> nil then Exit;
    n := GetNextSibling(n);
  end;
end;

function TLWDBVirtualTreeView.SelectKey(const AKey: string): Boolean;
var
  n: PVirtualNode;
  chain: TStringList;
  k: string;
  i: Integer;
begin
  Result := False;
  if AKey = '' then Exit;

  { 祖先链只能按 key 算、不能按 PVirtualNode 走：
    展开一个节点会让 VST 新建子节点、重新分配节点内存池，
    之前拿到的 PVirtualNode 指针全部失效（踩过：AV 在 GetNodeData）。
    所以每展开一层都重新按 key 找一次节点。 }
  chain := TStringList.Create;
  try
    k := AKey;
    while True do
    begin
      i := FKeys.IndexOf(k);
      if i < 0 then Break;
      k := FParentKeys[i];
      if k = '' then Break;
      chain.Insert(0, k);
    end;
    for i := 0 to chain.Count - 1 do
    begin
      n := FindNodeByKey(nil, chain[i]);
      if n <> nil then
        Expanded[n] := True;
    end;
  finally
    chain.Free;
  end;

  n := FindNodeByKey(nil, AKey);
  if n = nil then Exit;
  ClearSelection;
  Selected[n] := True;
  FocusedNode := n;
  ScrollIntoView(n, False);
  Result := True;
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
  key, parentKey, oldKey: string;
  cells: TStringList;
  i, j, colCount: Integer;
begin
  if FRebuilding or (csDestroying in ComponentState) then Exit;
  FRebuilding := True;
  { 虚拟节点全部要丢掉，先记住选中行的主键，重建后按主键选回来 }
  oldKey := SelectedKey;
  try
    for i := 0 to FChildren.Count - 1 do
      FChildren.Objects[i].Free;
    for i := 0 to FCellTexts.Count - 1 do
      FCellTexts.Objects[i].Free;
    FChildren.Clear;
    FKeys.Clear;
    FTexts.Clear;
    FCellTexts.Clear;
    FParentKeys.Clear;
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
        begin
          FRootKeys.Add(key);
          FParentKeys.Add('');   { 与 FKeys 一一对应，SelectKey 算祖先链用 }
        end
        else
        begin
          parentKey := fParent.AsString;
          if parentKey <> '' then
            ChildList(parentKey).Add(key);
          FParentKeys.Add(parentKey);
        end;
        ds.Next;
      end;
    finally
      ds.EnableControls;
    end;
    RootNodeCount := FRootKeys.Count;
    if FAutoExpand then
      FullExpand;
  finally
    FRebuilding := False;
  end;
  { 恢复选中：被删掉的 key 找不到时就是“无选中”，正好符合删除后的预期 }
  if oldKey <> '' then
    SelectKey(oldKey);
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
begin
  Result := '';
  n := GetFirstSelected;
  if n = nil then Exit;
  Result := NodeKeyOf(n);
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
  idx := FCellTexts.IndexOf(NodeKeyOf(n));
  if idx < 0 then Exit;
  cells := TStringList(FCellTexts.Objects[idx]);
  if (AColumn >= 0) and (AColumn < cells.Count) then
    Result := cells[AColumn];
end;

{$ENDIF}

initialization
  {$IFDEF LW_VIRTUALTREEVIEW}
  RegisterClass(TLWDBVirtualTreeView);
  {$ENDIF}

end.
