{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: lwvirtualtree
  ------------------------------------------------------------------
  VirtualTreeView 桥接层（可选）。

  VirtualTreeView 的节点是"虚拟"的：数据由 OnInitNode / OnInitChildren /
  OnGetText 事件按需提供，不像 TTreeView.Items 那样有持久化列表。
  本单元把虚拟节点遍历成 lazarusWeb 既有的 tree JSON 结构（nodes /
  children / text / expanded / selected / level），并给每个节点附加
  稳定的路径 id（如 "0.1.2"），浏览器点击后服务端按 id 找回节点。

  仅在定义 LW_VIRTUALTREEVIEW 时由 lwwriter / lwdispatch 引用，
  不给其它 demo 引入 VirtualTreeView 包依赖。
}
unit lwvirtualtree;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, laz.virtualtrees;

function LWVirtualTreeNodesJson(T: TBaseVirtualTree): TJSONArray;
function LWVirtualTreeColumnsJson(T: TBaseVirtualTree): TJSONArray;
function LWVirtualTreeSelectByPath(T: TBaseVirtualTree; const APath: string): Boolean;

implementation

type
  { Header 在 TLazVirtualStringTree 的 published 段；通过局部派生类读取，
    不改动 VirtualTreeView 源码，也不要求调用方一定是这个精确类型。 }
  TVirtualStringTreeAccess = class(TLazVirtualStringTree);

{ 节点在整棵树里的路径：根节点的兄弟序号.子序号... }
function NodePath(T: TBaseVirtualTree; N: PVirtualNode): string;
begin
  Result := '';
  if N = nil then Exit;
  Result := IntToStr(N^.Index);
  while (N^.Parent <> nil) and (N^.Parent <> T.RootNode) do
  begin
    N := N^.Parent;
    Result := IntToStr(N^.Index) + '.' + Result;
  end;
end;

function NodeJson(T: TBaseVirtualTree; N: PVirtualNode): TJSONObject;
var
  arr, cols: TJSONArray;
  c: PVirtualNode;
  s: string;
  i, colCount: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('id', NodePath(T, N));
  s := '';
  if T is TCustomVirtualStringTree then
    s := TCustomVirtualStringTree(T).Text[N, 0];
  Result.Add('text', s);
  { 多列 VirtualTreeView：每列文本一起下发；单列时 cols 也至少有一项，
    前端据此可统一按 cols 渲染，同时 text 保留给旧版客户端。 }
  cols := TJSONArray.Create;
  colCount := 0;
  if T is TLazVirtualStringTree then
    colCount := TVirtualStringTreeAccess(T).Header.Columns.Count;
  if colCount < 1 then colCount := 1;
  for i := 0 to colCount - 1 do
  begin
    s := '';
    if T is TCustomVirtualStringTree then
      s := TCustomVirtualStringTree(T).Text[N, TColumnIndex(i)];
    cols.Add(s);
  end;
  Result.Add('cols', cols);
  Result.Add('expanded', T.Expanded[N]);
  Result.Add('selected', T.Selected[N]);
  Result.Add('level', Integer(T.GetNodeLevel(N)));
  arr := TJSONArray.Create;
  c := T.GetFirstChild(N);
  while c <> nil do
  begin
    arr.Add(NodeJson(T, c));
    c := T.GetNextSibling(c);
  end;
  Result.Add('children', arr);
end;

function LWVirtualTreeNodesJson(T: TBaseVirtualTree): TJSONArray;
var
  n: PVirtualNode;
begin
  Result := TJSONArray.Create;
  if T = nil then Exit;
  n := T.GetFirst;
  while n <> nil do
  begin
    Result.Add(NodeJson(T, n));
    n := T.GetNextSibling(n);
  end;
end;

function LWVirtualTreeColumnsJson(T: TBaseVirtualTree): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  if not (T is TLazVirtualStringTree) then Exit;
  for i := 0 to TVirtualStringTreeAccess(T).Header.Columns.Count - 1 do
    Result.Add(TVirtualStringTreeAccess(T).Header.Columns[i].Text);
end;

function LWVirtualTreeSelectByPath(T: TBaseVirtualTree; const APath: string): Boolean;
var
  parts: TStringList;
  i, want: Integer;
  n, c: PVirtualNode;
begin
  Result := False;
  if (T = nil) or (APath = '') then Exit;
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := APath;
    if parts.Count = 0 then Exit;
    want := StrToIntDef(parts[0], -1);
    if want < 0 then Exit;
    n := T.GetFirst;
    while (n <> nil) and (Integer(n^.Index) <> want) do
      n := T.GetNextSibling(n);
    if n = nil then Exit;
    for i := 1 to parts.Count - 1 do
    begin
      want := StrToIntDef(parts[i], -1);
      if want < 0 then Exit;
      c := T.GetFirstChild(n);
      while (c <> nil) and (Integer(c^.Index) <> want) do
        c := T.GetNextSibling(c);
      if c = nil then Exit;
      n := c;
    end;
    T.ClearSelection;
    T.Selected[n] := True;
    T.FocusedNode := n;
    Result := True;
  finally
    parts.Free;
  end;
end;

end.
