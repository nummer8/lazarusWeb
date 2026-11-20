{
  lazarusWeb :: lwlang
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  ------------------------------------------------------------------
  多语言运行时（Lazarus / gettext PO 模式）。

  设计要点：
   - 复用 LCL 自带的 Translations 单元（TPOFile），不自己解析 PO 文件；
     目录布局也按 LCL 约定：<exe目录>\languages\<lang>\<域>.po。
   - **中文原文即 msgid**：翻译表里 msgid 就是界面上的中文，msgstr 是译文。
     TPOFile.Translate 先按资源名、找不到再按"原文值"匹配，所以服务端任何
     一处输出（窗体 Caption、对话框、外壳文案）都能在输出边界上查表，
     不需要把几千个字面量改写成 resourcestring，也不需要给每条起名字。
   - 两个域分开：
       lazarusweb.po  服务端产出的一切界面文本
       lwclient.po    浏览器端 JS 自己的文案（启动时注入 window.__LW_LANG）
   - 语言是**按会话**的：会话变量 lwlang（?lwlang=en / cookie 写入）。
     因为翻译发生在"输出那一刻"而不是"建窗体那一刻"，同一进程里中英文
     会话可以并存 —— 这正是 uniGUI 那种"一个 exe 服务多个客户"的形态需要的。
   - 找不到翻译就原样返回中文（gettext 的标准降级行为），不会出现空白。
}
unit lwlang;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Translations, lwbase
  {$IFDEF MSWINDOWS}, Windows{$ENDIF};

const
  LW_LANG_ZH = 'zh';
  LW_LANG_EN = 'en';
  { 翻译域（= PO 文件名去掉扩展名）}
  LW_PO_SERVER = 'lazarusweb';
  LW_PO_CLIENT = 'lwclient';
  { 会话里存语言的变量名 }
  LW_SESSION_LANG = 'lwlang';

{ 'zh-CN' / 'zh_CN' / 'EN-us' -> 'zh' / 'en'；不认识的返回 '' }
function LWLangNormalize(const S: string): string;
{ 系统界面语言：走 Lazarus 的 Translations.GetLanguageID（Windows 用
  GetUserDefaultLCID + GetLocaleInfo，其它平台看 LC_ALL/LC_MESSAGES/LANG，
  macOS 看 AppleLocale）。中文系统 -> 'zh'，其它 -> 'en'（只带这两套译文）。
  取不到时返回 ''，调用方再决定兜底（内置 zh）。 }
function LWLangSystem: string;
{ 当前语言：会话里有就用会话的，否则用请求级（?lwlang= / cookie），
  再否则用进程默认（ini/命令行）}
function LWLangGet: string;
{ 请求级语言。lwhttp 在每次请求入口按 ?lwlang= / X-LW-Lang / cookie 设置；
  空串 = 清掉（不影响进程默认）。外壳页在会话建立之前就要出对应语言，
  所以这一层是必需的。 }
procedure LWLangSetRequest(const ACode: string);
function LWLangDefault: string;
procedure LWLangSetDefault(const ACode: string);
{ 支持的语言清单（逗号分隔），给 /lw/api/lang 与启动日志用 }
function LWLangAvailable: string;
{ 语言目录：<root>\languages，找不到时向上最多 4 级、再看 exe 目录。
  不存在返回 ''（此时所有 LWLangText 原样返回中文）}
function LWLangDir(const ARoot: string): string;
{ 是否已具备可用的翻译（目录存在且该语言有 po 文件）}
function LWLangReady(const ALang: string): Boolean;

{ 按当前语言翻译一条服务端文本。ALang 为空 = 当前语言。
  没有翻译、或语言是中文，都原样返回。 }
function LWLangText(const S: string): string;
function LWLangTextIn(const ALang, S: string): string;
{ 带占位符的翻译：把格式串当 msgid 先翻译，再 Format —— 控制台横幅/日志这种
  "固定文案 + 变量" 的行必须走这条，否则整行匹配不上 PO。 }
function LWLangFmt(const AFmt: string; const Args: array of const): string;
{ 一行日志/控制台文本的翻译：跳过时间戳（'hh:nn:ss  '）和级别前缀
  （'[info] ' / '[warn] '），只翻正文 —— PO 里存的就是正文。
  前缀原样保留，所以排障时仍能一眼看出级别。 }
function LWLangLine(const ALine: string): string;
{ 浏览器端字典（JSON 对象，键是中文原文、值是译文）。只含 lwclient 域，
  启动时注入 window.__LW_LANG.t，JS 用 lwT('中文') 取。 }
function LWLangJsonFor(const ALang: string; const ARoot: string): string;
{ 把 S 作为 msgid 在浏览器域里翻译（用于服务端外壳里直接写死的少量文案）}
function LWLangTextC(const S: string): string;

{ 启动时调用一次：解析要用的语言并预热 PO。ARoot 为项目根/exe 目录。
  返回实际生效的语言。 }
function LWLangInit(const AWanted, ARoot: string): Boolean;

implementation

type
  TLangSlot = record
    Code: string;
    Ready: Boolean;
    Server: TPOFile;    { lazarusweb.po }
    Client: TPOFile;    { lwclient.po }
    ClientJson: string; { 缓存好的 JS 字典 }
  end;

var
  GSlots: array[0..1] of TLangSlot;
  GDefault: string = LW_LANG_ZH;
  GDir: string = '';
  GDirTried: Boolean = False;

threadvar
  { 请求级语言（见 LWLangSetRequest）。线程本地：一个进程多个请求线程
    同时服务不同语言的会话时互不干扰 }
  LWReqLang: string;

procedure LWLangSetRequest(const ACode: string);
begin
  LWReqLang := LWLangNormalize(ACode);
end;

function LangIndex(const ACode: string): Integer;
begin
  if ACode = LW_LANG_EN then Result := 1 else Result := 0;
end;

function LWLangNormalize(const S: string): string;
var
  v: string;
begin
  v := LowerCase(Trim(S));
  { 只取主语言段：en-US / en_US / en.UTF-8 -> en }
  if (v <> '') and (v[1] = 'z') then
  begin
    if (Pos('zh', v) = 1) or (Pos('chinese', v) = 1) then Exit(LW_LANG_ZH);
  end;
  if Pos('en', v) = 1 then Exit(LW_LANG_EN);
  { 也认中文名，配置文件里写"英文"更直观 }
  if (v = '英文') or (v = 'english') then Exit(LW_LANG_EN);
  if (v = '中文') or (v = 'chinese') or (v = '简体中文') then Exit(LW_LANG_ZH);
  Result := '';
end;

function LWLangSystem: string;

  function IsChineseCode(const AC: string): Boolean;
  begin
    { Windows 的 LOCALE_SISO639LANGNAME 一般是 'zh'，个别语言包会返回
      'CHS'/'CHT'；这里都认，免得中文系统被判成英文 }
    Result := (Pos('zh', AC) = 1) or (AC = 'chs') or (AC = 'cht') or
      (Pos('chinese', AC) = 1);
  end;

var
  c: string;
begin
  c := '';
  try
    { Lazarus 的做法：Windows 用 GetUserDefaultLCID + GetLocaleInfo，
      其它平台读 LC_ALL / LC_MESSAGES / LANG，macOS 读 AppleLocale }
    c := LowerCase(Trim(GetLanguageID.LanguageCode));
  except
    c := '';
  end;
  if IsChineseCode(c) then Exit(LW_LANG_ZH);
  {$IFDEF MSWINDOWS}
  { 双保险：UI 语言的主语言 ID（LCID 低 10 位）0x04 = 中文。
    GetLocaleInfo 在某些精简系统上可能返回空，这一步几乎不会失手。 }
  if (GetUserDefaultLCID and $3FF) = $04 then Exit(LW_LANG_ZH);
  {$ENDIF}
  { 非中文系统一律给英文：只带 zh/en 两套译文，给英文比给中文有用 }
  if c <> '' then Exit(LW_LANG_EN);
  Result := '';
end;

function LWLangDefault: string;
begin
  Result := GDefault;
end;

procedure LWLangSetDefault(const ACode: string);
var
  c: string;
begin
  c := LWLangNormalize(ACode);
  if c <> '' then GDefault := c;
end;

function LWLangAvailable: string;
begin
  Result := LW_LANG_ZH + ',' + LW_LANG_EN;
end;

function LWLangGet: string;
var
  v: string;
begin
  if LWCurrentSession <> nil then
  begin
    v := LWCurrentSession.SessionGetVar(LW_SESSION_LANG);
    if v <> '' then
    begin
      v := LWLangNormalize(v);
      if v <> '' then Exit(v);
    end;
  end;
  if LWReqLang <> '' then Exit(LWReqLang);
  Result := GDefault;
end;

{ 找 languages 目录。ARoot 通常是 exe 目录；开发期 demo 的 exe 在
  demos\<名>\ 下，PO 放在仓库根的 languages\ 里，所以要向上找。
  结果进程内缓存一次（运行期目录不会变）。 }
function LWLangDir(const ARoot: string): string;

  function HasLangSub(const ADir: string): Boolean;
  begin
    Result := DirectoryExists(ADir) and
      (DirectoryExists(IncludeTrailingPathDelimiter(ADir) + LW_LANG_EN) or
       FileExists(IncludeTrailingPathDelimiter(ADir) + LW_LANG_EN +
         PathDelim + LW_PO_SERVER + '.po'));
  end;

var
  d, up: string;
  i: Integer;
begin
  if GDirTried then Exit(GDir);
  GDirTried := True;
  GDir := '';
  { 1) <root>\languages }
  d := IncludeTrailingPathDelimiter(ARoot);
  if HasLangSub(d + 'languages') then
  begin
    GDir := d + 'languages';
    Exit(GDir);
  end;
  { 2) 从 root 向上最多 4 级（demos\x\ -> 仓库根）}
  up := d;
  for i := 1 to 4 do
  begin
    up := ExcludeTrailingPathDelimiter(ExtractFileDir(ExcludeTrailingPathDelimiter(up)));
    if up = '' then Break;
    if HasLangSub(IncludeTrailingPathDelimiter(up) + 'languages') then
    begin
      GDir := IncludeTrailingPathDelimiter(up) + 'languages';
      Exit(GDir);
    end;
    { 走到盘符根就停 }
    if ExtractFileDir(ExcludeTrailingPathDelimiter(up)) = '' then Break;
  end;
  { 3) exe 目录（部署时 exe 旁带 languages\，而 Root 指向别处）}
  d := IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));
  if HasLangSub(d + 'languages') then
  begin
    GDir := d + 'languages';
    Exit(GDir);
  end;
  { 4) Windows 下再试一次带盘符的当前目录 }
  d := IncludeTrailingPathDelimiter(GetCurrentDir);
  if HasLangSub(d + 'languages') then
    GDir := d + 'languages';
  Result := GDir;
end;

function LWLangReady(const ALang: string): Boolean;
var
  base, code: string;
begin
  Result := False;
  code := LWLangNormalize(ALang);
  if code = '' then Exit;
  if code = LW_LANG_ZH then Exit(True);  { 中文 = 原文，永远可用 }
  base := LWLangDir(ExtractFileDir(ParamStr(0)));
  if base = '' then Exit(False);
  base := IncludeTrailingPathDelimiter(base) + code + PathDelim;
  Result := FileExists(base + LW_PO_SERVER + '.po') or
    FileExists(base + LW_PO_CLIENT + '.po');
end;

{ 惰性加载某个语言的 PO。失败就记 nil（只尝试一次，避免每帧刷盘）}
procedure SlotLoad(AIdx: Integer);
var
  base, fn: string;
  slot: TLangSlot;
begin
  slot := GSlots[AIdx];
  if slot.Ready then Exit;
  slot.Code := LW_LANG_ZH;
  if AIdx = 1 then slot.Code := LW_LANG_EN;
  slot.Ready := True;   { 先标记：加载失败也不要反复尝试 }
  { 中文是原文，不需要 PO }
  if slot.Code = LW_LANG_ZH then
  begin
    GSlots[AIdx] := slot;
    Exit;
  end;
  base := LWLangDir(ExtractFileDir(ParamStr(0)));
  if base = '' then
  begin
    GSlots[AIdx] := slot;
    Exit;
  end;
  base := IncludeTrailingPathDelimiter(base) + slot.Code + PathDelim;
  fn := base + LW_PO_SERVER + '.po';
  if FileExists(fn) then
  try
    slot.Server := TPOFile.Create(fn);
  except
    slot.Server := nil;
  end;
  fn := base + LW_PO_CLIENT + '.po';
  if FileExists(fn) then
  try
    slot.Client := TPOFile.Create(fn);
  except
    slot.Client := nil;
  end;
  GSlots[AIdx] := slot;
end;

function SlotOf(const ALang: string): Integer;
var
  code: string;
begin
  code := LWLangNormalize(ALang);
  if code = '' then code := LW_LANG_ZH;
  Result := LangIndex(code);
  SlotLoad(Result);
end;

function LWLangTextIn(const ALang, S: string): string;
var
  idx: Integer;
  po: TPOFile;
begin
  Result := S;
  if S = '' then Exit;
  idx := SlotOf(ALang);
  if GSlots[idx].Code = LW_LANG_ZH then Exit;
  po := GSlots[idx].Server;
  if po = nil then Exit;
  try
    Result := po.Translate('', S);
    { 拼接片段在 PO 里是以去掉首尾空格的形态存的（'共 ' -> '共'），
      精确匹配失败时按 trim 再查一次 }
    if (Result = S) and (Trim(S) <> S) then
      Result := po.Translate('', Trim(S));
  except
    Result := S;
  end;
  if Result = '' then Result := S;
end;

function LWLangText(const S: string): string;
begin
  Result := LWLangTextIn(LWLangGet, S);
end;

function LWLangFmt(const AFmt: string; const Args: array of const): string;
var
  tpl: string;
begin
  if AFmt = '' then Exit('');
  tpl := LWLangText(AFmt);
  { 没有占位符就别过 Format：文案里自带 % 的时候 Format 会抛异常 }
  if Pos('%', tpl) = 0 then Exit(tpl);
  try
    Result := Format(tpl, Args);
  except
    { 译文把 %s 写坏了：宁可退回中文格式串，也不要让启动横幅炸掉 }
    try
      Result := Format(AFmt, Args);
    except
      Result := tpl;
    end;
  end;
end;

function LWLangLine(const ALine: string): string;
var
  p: Integer;
  head, body: string;
begin
  Result := LWLangText(ALine);
  if Result <> ALine then Exit;      { 整行命中（不带前缀）}
  head := '';
  body := ALine;
  { 日志出口会先加 'hh:nn:ss  '，这一截不是正文 }
  if (Length(body) > 12) and (body[3] = ':') and (body[6] = ':') and
     (body[9] = ' ') and (body[10] = ' ') then
  begin
    head := Copy(body, 1, 10);
    body := Copy(body, 11, MaxInt);
  end;
  { '[info] xxx' / '[warn] xxx'：级别前缀保留，只翻正文 }
  if (body <> '') and (body[1] = '[') then
  begin
    p := Pos('] ', body);
    if p > 1 then
    begin
      head := head + Copy(body, 1, p + 1);
      body := Copy(body, p + 2, MaxInt);
    end;
  end;
  if body = '' then Exit(ALine);
  Result := head + LWLangText(body);
end;

function LWLangTextC(const S: string): string;
var
  idx: Integer;
  po: TPOFile;
begin
  Result := S;
  if S = '' then Exit;
  idx := SlotOf(LWLangGet);
  if GSlots[idx].Code = LW_LANG_ZH then Exit;
  po := GSlots[idx].Client;
  if po = nil then Exit;
  try
    Result := po.Translate('', S);
    { 拼接片段在 PO 里是以去掉首尾空格的形态存的（'共 ' -> '共'），
      精确匹配失败时按 trim 再查一次 }
    if (Result = S) and (Trim(S) <> S) then
      Result := po.Translate('', Trim(S));
  except
    Result := S;
  end;
  if Result = '' then Result := S;
end;

function JsonEsc(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(c) < 32 then
        Result := Result + '\u' + IntToHex(Ord(c), 4)
      else
        Result := Result + c;
    end;
  end;
end;

function LWLangJsonFor(const ALang: string; const ARoot: string): string;
var
  idx, i: Integer;
  po: TPOFile;
  it: TPOFileItem;
  sb: TStringList;
  first: Boolean;
begin
  if ARoot <> '' then LWLangDir(ARoot);
  idx := SlotOf(ALang);
  if GSlots[idx].ClientJson <> '' then Exit(GSlots[idx].ClientJson);
  po := GSlots[idx].Client;
  if (po = nil) or (GSlots[idx].Code = LW_LANG_ZH) then
  begin
    GSlots[idx].ClientJson := '{}';
    Exit('{}');
  end;
  sb := TStringList.Create;
  try
    sb.LineBreak := '';
    sb.Add('{');
    first := True;
    for i := 0 to po.Count - 1 do
    begin
      it := po.PoItems[i];
      if (it = nil) or (it.Original = '') then Continue;
      if (it.Translation = '') then Continue;
      { fuzzy / badformat 的条目不采用：格式串对不上会让前端显示 %s }
      if (Pos('fuzzy', it.Flags) > 0) or (Pos('badformat', it.Flags) > 0) then Continue;
      if not first then sb.Add(',');
      first := False;
      sb.Add('"' + JsonEsc(it.Original) + '":"' + JsonEsc(it.Translation) + '"');
    end;
    sb.Add('}');
    GSlots[idx].ClientJson := sb.Text;
  finally
    sb.Free;
  end;
  Result := GSlots[idx].ClientJson;
end;

function LWLangInit(const AWanted, ARoot: string): Boolean;
var
  code: string;
begin
  Result := False;
  if ARoot <> '' then LWLangDir(ARoot);
  code := LWLangNormalize(AWanted);
  if code = '' then
  begin
    { 没指定（或写了个不认识的代码）= 跟随系统语言 }
    code := LWLangSystem;
    if code = '' then code := LW_LANG_ZH;
  end;
  GDefault := code;
  if code = LW_LANG_ZH then Exit(True);
  SlotLoad(LangIndex(code));
  Result := (GSlots[LangIndex(code)].Server <> nil) or
    (GSlots[LangIndex(code)].Client <> nil);
end;

initialization
  GSlots[0].Code := LW_LANG_ZH;
  GSlots[1].Code := LW_LANG_EN;

finalization
  if GSlots[0].Server <> nil then GSlots[0].Server.Free;
  if GSlots[0].Client <> nil then GSlots[0].Client.Free;
  if GSlots[1].Server <> nil then GSlots[1].Server.Free;
  if GSlots[1].Client <> nil then GSlots[1].Client.Free;

end.
