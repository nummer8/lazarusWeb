{
  lazarusWeb :: 普通 TTreeView 的多列文本寄存
  ------------------------------------------------------------------
  TTreeView 自己没有“列”的概念（列是 TListView / VirtualTreeView 才有），
  也没有可以 published 出来的多列属性。要在浏览器里把一棵原生 TTreeView
  画成“树 + 多列表格”，只能由业务代码把每行的各列文本告诉框架：

      LWTreeSetColumns(tv, ['名称', 'ID', '备注']);   // 多于 1 列才生效
      LWTreeSetCellText(tv, node, 1, '101');          // 第 0 列直接用 node.Text
      LWTreeSetCellText(tv, node, 2, '根节点');

  lwwriter.WriteTree 序列化这棵树时会读这里：列标题下发 vcols，每行的
  cols 下发各列文本；前端 lw-alpine.js 见到 vcols.length > 1 就切到
  表头 + 多列的表格状布局 —— 与 TLWDBTreeView 的多列走同一套前端。

  与 TLWDBTreeView 的分工：
    · TLWDBTreeView 自己按 TextFields 缓存列文本，数据感知，不用这套 API；
    · 本单元服务“纯手工建节点的原生 TTreeView”，文本完全由调用方决定
      （可以是库字段，也可以是算出来的值，例如子节点数）。

  生命周期：登记表按树对象存放，树被销毁时自动注销（FreeNotification），
  不会把已释放的对象留在表里。指针类型的节点 key 在重建节点后会失效，
  所以每次重建树都先调 LWTreeSetColumns（它同时清空旧的单元格文本），
  再逐行 LWTreeSetCellText。
}
unit lwtreecols;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ComCtrls;

{ 定义列标题；同时清空该树已登记的所有单元格文本（重建树的起点） }
procedure LWTreeSetColumns(T: TTreeView; const ATitles: array of string);

{ 登记某一格文本。AIndex = 0 也会被记录，但序列化与前端都优先用 node.Text，
  所以只填 1..N-1 就够了 }
procedure LWTreeSetCellText(T: TTreeView; N: TTreeNode; AIndex: Integer;
  const AText: string);

{ 只清单元格文本，保留列标题 }
procedure LWTreeClearCells(T: TTreeView);

{ 整棵树的多列登记全部注销（窗体析构时调用；树被销毁时也会自动注销） }
procedure LWTreeClearColumns(T: TTreeView);

function LWTreeColumnCount(T: TTreeView): Integer;
function LWTreeColumnTitle(T: TTreeView; AIndex: Integer): string;
function LWTreeCellText(T: TTreeView; N: TTreeNode; AIndex: Integer): string;

implementation

type
  { 每棵原生 TTreeView 一份。用 TComponent 是为了能挂 FreeNotification，
    树释放时把自己从全局表里摘掉并自毁，避免“新树分配到同一地址”读到
    上一棵树的残留列文本。 }
  TLWTreeColStore = class(TComponent)
  private
    FTree: TTreeView;
    FTitles: TStringList;
    FCells: TStringList;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor CreateForTree(ATree: TTreeView);
    destructor Destroy; override;
  end;

var
  { key = 树对象指针的十进制串；Objects[] = TLWTreeColStore }
  GStores: TStringList = nil;

function StoreKey(T: TTreeView): string;
begin
  Result := IntToStr(PtrInt(Pointer(T)));
end;

function CellKey(N: TTreeNode; AIndex: Integer): string;
begin
  Result := IntToStr(PtrInt(Pointer(N))) + '#' + IntToStr(AIndex);
end;

function FindStore(T: TTreeView; ACreate: Boolean): TLWTreeColStore;
var
  i: Integer;
begin
  Result := nil;
  if T = nil then Exit;
  if GStores = nil then
  begin
    if not ACreate then Exit;
    GStores := TStringList.Create;
    GStores.CaseSensitive := True;
  end;
  i := GStores.IndexOf(StoreKey(T));
  if i >= 0 then
    Exit(TLWTreeColStore(GStores.Objects[i]));
  if ACreate then
  begin
    Result := TLWTreeColStore.CreateForTree(T);
    GStores.AddObject(StoreKey(T), Result);
  end;
end;

{ ==================== TLWTreeColStore ==================== }

constructor TLWTreeColStore.CreateForTree(ATree: TTreeView);
begin
  inherited Create(nil);
  FTree := ATree;
  { opRemove 时把本对象从 GStores 摘掉并自毁 }
  ATree.FreeNotification(Self);
  FTitles := TStringList.Create;
  FCells := TStringList.Create;
  FCells.NameValueSeparator := '=';
end;

destructor TLWTreeColStore.Destroy;
begin
  { 先撤销登记：树还活着时要把它 FreeNotifies 里的自己摘掉，
    否则树以后析构会通知一个已经释放的对象 }
  if FTree <> nil then
  begin
    FTree.RemoveFreeNotification(Self);
    FTree := nil;
  end;
  FTitles.Free;
  FCells.Free;
  inherited Destroy;
end;

procedure TLWTreeColStore.Notification(AComponent: TComponent;
  Operation: TOperation);
var
  i: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FTree) then
  begin
    { 先把树引用断掉：下面 Destroy 里不该再碰它 }
    FTree := nil;
    if GStores <> nil then
    begin
      i := GStores.IndexOfObject(Self);
      if i >= 0 then
        GStores.Delete(i);
    end;
    { TComponent.Destroy 先把 FFreeNotifies 整个摘下来再逐个通知，
      所以这里自毁不会破坏通知链 }
    Free;
  end;
end;

{ ==================== 对外 API ==================== }

procedure LWTreeSetColumns(T: TTreeView; const ATitles: array of string);
var
  st: TLWTreeColStore;
  i: Integer;
begin
  st := FindStore(T, True);
  if st = nil then Exit;
  st.FTitles.Clear;
  st.FCells.Clear;
  for i := 0 to High(ATitles) do
    st.FTitles.Add(ATitles[i]);
end;

procedure LWTreeSetCellText(T: TTreeView; N: TTreeNode; AIndex: Integer;
  const AText: string);
var
  st: TLWTreeColStore;
  k: string;
  i: Integer;
begin
  if (T = nil) or (N = nil) or (AIndex < 0) then Exit;
  st := FindStore(T, True);
  if st = nil then Exit;
  k := CellKey(N, AIndex);
  i := st.FCells.IndexOfName(k);
  if i >= 0 then
    st.FCells[i] := k + '=' + AText
  else
    st.FCells.Add(k + '=' + AText);
end;

procedure LWTreeClearCells(T: TTreeView);
var
  st: TLWTreeColStore;
begin
  st := FindStore(T, False);
  if st <> nil then
    st.FCells.Clear;
end;

procedure LWTreeClearColumns(T: TTreeView);
var
  i: Integer;
  st: TLWTreeColStore;
begin
  if GStores = nil then Exit;
  i := GStores.IndexOf(StoreKey(T));
  if i < 0 then Exit;
  st := TLWTreeColStore(GStores.Objects[i]);
  { 先摘表再 Free：Free 之后不再有指针落在表里 }
  GStores.Delete(i);
  if st <> nil then
  begin
    st.FTree := nil;
    st.Free;
  end;
end;

function LWTreeColumnCount(T: TTreeView): Integer;
var
  st: TLWTreeColStore;
begin
  st := FindStore(T, False);
  if st = nil then
    Result := 0
  else
    Result := st.FTitles.Count;
end;

function LWTreeColumnTitle(T: TTreeView; AIndex: Integer): string;
var
  st: TLWTreeColStore;
begin
  Result := '';
  st := FindStore(T, False);
  if (st <> nil) and (AIndex >= 0) and (AIndex < st.FTitles.Count) then
    Result := st.FTitles[AIndex];
end;

function LWTreeCellText(T: TTreeView; N: TTreeNode; AIndex: Integer): string;
var
  st: TLWTreeColStore;
  i: Integer;
  k: string;
begin
  Result := '';
  if (N = nil) or (AIndex < 0) then Exit;
  st := FindStore(T, False);
  if st = nil then Exit;
  k := CellKey(N, AIndex);
  i := st.FCells.IndexOfName(k);
  if i >= 0 then
    Result := st.FCells.ValueFromIndex[i];
end;

finalization
  if GStores <> nil then
  begin
    { 进程退出时把还挂着登记的都释放掉（树可能已经先被释放，
      那种情况下表项在 Notification 里就已经摘掉了） }
    while GStores.Count > 0 do
    begin
      TLWTreeColStore(GStores.Objects[0]).Free;
      GStores.Delete(0);
    end;
    FreeAndNil(GStores);
  end;

end.
