{ lazarusWeb :: lwdsgntplcore
  ------------------------------------------------------------------
  LFM → 窗体布局模板生成器（纯解析/生成，无 IDE 依赖，可被控制台
  程序单独测试）。由 lwdsgntplgen（设计期 IDE 菜单）调用。

  职责：
    1. ParseLfmText —— 解析 .lfm 文本：窗体名、窗体设计宽、顶层可视
       控件（Name/类名/Left/Top/Width/Height），非可视控件跳过；
    2. GenUnifiedTplEx —— 现行生成器：窗口/平面两种模式统一输出单个
       <窗体名>.html，文件头写 lw-tpl-mode:window|flat 标记决定渲染方式；
       模板只作背景装饰层，控件保持 LFM 的 Left/Top 绝对定位，不重排。

  GenMobileTplEx / GenDesktopTplEx / GenFlatTplEx 是旧版占位符流式模板的
  生成函数，现行 IDE 菜单已不再调用，仅为回归测试保留；新功能请看
  GenUnifiedTplEx。用户拿到骨架后可自由加背景/CSS 装饰（见手册第二篇 16）。

  解析按对象深度 + 集合 item 块 + 括号字符串块三层状态推进，避免
  TListView.Columns 的 end/end> 与多行字符串里的 'end' 误伤对象层级；
  属性只取 Left/Top/Width/Height（模板不含 Caption，只含控件名与类名）。
  ParseLfmTextEx / Gen*Ex 额外返回自检警告，IDE 菜单与生成文件头都显示。 }
unit lwdsgntplcore;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

type
  { lfm 里的一个顶层控件 }
  TTplChild = class
  public
    Name, Cls: string;
    Left, Top, Width, Height: Integer;
    HasKids: Boolean;   { lfm 里带子 object 的容器（TPanel 等），模板要加兜底规则 }
  end;

{ 解析 lfm 文本行。返回 False 表示没解析到窗体对象。
  FormName=窗体对象名；FormWidth=lfm 的 Width（取不到时 800）；
  Children 按视觉顺序（Top 升序、同排按 Left 升序）返回顶层可视控件，
  调用者负责释放（TObjectList 拥有对象）。 }
function ParseLfmText(Lines: TStrings; out FormName: string;
  out FormWidth: Integer; out Children: TObjectList): Boolean;

{ 带自检报告的解析：Warnings 返回跳过的非可视控件、重复/非法占位符名、
  缺失几何、嵌套容器等提示；传入 nil 表示不收集。 }
function ParseLfmTextEx(Lines: TStrings; out FormName: string;
  out FormWidth: Integer; out Children: TObjectList; Warnings: TStrings): Boolean;

{ 该控件类是否应跳过（非可视/由框架单独管理的控件不进模板） }
function IsSkipClass(const Cls: string): Boolean;

{ 生成移动端模板：单列流式，全部占满宽度；FormWidth 用于判定"主区域"
  （占满窗体的大控件按视口伸缩，不写死设计期像素高） }
function GenMobileTpl(const FormName: string; Children: TObjectList;
  FormWidth: Integer): string;
function GenMobileTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;

{ 生成桌面模板：按设计期宽度比例（Width/FormWidth 百分比）flex 换行
  流式排布，保持大致的横向比例关系；窗体几何由框架保持设计期 }
function GenDesktopTpl(const FormName: string; Children: TObjectList;
  FormWidth: Integer): string;
function GenDesktopTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;

{ 【旧版，仅回归测试保留】生成平面模板（标准网页整页）：完整 HTML5 文档，
  body 普通文档流，无浮窗标题/边框/拖动/缩放；用花括号控件名占位符 +
  按设计期高度定高的流式 CSS。现行 IDE 菜单走 GenUnifiedTplEx。 }
function GenFlatTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;

{ 统一模板：窗口/平面两种模式只生成一个 <窗体名>.html，文件头写
  `lw-tpl-mode:window|flat` 标记，客户端按标记决定浮窗或整页渲染。
  模板只作背景装饰层，不再用花括号占位符重排控件；控件始终按 LFM 的
  Left/Top 绝对定位。若文件里同时出现两种标记，flat 优先。 }
function GenUnifiedTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Flat: Boolean; Warnings: TStrings): string;

implementation

{ 尺寸策略辅助（定义在 Gen* 之前，解析阶段的自检也要用它们判定主区域） }
function StackHeight(Children: TObjectList): Integer; forward;
function MainAreaIndex(Children: TObjectList; FormWidth, StackH: Integer): Integer; forward;
function FixedBelowHeight(Children: TObjectList; MainIdx, GapPx: Integer): Integer; forward;

const
  { 跳过的类（大写）。数据源/对话框/菜单/图片列表等非可视控件，以及
    状态栏（框架单独挂在窗体底部，不进模板流） }
  SKIP_CLASSES: array[0..17] of string = (
    'TTIMER', 'TDATASOURCE', 'TMAINMENU', 'TPOPUPMENU', 'TMENUITEM',
    'TACTIONLIST', 'TACTION', 'TACTIONMANAGER',
    'TIMAGELIST', 'TOPENDIALOG', 'TSAVEDIALOG', 'TFONTDIALOG',
    'TCOLORDIALOG', 'TPRINTDIALOG', 'TPRINTERSETUPDIALOG',
    'TLWSIDEMENU', 'TLWREPORT', 'TSTATUSBAR');

  { 会以 .lw-body 承载子控件的容器类（大写）：模板改了它们的宽度后
    内部绝对定位子控件可能溢出，骨架要为它们生成裁剪/收宽兜底规则。
    页签（TPageControl/TTabControl）内容走 pages，不在此列。 }
  BODY_CONTAINERS: array[0..5] of string = (
    'TPANEL', 'TGROUPBOX', 'TRADIOGROUP', 'TCHECKGROUP',
    'TFLOWPANEL', 'TSCROLLBOX');

function IsBodyContainer(const Cls: string): Boolean;
var
  U: string;
  i: Integer;
begin
  U := UpperCase(Trim(Cls));
  for i := Low(BODY_CONTAINERS) to High(BODY_CONTAINERS) do
    if U = BODY_CONTAINERS[i] then
      Exit(True);
  Result := False;
end;

function IsSkipClass(const Cls: string): Boolean;
var
  U: string;
  i: Integer;
begin
  U := UpperCase(Trim(Cls));
  for i := Low(SKIP_CLASSES) to High(SKIP_CLASSES) do
    if U = SKIP_CLASSES[i] then
      Exit(True);
  { 兜底：以 Dialog / ImageList 结尾的通用非可视族 }
  Result := (Length(U) > 6) and (Copy(U, Length(U) - 5, 6) = 'DIALOG') or
            (Length(U) > 9) and (Copy(U, Length(U) - 8, 9) = 'IMAGELIST');
end;

function IsObjStart(const S: string): Boolean;
begin
  Result := (Pos('object ', S) = 1) or (Pos('inline ', S) = 1);
end;

function IsItemStart(const S: string): Boolean;
begin
  Result := (S = 'item') or (Pos('item ', S) = 1);
end;

{ LFM 的集合块用 item ... end / item ... end> 包裹。集合里的 end 不是
  对象结束，必须在这里消化，否则 TListView.Columns 这类属性会把解析深度
  搞乱，后续顶层控件全部丢失（gallery 的 ugallery.lfm 就会触发）。 }
function IsCollectionEnd(const S: string): Boolean;
begin
  Result := (S = 'end') or (S = 'end>') or (S = 'end)');
end;

{ 统计一行里括号深度的净变化，忽略单引号字符串里的括号。
  Lines.Strings = ( ... ) 这类多行字符串里的 'end' 不能当对象结束。 }
function ParenDelta(const S: string): Integer;
var
  i, n: Integer;
  quoted: Boolean;
begin
  Result := 0;
  quoted := False;
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    if S[i] = '''' then
    begin
      if quoted and (i < n) and (S[i + 1] = '''') then
        Inc(i)                       { LFM 里用两个单引号表示一个引号 }
      else
        quoted := not quoted;
    end
    else if not quoted then
    begin
      if S[i] = '(' then Inc(Result)
      else if S[i] = ')' then Dec(Result);
    end;
    Inc(i);
  end;
end;

procedure AddWarn(Warnings: TStrings; const S: string);
begin
  if (Warnings <> nil) and (S <> '') then
    Warnings.Add(S);
end;

function IsIdentName(const S: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if S = '' then Exit;
  if not ((S[1] = '_') or (S[1] >= 'A') and (S[1] <= 'Z') or
          (S[1] >= 'a') and (S[1] <= 'z')) then Exit;
  for i := 2 to Length(S) do
    if not ((S[i] = '_') or (S[i] >= 'A') and (S[i] <= 'Z') or
            (S[i] >= 'a') and (S[i] <= 'z') or
            (S[i] >= '0') and (S[i] <= '9')) then Exit;
  Result := True;
end;

procedure ParseObjHeader(const Line: string; out AName, ACls: string);
var
  p, q: Integer;
  s: string;
begin
  { 行形如：object <Name>: T<Class>（已 trim） }
  AName := '';
  ACls := '';
  s := Line;
  p := Pos('object ', s);
  q := Pos('inline ', s);
  if (q > 0) and ((p = 0) or (q < p)) then
    p := q;
  if p = 0 then
    Exit;
  s := Copy(s, p, MaxInt);                      { 'object Name: TCls' }
  s := Copy(s, Pos(' ', s) + 1, MaxInt);        { 'Name: TCls' }
  q := Pos(':', s);
  if q > 0 then
  begin
    AName := Trim(Copy(s, 1, q - 1));
    ACls := Trim(Copy(s, q + 1, MaxInt));
  end;
end;

function PropInt(const Line: string; const PropName: string;
  out Value: Integer): Boolean;
var
  p, e: Integer;
  sv: string;
begin
  Result := False;
  if Pos(PropName + ' =', Line) <> 1 then
    Exit;
  sv := Trim(Copy(Line, Length(PropName) + 3, MaxInt));
  p := Pos(' ', sv);
  if p > 0 then
    sv := Copy(sv, 1, p - 1);
  Value := 0;
  if TryStrToInt(sv, e) then
  begin
    Value := e;
    Result := True;
  end;
end;

{ 按视觉顺序排：Top 升序，同一排（Top 差 < 24px）按 Left 升序 }
function ChildCompare(Item1, Item2: Pointer): Integer;
var
  a, b: TTplChild;
begin
  a := TTplChild(Item1);
  b := TTplChild(Item2);
  if Abs(a.Top - b.Top) < 24 then
    Result := a.Left - b.Left
  else
    Result := a.Top - b.Top;
end;

function ParseLfmText(Lines: TStrings; out FormName: string;
  out FormWidth: Integer; out Children: TObjectList): Boolean;
var
  W: TStringList;
begin
  W := TStringList.Create;
  try
    Result := ParseLfmTextEx(Lines, FormName, FormWidth, Children, W);
  finally
    W.Free;
  end;
end;

function ParseLfmTextEx(Lines: TStrings; out FormName: string;
  out FormWidth: Integer; out Children: TObjectList; Warnings: TStrings): Boolean;
var
  i, depth, collDepth, parenDepth, delta: Integer;
  s, nm, cl: string;
  c, cur: TTplChild;
  wasInParen: Boolean;
begin
  Result := False;
  FormName := '';
  FormWidth := 800;
  Children := TObjectList.Create(True);
  depth := 0;
  collDepth := 0;
  parenDepth := 0;
  cur := nil;

  for i := 0 to Lines.Count - 1 do
  begin
    s := Trim(Lines[i]);

    { 括号块（字符串列表）整段跳过；'end' 出现在字符串里不算对象结束 }
    wasInParen := parenDepth > 0;
    delta := ParenDelta(s);
    Inc(parenDepth, delta);
    if wasInParen or (parenDepth > 0) then
      Continue;

    { 集合属性块：item ... end / end> 里的 end 与对象无关。
      每个 item 单独计数，end/end> 各消一个 item。 }
    if collDepth > 0 then
    begin
      if IsCollectionEnd(s) then Dec(collDepth);
      Continue;
    end;
    if IsItemStart(s) then
    begin
      Inc(collDepth);
      Continue;
    end;

    if IsObjStart(s) then
    begin
      Inc(depth);
      if depth = 1 then
      begin
        ParseObjHeader(s, nm, cl);
        FormName := nm;
        Result := FormName <> '';
      end
      else if depth = 2 then
      begin
        ParseObjHeader(s, nm, cl);
        cur := TTplChild.Create;
        cur.Name := nm;
        cur.Cls := cl;
      end
      else if (cur <> nil) then
        cur.HasKids := True;               { 容器带子控件，生成兜底 CSS }
      Continue;
    end;

    if s = 'end' then
    begin
      if (depth = 2) and (cur <> nil) then
      begin
        if cur.Name = '' then
        begin
          AddWarn(Warnings, '忽略未命名顶层对象（' + cur.Cls + '）');
          cur.Free;
        end
        else if IsSkipClass(cur.Cls) then
        begin
          AddWarn(Warnings, '跳过非可视控件 ' + cur.Name + ' : ' + cur.Cls);
          cur.Free;
        end
        else
          Children.Add(cur);
        cur := nil;
      end;
      if depth > 0 then Dec(depth);
      Continue;
    end;

    if depth = 1 then
      PropInt(s, 'Width', FormWidth)
    else if (depth = 2) and (cur <> nil) then
    begin
      PropInt(s, 'Left', cur.Left);
      PropInt(s, 'Top', cur.Top);
      PropInt(s, 'Width', cur.Width);
      PropInt(s, 'Height', cur.Height);
    end;
  end;

  cur.Free;                                { lfm 截断时的兜底，不会重复释放 }
  Children.Sort(@ChildCompare);

  { 自检：名字合法、无重复、几何完整；嵌套容器给精修提示 }
  if Warnings <> nil then
  begin
    with TStringList.Create do
    try
      CaseSensitive := False;
      Sorted := False;
      for i := 0 to Children.Count - 1 do
      begin
        c := TTplChild(Children[i]);
        if not IsIdentName(c.Name) then
          AddWarn(Warnings, '占位符名不是合法标识符，客户端可能整体回退: ' + c.Name);
        if IndexOf(c.Name) >= 0 then
          AddWarn(Warnings, '重复的顶层控件名，占位符会互相覆盖: ' + c.Name)
        else
          Add(c.Name);
        if (c.Width <= 0) or (c.Height <= 0) then
          AddWarn(Warnings, '控件 ' + c.Name + ' 缺少有效几何，生成模板按默认高度处理');
        if (FormWidth > 0) and (c.Width > FormWidth) then
          AddWarn(Warnings, '控件 ' + c.Name + ' 设计期宽 ' + IntToStr(c.Width) +
            'px 超过窗体宽 ' + IntToStr(FormWidth) + 'px，模板里会被收进 100%');
        if c.HasKids then
          AddWarn(Warnings, '控件 ' + c.Name + ' : ' + c.Cls +
            ' 含嵌套子控件；模板 v1 只重排顶层，内部需按手册 16.3 精修');
      end;
      { 主区域结论要写进提示：生成结果里那段 calc(100% …) 是推算出来的，
        用户看到"高度和设计期不一样"时得知道为什么 }
      if MainAreaIndex(Children, FormWidth, StackHeight(Children)) >= 0 then
      begin
        c := TTplChild(Children[MainAreaIndex(Children, FormWidth,
          StackHeight(Children))]);
        AddWarn(Warnings, '主区域 ' + c.Name + ' 设计期高 ' + IntToStr(c.Height) +
          'px 接近窗体高，模板按容器高度伸缩（calc(100% - 其它控件高度)）');
      end;
      AddWarn(Warnings, '生成占位符 ' + IntToStr(Children.Count) +
        ' 个；运行时控件名不一致会导致该窗体整体回退设计期布局');
    finally
      Free;
    end;
  end;
end;

function TplCommentEx(const FormName, Kind: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;
var
  i: Integer;
  c: TTplChild;
begin
  Result :=
    '<!--' + sLineBreak +
    '  ' + FormName + ' 的' + Kind + '布局模板 —— 由 lwdesign 的 IDE' + sLineBreak +
    '  Tools 菜单「生成 lazarusWeb 窗体模板」自动生成（起始骨架）。' + sLineBreak +
    '  {%控件名%} 由浏览器端替换成该控件的既有 DOM 节点：搬迁不重建，' + sLineBreak +
  '  事件与增量补丁照旧。占位符引用不存在的控件名时整体回退设计期布局。' + sLineBreak +
  '  本文件由 /lw/tpl/ 路由按文件名静态下发（no-store），' + sLineBreak +
    '  改动刷新即生效，无需重编译。放置目录：<运行根目录>\tpl\。' + sLineBreak +
    '  模板 v1 只重排窗体顶层控件；容器内部仍是绝对定位，精修方法见' + sLineBreak +
    '  docs/MANUAL.md 第二篇 16.3（常用 CSS 钩子表）。' + sLineBreak +
    '  顶层控件清单（lfm 解析，按视觉顺序）：';
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    Result := Result + sLineBreak + '    ' + c.Name + ' : ' + c.Cls +
      '  (' + IntToStr(c.Left) + ',' + IntToStr(c.Top) + ' ' +
      IntToStr(c.Width) + 'x' + IntToStr(c.Height) + ')';
  end;
  if (Kind = '桌面') and (FormWidth > 0) then
    Result := Result + sLineBreak + '  桌面模板宽度比例基准：窗体 Width=' +
      IntToStr(FormWidth);
  if Warnings <> nil then
  begin
    Result := Result + sLineBreak + '  自检提示（IDE 菜单同步显示）：';
    for i := 0 to Warnings.Count - 1 do
      Result := Result + sLineBreak + '  ! ' + Warnings[i];
  end;
  Result := Result + sLineBreak + '-->' + sLineBreak;
end;

function TplComment(const FormName, Kind: string; Children: TObjectList;
  FormWidth: Integer): string;
begin
  Result := TplCommentEx(FormName, Kind, Children, FormWidth, nil);
end;

{ 带子控件的顶层容器的兜底规则（坑 155）：
  模板 v1 只重排窗体顶层，容器内部仍是设计期绝对定位；模板把容器宽度
  改变后（桌面按百分比、移动改单列），内部控件按设计期 px 定的 left/width
  可能溢出容器 —— LCL 里 TPanel 本来就裁剪子控件，这里按同一语义兜底，
  要重排内部控件时按手册 16.3 精修。

  页签（TPageControl/TTabControl）不在此列：客户端 .lw-tabs 自己
  `height:100%` + flex 列，.lw-tabs-body `flex:1; min-height:0`，
  .lw-tabcard 绝对定位铺满并 `overflow:hidden` —— 页内容已被裁剪，
  再叠一条兜底只会和这套布局打架。 }

{ ---------------- 尺寸策略辅助 ----------------

  设计期几何是"窗体多大就画多大"的像素值；直接搬进模板会在这几处出错：
    · 主区域（gallery 的 pcMain 1800x900 / 窗体 1800x1110）写死 900px ——
      720p 窗口里底部日志条被顶出可视区，手机上要滚一屏才看得到页签之外
      的内容；
    · 桌面侧 `flex: 0 0 50%` + `gap: 10px`，两个半宽控件加起来
      100%+10px 超过一行 → 该并排的控件被挤成上下两行；
    · 扣减量按"每个控件的高度直接相加"算，在 wrap 布局里会重复扣同一行
      其它控件的高度（dbaware 报表窗顶排 6 个控件就在一行）。
  所以：① 纵向过半且横向基本占满的那个控件按容器高度伸缩；② 百分比宽度
  一律扣掉 gap；③ 桌面侧扣减量按行算。

  注意容器是 `.lw-tpl`（窗体客户区），不是视口：窗体开在浮窗里时客户区
  只有视口的一部分（dbaware 主窗体实测 720 vs 900），用 100vh 排版会
  整块溢出 —— 见坑 164。 }

{ 设计期纵向占用高度：max(Top+Height)。取不到时退化为最高的控件 }
function StackHeight(Children: TObjectList): Integer;
var
  i: Integer;
  c: TTplChild;
begin
  Result := 0;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    if c.Top + c.Height > Result then
      Result := c.Top + c.Height;
  end;
end;

{ 主区域判定：横向 ≥85% 窗体宽、纵向 ≥50% 纵向占用，且窗体本身有高度。
  只认最高的那一个（并列取视觉顺序靠前者），避免两个控件同时 calc 打架。 }
function MainAreaIndex(Children: TObjectList; FormWidth, StackH: Integer): Integer;
var
  i: Integer;
  c: TTplChild;
begin
  Result := -1;
  if (FormWidth <= 0) or (StackH < 300) then Exit;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    if (c.Width >= FormWidth * 0.85) and (c.Height >= StackH * 0.5) then
    begin
      if (Result < 0) or (c.Height > TTplChild(Children[Result]).Height) then
        Result := i;
    end;
  end;
end;

{ 主区域之外那些控件的固定高度合计 + 每个间隙（gap） }
function FixedBelowHeight(Children: TObjectList; MainIdx, GapPx: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to Children.Count - 1 do
    if i <> MainIdx then
      Inc(Result, TTplChild(Children[i]).Height);
  if Children.Count > 1 then
    Inc(Result, GapPx * (Children.Count - 1));
  if Result < 0 then
    Result := 0;
end;

{ 主区域的视口高度表达式。
  fixedH = 0 说的是"窗体顶层只有这一个控件"（dbaware 主窗体只有一个铺满的
  TPageControl 就是这种），此时 calc(100% - 0px) 能算对但读起来像漏填，
  直接在生成物里写成 100%，改模板的人一眼就知道没扣任何东西。 }
function MainAreaHeightExpr(FixedH: Integer): string;
begin
  if FixedH <= 0 then
    Result := '100%'
  else
    Result := 'calc(100% - ' + IntToStr(FixedH) + 'px)';
end;

{ 主区域上面的注释里那句"扣掉其它控件 Npx"，fixedH=0 时换个说法 }
function MainAreaNote(FixedH: Integer): string;
begin
  if FixedH <= 0 then
    Result := '窗体顶层只有它一个控件，直接吃满容器'
  else
    Result := '按容器高度伸缩（扣掉其它控件 ' + IntToStr(FixedH) + 'px）';
end;

{ 桌面 wrap 布局下"其它控件占掉多少纵向空间"必须按浏览器实际换行结果算：
  同一行里的控件只在纵向占一份高度，且一行能塞下的前提是宽度合计不超 100%。
    · 逐个控件高度直加（旧算法）：ReportForm 顶排 6 个控件会被重复扣 5 份，
      主区域压到 min-height，整页比设计期还高；
    · 只按 Top 差值分行：ReportForm 的 lblInfo(84) 与 lblHint(104) 差 20px，
      会被并成一行，于是少扣一行的高度，主区域高出 18px 把底部顶出去。
  所以按"宽度能不能再塞一个 + 纵向是否还站在同一行"贪心分行，行的判定阈值
  与 ChildCompare 的 24px 一致。 }
function RowsFixedHeight(Children: TObjectList; MainIdx, FormWidth, GapPx,
  BandPx: Integer): Integer;
var
  i, pct, rowPct, rowTop, rowH, rows: Integer;
  c: TTplChild;
begin
  Result := 0;
  if FormWidth <= 0 then
    FormWidth := 800;
  rowPct := 0;
  rowTop := 0;
  rowH := 0;
  rows := 0;
  for i := 0 to Children.Count - 1 do
  begin
    if i = MainIdx then Continue;          { 主区域自己占一行，不参与扣减 }
    c := TTplChild(Children[i]);
    pct := Round(c.Width / FormWidth * 100);
    if pct < 8 then
      pct := 8;
    if pct > 100 then
      pct := 100;
    if (rows > 0) and (rowPct + pct <= 100) and (Abs(c.Top - rowTop) < BandPx) then
    begin
      Inc(rowPct, pct);
      if c.Height > rowH then
        rowH := c.Height;                  { 同一行取最高的那个 }
    end
    else
    begin
      if rows > 0 then
        Inc(Result, rowH);
      Inc(rows);
      rowTop := c.Top;
      rowH := c.Height;
      rowPct := pct;
    end;
  end;
  if rows > 0 then
  begin
    Inc(Result, rowH);
    Inc(Result, GapPx * rows);              { 主区域那行与其它行之间的间隙 }
  end;
  if Result < 0 then
    Result := 0;
end;

function ContainerRules(const K: string; Children: TObjectList): string;
var
  i: Integer;
  c: TTplChild;
begin
  Result := '';
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    if c.HasKids and IsBodyContainer(c.Cls) then
      Result := Result +
        '  /* 容器 ' + c.Name + ' (' + c.Cls + ') 内部仍是设计期绝对定位' + sLineBreak +
        '     （模板 v1 只重排顶层）；容器被模板改宽后内部控件可能溢出，' + sLineBreak +
        '     这里按 LCL 语义（容器裁剪子控件）兜底，重排内部见手册 16.3 */' + sLineBreak +
        '  ' + K + ' [data-lw-ph="' + c.Name + '"] > .lw-n > .lw-body' +
        ' { overflow: hidden; }' + sLineBreak +
        '  ' + K + ' [data-lw-ph="' + c.Name + '"] .lw-body .lw-n' +
        ' { max-width: calc(100% - 16px); }' + sLineBreak;
  end;
end;

function GenMobileTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;
var
  i, stackH, mainIdx, fixedH: Integer;
  c: TTplChild;
  K: string;
begin
  K := '.tpl-' + LowerCase(FormName);
  if FormWidth <= 0 then
    FormWidth := 800;
  stackH := StackHeight(Children);
  mainIdx := MainAreaIndex(Children, FormWidth, stackH);
  fixedH := FixedBelowHeight(Children, mainIdx, 10);
  Result := TplCommentEx(FormName, '移动端', Children, 0, Warnings) + sLineBreak;
  Result := Result +
    '<style>' + sLineBreak +
    '  /* 单列流式：占位符占满一行；控件宽 100%，高按设计期值' + sLineBreak +
    '     （搬迁会清掉内联宽高，必须在这里逐个定高，否则容器塌陷）；' + sLineBreak +
    '     占满窗体的大控件例外 —— 它按容器高度伸缩，见下方"主区域"规则。' + sLineBreak +
    '     根节点 height:100% 取自 .lw-tpl（它是窗体客户区，可能只有视口的' + sLineBreak +
    '     一部分：窗体开在浮窗里时 100vh 会多算一截，见坑 164）*/' + sLineBreak +
    '  ' + K + ' { display: flex; flex-direction: column; gap: 10px;' + sLineBreak +
    '              height: 100%; box-sizing: border-box; }' + sLineBreak +
    '  ' + K + ' > .lw-ph { margin: 0; flex: 0 0 auto; }' + sLineBreak +
    '  ' + K + ' > .lw-ph > .lw-n { width: 100% !important; }' + sLineBreak +
    '  /* 面板/页签内容层随包装层撑满；需要贴边精修见手册 16.3 */' + sLineBreak +
    '  ' + K + ' > .lw-ph > .lw-n > .lw-body,' + sLineBreak +
    '  ' + K + ' > .lw-ph > .lw-n > .lw-memo {' + sLineBreak +
    '      width: 100% !important; height: 100% !important; }' + sLineBreak;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    if i = mainIdx then
    begin
      { 主区域：原设计高 + 其它控件固定高 ≤ 窗体客户区高，等价于"吃掉剩余
        高度"。写死像素会在矮窗口里顶出其它控件、在手机/浮窗里多滚一屏，
        故按容器高度算，再留一个下限防止极端窄屏压成一条线。 }
      Result := Result +
        '  /* 主区域 ' + c.Name + '：设计期 ' + IntToStr(c.Height) + 'px ≈ 窗体高，' + sLineBreak +
        '     ' + MainAreaNote(fixedH) + '，矮屏也不会把它挤出屏幕 */' + sLineBreak +
        '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] { height: ' + MainAreaHeightExpr(fixedH) + ';' + sLineBreak +
        '                          min-height: 240px; }' + sLineBreak +
        '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] > .lw-n { height: 100% !important; }' + sLineBreak;
    end
    else if c.Height > 0 then
      Result := Result + '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] > .lw-n { height: ' + IntToStr(c.Height) + 'px !important; }' + sLineBreak;
  end;
  Result := Result + ContainerRules(K, Children) + '</style>' + sLineBreak +
    '<div class="' + Copy(K, 2, MaxInt) + '">' + sLineBreak;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    Result := Result + '  {%' + c.Name + '%}' +
      ' <!-- ' + c.Cls + ' -->' + sLineBreak;
  end;
  Result := Result + '</div>' + sLineBreak;
end;

function GenMobileTpl(const FormName: string; Children: TObjectList;
  FormWidth: Integer): string;
begin
  Result := GenMobileTplEx(FormName, Children, FormWidth, nil);
end;

function GenDesktopTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;
var
  i, pct, stackH, mainIdx, fixedH: Integer;
  c: TTplChild;
  K: string;
begin
  K := '.tpl-' + LowerCase(FormName);
  if FormWidth <= 0 then
    FormWidth := 800;
  stackH := StackHeight(Children);
  mainIdx := MainAreaIndex(Children, FormWidth, stackH);
  { 桌面是 wrap 流式：纵向空间按行占用，所以扣减要按行算（见 RowsFixedHeight） }
  fixedH := RowsFixedHeight(Children, mainIdx, FormWidth, 10, 24);
  Result := TplCommentEx(FormName, '桌面', Children, FormWidth, Warnings) + sLineBreak;
  Result := Result +
    '<style>' + sLineBreak +
    '  /* 流式换行：每个占位符按设计期宽度比例（Width/' + IntToStr(FormWidth) +
    '）取百分比宽，' + sLineBreak +
    '     近似保持横向布局关系；可自由改成双栏/卡片等。' + sLineBreak +
    '     根节点 height:100% 取自 .lw-tpl（窗体客户区高度），主区域据此伸缩 */' +
    sLineBreak +
    '  ' + K + ' { display: flex; flex-wrap: wrap; gap: 10px;' + sLineBreak +
    '              align-items: flex-start; height: 100%;' + sLineBreak +
    '              box-sizing: border-box; }' + sLineBreak +
    '  ' + K + ' > .lw-ph { margin: 0; box-sizing: border-box; }' + sLineBreak +
    '  ' + K + ' > .lw-ph > .lw-n { width: 100% !important; }' + sLineBreak +
    '  /* 面板/页签内容层随包装层撑满 */' + sLineBreak +
    '  ' + K + ' > .lw-ph > .lw-n > .lw-body,' + sLineBreak +
    '  ' + K + ' > .lw-ph > .lw-n > .lw-memo {' + sLineBreak +
    '      width: 100% !important; height: 100% !important; }' + sLineBreak;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    pct := Round(c.Width / FormWidth * 100);
    if pct < 8 then
      pct := 8;
    if pct > 100 then
      pct := 100;
    { 百分比宽要扣掉 flex gap：`flex: 0 0 50%` 配 `gap: 10px` 时
      50%+50%+10px 超过一行，本该并排的两个控件会被换行 }
    if pct >= 95 then
      Result := Result + '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] { flex: 0 0 100%; }' + sLineBreak
    else
      Result := Result + '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] { flex: 0 0 calc(' + IntToStr(pct) + '% - 10px); }' + sLineBreak;
    if i = mainIdx then
    begin
      Result := Result +
        '  /* 主区域 ' + c.Name + '：设计期 ' + IntToStr(c.Height) + 'px ≈ 窗体高，' + sLineBreak +
        '     ' + MainAreaNote(fixedH) + ' */' + sLineBreak +
        '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] { height: ' + MainAreaHeightExpr(fixedH) + ';' + sLineBreak +
        '                          min-height: 240px; }' + sLineBreak +
        '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] > .lw-n { height: 100% !important; }' + sLineBreak;
    end
    else if c.Height > 0 then
      Result := Result + '  ' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] > .lw-n { height: ' + IntToStr(c.Height) + 'px !important; }' + sLineBreak;
  end;
  Result := Result + ContainerRules(K, Children) + '</style>' + sLineBreak +
    '<div class="' + Copy(K, 2, MaxInt) + '">' + sLineBreak;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    Result := Result + '  {%' + c.Name + '%}' +
      ' <!-- ' + c.Cls + ' -->' + sLineBreak;
  end;
  Result := Result + '</div>' + sLineBreak;
end;

function GenDesktopTpl(const FormName: string; Children: TObjectList;
  FormWidth: Integer): string;
begin
  Result := GenDesktopTplEx(FormName, Children, FormWidth, nil);
end;

function GenFlatTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Warnings: TStrings): string;
var
  i: Integer;
  c: TTplChild;
  K: string;
begin
  K := 'tpl-flat-' + LowerCase(FormName);
  if FormWidth <= 0 then
    FormWidth := 800;

  Result :=
    '<!DOCTYPE html>' + sLineBreak +
    '<!--' + sLineBreak +
    '  ' + FormName + ' 的平面（整页网页）布局模板 —— 由 lwdesign 的 IDE' + sLineBreak +
    '  Tools 菜单「生成 lazarusWeb 窗体模板」选择平面模式后生成（起始骨架）。' + sLineBreak +
    '  独立 HTML5 文档：body 普通文档流、页面自身滚动，不带窗口标题/边框，' + sLineBreak +
    '  不可拖动或调整大小（如需浮窗请改用窗口模式生成的桌面/移动模板）。' + sLineBreak +
    '  {%控件名%} 与现有模板一致：浏览器端把它换成该控件的既有 DOM 节点，' + sLineBreak +
    '  事件与增量补丁照旧；占位符引用不存在的控件名时无法完成替换。' + sLineBreak +
    '  设计期窗体宽 ' + IntToStr(FormWidth) + 'px 仅作参考：整页宽度由 CSS 的' + sLineBreak +
    '  max-width 控制，控件高度沿用设计期值以防搬迁后容器塌陷。' + sLineBreak +
    '  顶层控件清单（lfm 解析，按视觉顺序）：';
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    Result := Result + sLineBreak + '    ' + c.Name + ' : ' + c.Cls +
      '  (' + IntToStr(c.Left) + ',' + IntToStr(c.Top) + ' ' +
      IntToStr(c.Width) + 'x' + IntToStr(c.Height) + ')';
  end;
  if Warnings <> nil then
  begin
    Result := Result + sLineBreak +
      '  自检提示（IDE 菜单同步显示；其中主区域伸缩一句只针对窗口模板，' + sLineBreak +
      '  平面模板一律沿用设计期高度）：';
    for i := 0 to Warnings.Count - 1 do
      Result := Result + sLineBreak + '  ! ' + Warnings[i];
  end;
  Result := Result + sLineBreak + '-->' + sLineBreak;

  Result := Result +
    '<html lang="zh-CN">' + sLineBreak +
    '<head>' + sLineBreak +
    '  <meta charset="utf-8">' + sLineBreak +
    '  <meta name="viewport" content="width=device-width, initial-scale=1">' + sLineBreak +
    '  <title>' + FormName + ' · lazarusWeb 平面模板</title>' + sLineBreak +
    '  <style>' + sLineBreak +
    '    /* 平面模式：普通网页布局，内容超过视口时由页面自身滚动；' + sLineBreak +
    '       不依赖浮窗客户区高度，也不用 calc(100% - ...) 抢高度。 */' + sLineBreak +
    '    html, body { margin: 0; padding: 0; min-height: 100%; }' + sLineBreak +
    '    /* 颜色用主题变量 + 浅色兜底：模板会随客户端主题（米色/深色/深蓝夜色…）' + sLineBreak +
    '       一起变，写死 #f5f7fa 会导致所有主题下都是同一块浅色底（坑 182）。 */' + sLineBreak +
    '    body { background: var(--lw-win-bg, #f5f7fa); color: var(--lw-fg, #2b3a49);' + sLineBreak +
    '           font-family: "Microsoft YaHei", "PingFang SC", "Segoe UI", Arial, sans-serif; }' + sLineBreak +
    '    .' + K + ' { max-width: 1080px; margin: 0 auto; padding: 16px 24px 32px;' + sLineBreak +
    '                box-sizing: border-box; display: flex; flex-direction: column;' + sLineBreak +
    '                gap: 12px; }' + sLineBreak +
    '    .' + K + ' > .lw-ph { margin: 0; flex: 0 0 auto; box-sizing: border-box; }' + sLineBreak +
    '    .' + K + ' > .lw-ph > .lw-n { width: 100% !important; }' + sLineBreak +
    '    /* 面板/页签/备忘录的内容层随包装层撑满 */' + sLineBreak +
    '    .' + K + ' > .lw-ph > .lw-n > .lw-body,' + sLineBreak +
    '    .' + K + ' > .lw-ph > .lw-n > .lw-memo {' + sLineBreak +
    '      width: 100% !important; height: 100% !important; }' + sLineBreak;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    if c.Height > 0 then
      Result := Result + '    .' + K + ' > .lw-ph[data-lw-ph="' + c.Name +
        '"] > .lw-n { height: ' + IntToStr(c.Height) + 'px !important; }' + sLineBreak;
  end;
  Result := Result + ContainerRules('.' + K, Children) +
    '  </style>' + sLineBreak +
    '</head>' + sLineBreak +
    '<body>' + sLineBreak +
    '<div class="' + K + '">' + sLineBreak;
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    Result := Result + '  {%' + c.Name + '%}' +
      ' <!-- ' + c.Cls + ' -->' + sLineBreak;
  end;
  Result := Result + '</div>' + sLineBreak +
    '</body>' + sLineBreak +
    '</html>' + sLineBreak;
end;

function GenUnifiedTplEx(const FormName: string; Children: TObjectList;
  FormWidth: Integer; Flat: Boolean; Warnings: TStrings): string;
var
  i: Integer;
  c: TTplChild;
  K, ModeName, ModeText, Note: string;
begin
  if Flat then
  begin
    ModeName := 'flat';
    ModeText := '平面模式（整页网页：无标题栏/边框/拖动/缩放）';
    Note := '整页宽高由浏览器视口决定，页面自身滚动';
  end
  else
  begin
    ModeName := 'window';
    ModeText := '窗口模式（现有浮窗：可移动、可调整大小）';
    Note := '窗体几何仍由框架按设计期保持';
  end;
  K := 'tpl-' + LowerCase(FormName) + '-' + ModeName;
  if FormWidth <= 0 then
    FormWidth := 800;

  Result := '';
  if Flat then
    Result := '<!DOCTYPE html>' + sLineBreak;
  Result := Result +
    '<!-- lw-tpl-mode:' + ModeName + ' -->' + sLineBreak +
    '<!--' + sLineBreak +
    '  ' + FormName + ' 的' + ModeText + '模板 —— 由 lwdesign 的 IDE' + sLineBreak +
    '  Tools 菜单「生成 lazarusWeb 窗体模板」生成（起始骨架）。' + sLineBreak +
    '  每个端一个文件：桌面 <窗体名>.html、移动 <窗体名>.m.html，均为装饰层；' + sLineBreak +
    '  文件头的 lw-tpl-mode 决定浏览器按浮窗还是整页渲染。两种标记并存时 flat 优先。' + sLineBreak +
    '  本模板只作背景/装饰层：不重排控件、不使用花括号控件名占位符。' + sLineBreak +
    '  控件继续由框架按 LFM 的 Left/Top 绝对定位，' + Note + '。' + sLineBreak +
    '  可在下面 <style> 与 <div> 里加背景、花纹、说明文字等装饰；' + sLineBreak +
    '  装饰层 pointer-events:none，不拦截控件事件。' + sLineBreak +
    '  设计期窗体宽 ' + IntToStr(FormWidth) + 'px。' + sLineBreak +
    '  顶层控件清单（lfm 解析，设计期坐标供参考）：';
  for i := 0 to Children.Count - 1 do
  begin
    c := TTplChild(Children[i]);
    Result := Result + sLineBreak + '    ' + c.Name + ' : ' + c.Cls +
      '  (left=' + IntToStr(c.Left) + ', top=' + IntToStr(c.Top) +
      ', ' + IntToStr(c.Width) + 'x' + IntToStr(c.Height) + ')';
  end;
  if Children.Count = 0 then
    Result := Result + sLineBreak + '    （空窗体：只有装饰层，没有顶层可视控件）';
  if Warnings <> nil then
  begin
    Result := Result + sLineBreak + '  自检提示（IDE 菜单同步显示）：';
    for i := 0 to Warnings.Count - 1 do
      if Pos('生成占位符', Warnings[i]) = 0 then   { 统一模板不用占位符 }
        Result := Result + sLineBreak + '  ! ' + Warnings[i];
  end;
  Result := Result + sLineBreak + '-->' + sLineBreak;

  if Flat then
    Result := Result + '<html lang="zh-CN">' + sLineBreak + '<head>' + sLineBreak;
  Result := Result + '<style>' + sLineBreak +
    '  /* 装饰层：铺满窗体客户区/整页，控件仍是客户的绝对定位子节点。 */' + sLineBreak;
  if Flat then
    Result := Result +
      '  html, body { margin: 0; padding: 0; min-height: 100%; }' + sLineBreak;
  Result := Result +
    '  .' + K + ' { position: absolute; left: 0; top: 0; right: 0; bottom: 0;' + sLineBreak +
    '              box-sizing: border-box; pointer-events: none;';
  if Flat then
    Result := Result + sLineBreak +
      '              /* 背景/字体放在装饰层类上，不用 body 全局选择器：' + sLineBreak +
      '                 模板经 innerHTML 注入宿主页面，body 规则会污染同页其它窗体 */' + sLineBreak +
      '              /* 颜色跟随客户端主题（var 取宿主页 :root 上的主题变量），' + sLineBreak +
      '                 写死固定色会让所有主题都显示同一块浅底（坑 182） */' + sLineBreak +
      '              background: var(--lw-win-bg, #f5f7fa); color: var(--lw-fg, #2b3a49);' + sLineBreak +
      '              font-family: "Microsoft YaHei", "PingFang SC", "Segoe UI", Arial, sans-serif;';
  Result := Result + ' }' + sLineBreak +
    '  </style>' + sLineBreak;
  if Flat then
    Result := Result + '</head>' + sLineBreak + '<body>' + sLineBreak;
  Result := Result + '<div class="' + K + '"></div>' + sLineBreak;
  if Flat then
    Result := Result + '</body>' + sLineBreak + '</html>' + sLineBreak;
end;

end.
