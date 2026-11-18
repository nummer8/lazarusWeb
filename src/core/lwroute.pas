{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: lwroute
  ------------------------------------------------------------------
  进程级插件路由：插件是独立 exe（一个完整的 lazarusWeb 服务，自己监听
  自己的端口），主框架把 /p/<插件名>/... 反向代理到对应上游。

  为什么是"独立 exe + HTTP 路由"而不是 DLL：
    - FPC 的 RTL/LCL 静态链接进每个模块，跨 DLL 边界 is 判断恒 False 且
      静默失败（实测见 docs/PLUGIN_FEASIBILITY.md §3）；
    - 进程边界天然跨平台（每个平台编自己的可执行文件）、故障隔离最好；
    - 插件页面就是普通 lazarusWeb 页面：长轮询是唯一推送通道，WebSocket
      只管事件加速且可缺省 —— 所以纯 HTTP 代理就能承载完整交互。
      （WebSocket 经代理暂不透传：前端 WS 连不上会自动回退 POST 事件 +
      长轮询，每 2 秒重试一次，无功能损失，只有约 1KB/2s 的重试流量。）

  配置（主框架 exe 同名 ini，命令行参数优先级更高）：
      plugin.notes=127.0.0.1:8871
      plugin.dashboard=127.0.0.1:8872
  键名 plugin.<插件名>=<host:port>（也可写完整 http://URL，尾部 '/' 剥掉）。

  约定：
    - 浏览器访问 /p/notes/ -> 上游 /（GET /p/notes 补尾斜杠 301，保证
      页面内相对路径解析正确）；
    - 转发时加 X-Forwarded-For / X-Forwarded-Prefix 头；插件的外壳 HTML
      读 X-Forwarded-Prefix 把 /lw/... 资源 URL 生成到 /p/<名>/ 前缀下；
    - 除 /p/ 前缀外不动任何现有路由，没配插件时零开销。
}
unit lwroute;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, fphttpserver, httpdefs, httpprotocol,
  fphttpclient, lwbase, lwrlog;

type
  { LWRouteDispatch 的结果：handled=True 表示响应已写好（成功或已回错误），
    调用方直接 Exit；False 表示路径不是 /p/ 前缀（调用方继续自己的路由） }
  TLWRouteHandled = (rrNotPlugin, rrDone, rrNoUpstream, rrUpstreamFail);

{ 登记/查询插件。AUpstream 归一化为 'host:port'（剥 http:// 与尾斜杠） }
procedure LWRouteSet(const AName, AUpstream: string);
procedure LWRouteRemove(const AName: string);
function LWRouteGet(const AName: string; out AUpstream: string): Boolean;
{ 逗号分隔的插件名清单（注册表为空返回 ''） }
function LWRouteNames: string;

{ /p/<名>/<框架静态资源> -> 本地路径（宿主直出）；非框架静态资源返回 ''。
  框架运行时（客户端 JS/CSS、alpine.min.js、favicon、Ext 资源）属于
  非业务功能，由主程序统一直出：升级只换宿主一处、插件部署不用带这些
  文件；插件 exe 只收业务请求（页面外壳、/lw/api/*、/lw/ajax/*、模板） }
function LWRouteStaticLocal(const APath: string): string;

{ 主框架路由入口：APath 是已去掉查询串的请求路径。
  返回 rrDone = 响应已写好；其余情形调用方按语义回 404/502 或继续路由。 }
function LWRouteDispatch(ARequest: TFPHTTPConnectionRequest;
  AResponse: TFPHTTPConnectionResponse; const APath: string): TLWRouteHandled;

implementation

type
  { 插件注册表。读多写少（启动后基本只读），进程闸门保护 }
  TLWRouteTable = class
  private
    FLock: TCriticalSection;
    FItems: TStringList;   { 'name=http://host:port'，name 已小写 }
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetItem(const AName, AUpstream: string);
    procedure RemoveItem(const AName: string);
    function GetItem(const AName: string; out AUpstream: string): Boolean;
    function Names: string;
  end;

var
  GTable: TLWRouteTable = nil;

const
  LW_PLUGIN_PREFIX = '/p/';

function GetTable: TLWRouteTable;
begin
  if GTable = nil then
    GTable := TLWRouteTable.Create;
  Result := GTable;
end;

{ 浏览器请求（Accept 含 text/html）？Accept 走双位置读取：先查 TRequest.Accept
  标准字段（3.3.1 常见头在 Headers 里），查不到再退 CustomHeaders（3.2.2
  未映射头的存放点）—— 与 lwhttp.LWReqHeader 同思路，只看一个位置会漏 }
function WantsHTML(ARequest: TFPHTTPConnectionRequest): Boolean;
var
  acc: string;
begin
  acc := Trim(ARequest.Accept);
  if acc = '' then
    acc := Trim(ARequest.CustomHeaders.Values['Accept']);
  Result := Pos('text/html', LowerCase(acc)) > 0;
end;

{ hop-by-hop 头：代理必须剥掉（RFC 7230 6.1）+ 由两端各自生成的头。
  与 lwhyper.IsHopByHop 同语义（那边是实现段私有，这边独立成套） }
function IsHopByHop(const AName: string): Boolean;
begin
  Result :=
    SameText(AName, 'connection') or SameText(AName, 'keep-alive') or
    SameText(AName, 'transfer-encoding') or SameText(AName, 'te') or
    SameText(AName, 'trailer') or SameText(AName, 'upgrade') or
    SameText(AName, 'proxy-connection') or SameText(AName, 'expect') or
    SameText(AName, 'host') or SameText(AName, 'content-length');
end;

{ 插件名只放行 URL 安全字符（注册表键与 URL 段共用） }
function ValidPluginName(const AName: string): Boolean;
var
  i: Integer;
  c: Char;
begin
  Result := False;
  if (Length(AName) < 1) or (Length(AName) > 64) then Exit;
  for i := 1 to Length(AName) do
  begin
    c := AName[i];
    if not ( ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
             ((c >= '0') and (c <= '9')) or (c = '-') or (c = '_') or (c = '.') ) then
      Exit;
  end;
  Result := True;
end;

{ 'http://127.0.0.1:8871/' -> '127.0.0.1:8871'；'127.0.0.1:8871' 原样 }
function NormUpstream(const AValue: string): string;
var
  v: string;
begin
  Result := '';
  v := Trim(AValue);
  if v = '' then Exit;
  if Copy(LowerCase(v), 1, 7) = 'http://' then
    Delete(v, 1, 7)
  else if Copy(LowerCase(v), 1, 8) = 'https://' then
  begin
    LWLog('警告: 插件上游不支持 https://（进程间走本机/内网 HTTP），剥掉协议: ' + v);
    Delete(v, 1, 8);
  end;
  while (Length(v) > 0) and ((v[Length(v)] = '/') or (v[Length(v)] = '\')) do
    Delete(v, Length(v), 1);
  if v = '' then Exit;
  Result := v;
end;

{ ---------------- TLWRouteTable ---------------- }

constructor TLWRouteTable.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TStringList.Create;
  FItems.NameValueSeparator := '=';
end;

destructor TLWRouteTable.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TLWRouteTable.SetItem(const AName, AUpstream: string);
var
  k: string;
  idx: Integer;
begin
  k := LowerCase(AName);
  FLock.Enter;
  try
    idx := FItems.IndexOfName(k);
    if idx >= 0 then
      FItems[idx] := k + '=' + AUpstream
    else
      FItems.Add(k + '=' + AUpstream);
  finally
    FLock.Leave;
  end;
end;

procedure TLWRouteTable.RemoveItem(const AName: string);
var
  k: string;
  idx: Integer;
begin
  k := LowerCase(AName);
  FLock.Enter;
  try
    { 不要在持锁状态下调 GetItem —— 它也会加锁，Linux 的 pthread 互斥量
      不可重入，嵌套加锁直接死锁 }
    idx := FItems.IndexOfName(k);
    if idx >= 0 then
      FItems.Delete(idx);
  finally
    FLock.Leave;
  end;
end;

function TLWRouteTable.GetItem(const AName: string; out AUpstream: string): Boolean;
var
  k, v: string;
  idx: Integer;
begin
  Result := False;
  AUpstream := '';
  k := LowerCase(AName);
  FLock.Enter;
  try
    idx := FItems.IndexOfName(k);
    if idx >= 0 then
    begin
      v := FItems.ValueFromIndex[idx];
      if v <> '' then
      begin
        AUpstream := v;
        Result := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TLWRouteTable.Names: string;
var
  i: Integer;
begin
  Result := '';
  FLock.Enter;
  try
    for i := 0 to FItems.Count - 1 do
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + FItems.Names[i];
    end;
  finally
    FLock.Leave;
  end;
end;

{ ---------------- 公开 API ---------------- }

procedure LWRouteSet(const AName, AUpstream: string);
var
  up: string;
begin
  if not ValidPluginName(AName) then
  begin
    LWLog('警告: 插件名非法（只允许字母数字 .-_，1..64 位）: ' + AName);
    Exit;
  end;
  up := NormUpstream(AUpstream);
  if up = '' then
  begin
    LWLog('警告: 插件上游为空，忽略: ' + AName);
    Exit;
  end;
  GetTable.SetItem(AName, up);
  LWLog('插件路由: /p/' + AName + '/ -> http://' + up + '/');
end;

procedure LWRouteRemove(const AName: string);
begin
  GetTable.RemoveItem(AName);
end;

function LWRouteGet(const AName: string; out AUpstream: string): Boolean;
begin
  Result := GetTable.GetItem(AName, AUpstream);
end;

function LWRouteNames: string;
begin
  Result := GetTable.Names;
end;

{ 框架静态资源白名单：宿主直出，不进插件（非业务功能由主程序处理）。
  会话绑定类端点（/lw/api/*、/lw/ajax/*、验证码、/lw/tpl/ 模板）不在
  此列 —— 状态在插件会话里，必须代理回插件 }
function LWRouteStaticLocal(const APath: string): string;
const
  STATIC_ASSETS: array[0..4] of string = (
    '/lw/lw.js', '/lw/lw.css', '/lw/lw-alpine.js', '/lw/lw-alpine.css',
    '/lw/alpine.min.js');
var
  rest: string;
  slash, i: Integer;
begin
  Result := '';
  if Copy(APath, 1, Length(LW_PLUGIN_PREFIX)) <> LW_PLUGIN_PREFIX then
    Exit;
  rest := Copy(APath, Length(LW_PLUGIN_PREFIX) + 1, MaxInt);
  slash := Pos('/', rest);
  if slash <= 0 then
    Exit;                                    { /p/<名> 无尾斜杠：交给代理补 301 }
  rest := Copy(rest, slash, MaxInt);         { 含开头 '/' }
  if rest = '/favicon.ico' then
    Exit('/favicon.ico');
  if Copy(rest, 1, 5) = '/ext/' then
    Exit(rest);
  for i := Low(STATIC_ASSETS) to High(STATIC_ASSETS) do
    if rest = STATIC_ASSETS[i] then
      Exit(rest);
end;

{ 反向代理：把 ARequest 原样转发到 http://AUpstream+AUpPath（含查询串），
  响应搬运回 AResponse。写法与 lwhyper.ProxyHTTP 同源：
  头/体透传、hop-by-hop 剥离、请求体原始字节不动（multipart 二进制安全）。 }
function ProxyTo(ARequest: TFPHTTPConnectionRequest;
  AResponse: TFPHTTPConnectionResponse;
  const AUpstream, AUpPath, AForwardedPrefix: string): Boolean;
var
  clt: TFPHTTPClient;
  body, ms: TMemoryStream;
  i, n, q: Integer;
  name, val, ct: string;
  url: string;
begin
  Result := False;
  clt := TFPHTTPClient.Create(nil);
  body := nil;
  ms := TMemoryStream.Create;
  try
    clt.AllowRedirect := False;
    { Windows 上 connection refused 被当超时处理，缺省烧 3 秒 ——
      本机转发 connect 毫秒级完成，1 秒足够宽裕 }
    clt.ConnectTimeout := 1000;
    { 长轮询 /lw/api/poll 服务端最多挂 20s（LW_POLL_MS），30s 宽裕 }
    clt.IOTimeout := 30000;

    { 请求头透传（剥 hop-by-hop） }
    for i := 0 to ARequest.CustomHeaders.Count - 1 do
    begin
      name := ARequest.CustomHeaders.Names[i];
      val := Trim(ARequest.CustomHeaders.Values[name]);
      if val = '' then Continue;
      if IsHopByHop(name) then Continue;
      clt.RequestHeaders.Add(name + ': ' + val);
    end;
    clt.RequestHeaders.Values['X-Forwarded-For'] := ARequest.RemoteAddress;
    clt.RequestHeaders.Values['X-Forwarded-Prefix'] := AForwardedPrefix;

    { 请求体透传（原始字节）。3.3.1 在 ContentBytes，3.2.2 在 Content }
    {$IF FPC_FULLVERSION >= 30301}
    if Length(ARequest.ContentBytes) > 0 then
    begin
      body := TMemoryStream.Create;
      body.WriteBuffer(ARequest.ContentBytes[0], Length(ARequest.ContentBytes));
      body.Position := 0;
      clt.RequestBody := body;
    end;
    {$ELSE}
    if Length(ARequest.Content) > 0 then
    begin
      body := TMemoryStream.Create;
      body.WriteBuffer(ARequest.Content[1], Length(ARequest.Content));
      body.Position := 0;
      clt.RequestBody := body;
    end;
    {$ENDIF}

    url := 'http://' + AUpstream + AUpPath;
    { query string 必须透传：Route 为匹配路径把 ?... 去掉了，但 poll/tree/ajax
      全靠 query 传 sid/t/after/form —— 丢了上游 Find('')=nil 就回 gone，
      前端 forgetSid+boot 反复重建，表现为"会话已过期"无限闪 }
    q := Pos('?', ARequest.URL);
    if q > 0 then
      url := url + Copy(ARequest.URL, q, MaxInt);   { 含开头 '?' }
    try
      clt.HTTPMethod(ARequest.Method, url, ms, []);
    except
      on E: Exception do
      begin
        LWLog('[route] ' + url + ' 转发失败: ' + E.Message);
        FreeAndNil(ms);
        Exit;
      end;
    end;
    Result := True;   { 上游已应答，后续只是搬运 }

    { 响应头透传（剥 hop-by-hop 与 fphttpserver 自己生成的头）。
      content-length 不抄：ContentStream 赋值时框架自动按流大小设置 }
    AResponse.Code := clt.ResponseStatusCode;
    {$IF FPC_FULLVERSION >= 30301}
    AResponse.CodeText := GetHTTPStatusText(clt.ResponseStatusCode);
    {$ELSE}
    AResponse.CodeText := LWHTTPStatusText(clt.ResponseStatusCode);
    {$ENDIF}
    n := clt.ResponseHeaders.Count - 1;
    for i := 0 to n do
    begin
      name := clt.ResponseHeaders.Names[i];
      val := Trim(clt.ResponseHeaders.Values[name]);
      if val = '' then Continue;
      if IsHopByHop(name) then Continue;
      if SameText(name, 'server') or SameText(name, 'date') or
         SameText(name, 'content-type') or SameText(name, 'content-length') then
        Continue;
      AResponse.CustomHeaders.Add(name + ': ' + val);
    end;
    ct := clt.ResponseHeaders.Values['content-type'];
    if ct = '' then ct := 'application/octet-stream';
    AResponse.ContentType := ct;

    if (clt.ResponseStatusCode = 204) or (clt.ResponseStatusCode = 304) or
       (ms.Size = 0) then
    begin
      AResponse.Content := '';
      Exit;
    end;
    ms.Position := 0;
    AResponse.ContentStream := ms;
    AResponse.FreeContentStream := True;
    ms := nil;   { 所有权移交给响应对象 }
  finally
    ms.Free;
    body.Free;
    clt.Free;
  end;
end;

function LWRouteDispatch(ARequest: TFPHTTPConnectionRequest;
  AResponse: TFPHTTPConnectionResponse; const APath: string): TLWRouteHandled;
var
  rest, name, up, prefix: string;
  slash: Integer;
begin
  Result := rrNotPlugin;
  if Copy(APath, 1, Length(LW_PLUGIN_PREFIX)) <> LW_PLUGIN_PREFIX then
    Exit;

  rest := Copy(APath, Length(LW_PLUGIN_PREFIX) + 1, MaxInt);
  slash := Pos('/', rest);
  if slash > 0 then
  begin
    name := Copy(rest, 1, slash - 1);
    rest := Copy(rest, slash, MaxInt);          { 含开头 '/' }
  end
  else
  begin
    name := rest;
    rest := '/';                                 { /p/notes -> 上游 / }
  end;

  if not ValidPluginName(name) then
  begin
    AResponse.Code := 404;
    AResponse.CodeText := 'Not Found';
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := '404 invalid plugin name';
    Result := rrDone;
    Exit;
  end;
  if not LWRouteGet(name, up) then
  begin
    AResponse.Code := 404;
    AResponse.CodeText := 'Not Found';
    if WantsHTML(ARequest) then
    begin
      AResponse.ContentType := 'text/html; charset=utf-8';
      AResponse.Content :=
        '<!DOCTYPE html><html><head><meta charset="utf-8">' +
        '<title>未登记插件: ' + name + '</title></head><body ' +
        'style="font-family:sans-serif;background:#1e1e1e;color:#ddd;' +
        'margin:0;padding:48px 24px">' +
        '<h2 style="color:#f66;margin:0 0 16px">没有名为「' + name + '」的插件</h2>' +
        '<p>宿主 ini 里加一行 <code>plugin.' + name + '=host:port</code> 指向该' +
        '插件 exe 的监听地址，然后重启宿主。已登记：' + LWRouteNames + '</p>' +
        '</body></html>';
    end
    else
    begin
      AResponse.ContentType := 'text/plain; charset=utf-8';
      AResponse.Content := '404 no plugin named "' + name +
        '"（主框架 ini 里加 plugin.' + name + '=host:port 后重启）';
    end;
    Result := rrNoUpstream;
    Exit;
  end;

  { /p/notes（无尾斜杠）补 301：页面内相对路径（BASE 推导）依赖尾斜杠 }
  if (rest = '/') and (ARequest.URL <> '') and
     (Copy(ARequest.URL, Length(ARequest.URL), 1) <> '/') and
     (Pos('?', ARequest.URL) = 0) then
  begin
    AResponse.Code := 301;
    AResponse.CodeText := 'Moved Permanently';
    AResponse.SetCustomHeader('Location', LW_PLUGIN_PREFIX + name + '/');
    AResponse.Content := '';
    Result := rrDone;
    Exit;
  end;

  prefix := LW_PLUGIN_PREFIX + name + '/';
  if ProxyTo(ARequest, AResponse, up, rest, prefix) then
    Result := rrDone
  else
  begin
    { 上游连不上（最常见：插件 exe 没启动）。浏览器请求（Accept 含
      text/html）回人可读的 HTML 错误页，API/程序调用仍回 JSON ——
      裸 JSON 在浏览器页签里就是一行代码，运维不知道该干什么 }
    AResponse.Code := 502;
    AResponse.CodeText := 'Bad Gateway';
    if WantsHTML(ARequest) then
    begin
      AResponse.ContentType := 'text/html; charset=utf-8';
      AResponse.Content :=
        '<!DOCTYPE html><html><head><meta charset="utf-8">' +
        '<title>插件不可达: ' + name + '</title></head><body ' +
        'style="font-family:sans-serif;background:#1e1e1e;color:#ddd;' +
        'margin:0;padding:48px 24px">' +
        '<h2 style="color:#f66;margin:0 0 16px">插件「' + name + '」未启动或不可达</h2>' +
        '<p>宿主已按登记把本页代理到 <code>' + up + '</code>，但连接失败。</p>' +
        '<p>最常见原因：<b>插件 exe 没有运行</b>（或正在重启）。请启动对应插件' +
        '程序后<a href="" onclick="location.reload();return false" ' +
        'style="color:#6cf">刷新本页</a>。</p>' +
        '<p style="color:#999;font-size:13px">宿主 ini 键：plugin.' + name + '=' +
        up + '</p></body></html>';
    end
    else
    begin
      AResponse.ContentType := 'application/json; charset=utf-8';
      AResponse.Content := '{"ok":false,"err":"plugin unreachable: ' + name + '"}';
    end;
    Result := rrUpstreamFail;
  end;
end;

finalization
  FreeAndNil(GTable);
end.
