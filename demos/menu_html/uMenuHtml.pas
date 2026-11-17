{
  lazarusWeb :: menu_html
  ------------------------------------------------------------------
  做法二：左侧菜单是 TLWHTMLFrame 里的自定义 HTML + Alpine.js，
  右侧是**真实的 LCL 控件**（TPageControl + 编辑框 + 下拉框 + TStringGrid）。
  演示 HTML 菜单与 LCL 控件的双向联动：

    菜单点击 -> $lwFireByName('edtMenuKey','OnChange', "val:key")
             -> 服务端 edtMenuKeyChange -> 切 pcMain.ActivePage
             -> 事件响应带回整棵树，浏览器里的 LCL 页签立刻切换

    LCL 查询按钮 -> 服务端填 TStringGrid / 改状态标签
                -> 同一次响应里重建 frame 的 HTML，左侧菜单高亮与
                   状态栏（"共 N 条"）跟着更新（LCL -> HTML 方向）

    直接点浏览器里的 LCL 页签 -> pcMain.OnChange -> 服务端
             -> 重建菜单 HTML，左侧高亮跟上（两个方向都同步）

  帧里的脚本拿不到控件 id（id 由服务端序列化时分配），所以用框架提供的
  $lwFireByName(控件名, 事件名, 附加参数) —— 见 src/client/lw-alpine.js。

  渲染层：Alpine.js，工程目录下 menu_html.ini 里 Client=alpine，不加载 Ext JS。
}
unit uMenuHtml;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Grids,
  lwform, lwweb;

type

  { TMenuHtmlForm }

  TMenuHtmlForm = class(TLWForm)
    pnlTop: TPanel;
    lblGreeting: TLabel;
    hfMenu: TLWHTMLFrame;
    pcMain: TPageControl;
    tsSignup: TTabSheet;
    lblName: TLabel;
    edtName: TEdit;
    lblYear: TLabel;
    cboYear: TComboBox;
    btnSignupQuery: TButton;
    lblSignupStatus: TLabel;
    sgSignup: TStringGrid;
    tsScore: TTabSheet;
    lblScoreName: TLabel;
    edtScoreName: TEdit;
    btnScoreQuery: TButton;
    lblScoreStatus: TLabel;
    sgScore: TStringGrid;
    tsStat: TTabSheet;
    btnStat: TButton;
    lblStatStatus: TLabel;
    sgStat: TStringGrid;
    tsSchedule: TTabSheet;
    mmoNotice: TMemo;
    btnDownload: TButton;
    lblDlStatus: TLabel;
    tsOther: TTabSheet;
    lblOther: TLabel;
    edtMenuKey: TEdit;
    procedure FormCreate(Sender: TObject);
    procedure edtMenuKeyChange(Sender: TObject);
    procedure pcMainChange(Sender: TObject);
    procedure btnSignupQueryClick(Sender: TObject);
    procedure btnScoreQueryClick(Sender: TObject);
    procedure btnStatClick(Sender: TObject);
    procedure btnDownloadClick(Sender: TObject);
  private
    FActiveKey: string;
    FStatus: string;
    procedure ApplyKey(const AKey: string);
    procedure RefreshMenu;
    function BuildMenuHtml: string;
  public
  end;

var
  MenuHtmlForm: TMenuHtmlForm;

implementation

uses
  fpjson;

{$R *.lfm}

const
  { 没有对应业务页的菜单项落到"其他功能"页 }
  PAGE_OTHER = 4;

  { 以下姓名、公司、证件号、电话均为虚构的示例数据，仅用于演示界面 }
  SIGNUP_NAMES: array[0..5] of string =
    ('张一凡', '李思远', '陈嘉禾', '赵子墨', '孙可欣', '周立诚');
  SIGNUP_COMPANIES: array[0..5] of string =
    ('深圳市正衡工程检测有限公司', '深圳市远川建筑工程检测有限公司',
     '深圳市正衡工程检测有限公司', '深圳市正衡工程检测有限公司',
     '深圳市远川建筑工程检测有限公司', '深圳市正衡工程检测有限公司');
  SIGNUP_IDS: array[0..5] of string =
    ('4403**********0017', '4403**********2231', '4401**********5566',
     '4301**********8890', '4403**********3372', '6101**********4415');
  SIGNUP_PHONES: array[0..5] of string =
    ('138****2201', '139****8812', '137****6631', '135****9027',
     '136****4418', '188****7735');
  SIGNUP_STATES: array[0..5] of string =
    ('已审核', '已审核', '待审核', '已审核', '待审核', '已审核');

function PageOfKey(const AKey: string): Integer;
begin
  if AKey = 'theory.signup' then Result := 0
  else if AKey = 'theory.score' then Result := 1
  else if AKey = 'theory.stat' then Result := 2
  else if AKey = 'theory.schedule' then Result := 3
  else Result := PAGE_OTHER;
end;

function KeyOfPage(APage: Integer): string;
begin
  case APage of
    0: Result := 'theory.signup';
    1: Result := 'theory.score';
    2: Result := 'theory.stat';
    3: Result := 'theory.schedule';
  else
    Result := 'other';
  end;
end;

function TitleOfKey(const AKey: string): string;
begin
  if AKey = 'theory.signup' then Result := '报名查询'
  else if AKey = 'theory.score' then Result := '成绩查询'
  else if AKey = 'theory.stat' then Result := '成绩统计'
  else if AKey = 'theory.schedule' then Result := '考试安排表下载'
  else if AKey = 'exam.plan' then Result := '考试计划'
  else if AKey = 'exam.room' then Result := '考场安排'
  else if AKey = 'exam.inv' then Result := '监考人员'
  else if AKey = 'qual.ent' then Result := '企业资质'
  else if AKey = 'qual.cert' then Result := '人员证书'
  else Result := '其他功能';
end;

{ ---------------- 窗体 ---------------- }

procedure TMenuHtmlForm.FormCreate(Sender: TObject);
begin
  { 隐藏桥接控件：HTML 菜单点击后把 key 写进它，走标准事件通道 }
  edtMenuKey.Text := 'theory.signup';

  pcMain.ActivePageIndex := 0;

  { 表格表头是设计期固定内容，数据由查询按钮填 }
  sgSignup.ColCount := 6;
  sgSignup.FixedRows := 1;
  sgSignup.FixedCols := 0;
  sgSignup.RowCount := 2;
  sgSignup.Cells[0, 0] := '姓名';
  sgSignup.Cells[1, 0] := '公司名称';
  sgSignup.Cells[2, 0] := '身份证号';
  sgSignup.Cells[3, 0] := '手机号';
  sgSignup.Cells[4, 0] := '状态';
  sgSignup.Cells[5, 0] := '考试年份';

  sgScore.ColCount := 5;
  sgScore.FixedRows := 1;
  sgScore.FixedCols := 0;
  sgScore.RowCount := 2;
  sgScore.Cells[0, 0] := '公司名称';
  sgScore.Cells[1, 0] := '姓名';
  sgScore.Cells[2, 0] := '科目';
  sgScore.Cells[3, 0] := '考试日期';
  sgScore.Cells[4, 0] := '成绩';

  sgStat.ColCount := 4;
  sgStat.FixedRows := 1;
  sgStat.FixedCols := 0;
  sgStat.RowCount := 2;
  sgStat.Cells[0, 0] := '公司名称';
  sgStat.Cells[1, 0] := '科目';
  sgStat.Cells[2, 0] := '总人数';
  sgStat.Cells[3, 0] := '通过人数';

  ApplyKey('theory.signup');
end;

procedure TMenuHtmlForm.ApplyKey(const AKey: string);
begin
  FActiveKey := AKey;
  pcMain.ActivePageIndex := PageOfKey(AKey);
  FStatus := Format('当前：%s（服务端 %s）',
    [TitleOfKey(AKey), FormatDateTime('hh:nn:ss', Now)]);
  RefreshMenu;
end;

procedure TMenuHtmlForm.RefreshMenu;
begin
  hfMenu.HTML.Text := BuildMenuHtml;
end;

{ HTML 菜单点击：val 就是菜单项的 key }
procedure TMenuHtmlForm.edtMenuKeyChange(Sender: TObject);
var
  key: string;
begin
  key := Trim(edtMenuKey.Text);
  if key = '' then Exit;
  ApplyKey(key);
end;

{ 用户直接在浏览器里点 LCL 页签：服务端 ActivePage 已同步，这里只刷新左侧高亮 }
procedure TMenuHtmlForm.pcMainChange(Sender: TObject);
var
  key: string;
begin
  key := KeyOfPage(pcMain.ActivePageIndex);
  if key = FActiveKey then Exit;
  FActiveKey := key;
  FStatus := Format('当前：%s（服务端 %s）',
    [TitleOfKey(key), FormatDateTime('hh:nn:ss', Now)]);
  RefreshMenu;
end;

{ ---------------- LCL 业务：查询 / 统计 / 下载 ---------------- }

procedure TMenuHtmlForm.btnSignupQueryClick(Sender: TObject);
var
  i, n: Integer;
  kw, year: string;
begin
  kw := Trim(edtName.Text);
  year := cboYear.Text;
  if year = '' then year := '2026';

  n := 0;
  sgSignup.RowCount := 1;
  for i := Low(SIGNUP_NAMES) to High(SIGNUP_NAMES) do
    if (kw = '') or (Pos(kw, SIGNUP_NAMES[i]) > 0) then
    begin
      Inc(n);
      sgSignup.RowCount := n + 1;
      sgSignup.Cells[0, n] := SIGNUP_NAMES[i];
      sgSignup.Cells[1, n] := SIGNUP_COMPANIES[i];
      sgSignup.Cells[2, n] := SIGNUP_IDS[i];
      sgSignup.Cells[3, n] := SIGNUP_PHONES[i];
      sgSignup.Cells[4, n] := SIGNUP_STATES[i];
      sgSignup.Cells[5, n] := year;
    end;

  lblSignupStatus.Caption := Format('共 %d 条（%s）',
    [n, FormatDateTime('hh:nn:ss', Now)]);
  FStatus := Format('报名查询：%s 年份共 %d 条', [year, n]);
  RefreshMenu;
end;

procedure TMenuHtmlForm.btnScoreQueryClick(Sender: TObject);
var
  i, n: Integer;
  kw: string;
begin
  kw := Trim(edtScoreName.Text);

  n := 0;
  sgScore.RowCount := 1;
  for i := Low(SIGNUP_NAMES) to High(SIGNUP_NAMES) do
    if (kw = '') or (Pos(kw, SIGNUP_NAMES[i]) > 0) then
    begin
      Inc(n);
      sgScore.RowCount := n + 1;
      sgScore.Cells[0, n] := SIGNUP_COMPANIES[i];
      sgScore.Cells[1, n] := SIGNUP_NAMES[i];
      sgScore.Cells[2, n] := '超声探伤';
      sgScore.Cells[3, n] := FormatDateTime('yyyy-mm-dd', Date);
      sgScore.Cells[4, n] := IntToStr(62 + i * 6);
    end;

  lblScoreStatus.Caption := Format('共 %d 条（%s）',
    [n, FormatDateTime('hh:nn:ss', Now)]);
  FStatus := Format('成绩查询：共 %d 条', [n]);
  RefreshMenu;
end;

procedure TMenuHtmlForm.btnStatClick(Sender: TObject);
begin
  sgStat.RowCount := 4;

  sgStat.Cells[0, 1] := '深圳市正衡工程检测有限公司';
  sgStat.Cells[1, 1] := '超声探伤';
  sgStat.Cells[2, 1] := '4';
  sgStat.Cells[3, 1] := '3';

  sgStat.Cells[0, 2] := '深圳市远川建筑工程检测有限公司';
  sgStat.Cells[1, 2] := '低应变';
  sgStat.Cells[2, 2] := '2';
  sgStat.Cells[3, 2] := '2';

  sgStat.Cells[0, 3] := '深圳市正衡工程检测有限公司';
  sgStat.Cells[1, 3] := '地基基础';
  sgStat.Cells[2, 3] := '3';
  sgStat.Cells[3, 3] := '2';

  lblStatStatus.Caption := Format('统计完成（%s）', [FormatDateTime('hh:nn:ss', Now)]);
  FStatus := '成绩统计：3 个单位 / 9 人';
  RefreshMenu;
end;

procedure TMenuHtmlForm.btnDownloadClick(Sender: TObject);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('场次,考试时间,考试科目,人数,考生姓名');
    for i := Low(SIGNUP_NAMES) to High(SIGNUP_NAMES) do
      L.Add(Format('%d,2026-11-09 09:15~10:00,超声探伤,3,%s',
        [i + 1, SIGNUP_NAMES[i]]));
    SendText(L.Text, '考试安排表.csv', True);
  finally
    L.Free;
  end;
  lblDlStatus.Caption := Format('已生成下载（%s）', [FormatDateTime('hh:nn:ss', Now)]);
  FStatus := '已生成考试安排表下载';
  RefreshMenu;
end;

{ ---------------- 左侧菜单 HTML ---------------- }

function TMenuHtmlForm.BuildMenuHtml: string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add('<style>');
    L.Add('.lwm{position:absolute;left:0;top:0;right:0;bottom:0;display:flex;flex-direction:column;');
    { 配色走框架的主题变量（--lw-sm-*）：HTMLFrame 的内容是 innerHTML，
      和页面在同一个文档里，变量能直接继承下来 —— 切亮色/深色时这块菜单
      自动跟着变，不用重建 HTML。第二参数是兜底值（主题变量缺失时的原色） }
    L.Add('  font-family:"Microsoft YaHei",Arial,sans-serif;');
    L.Add('  background:var(--lw-sm-bg,#2c3947);color:var(--lw-sm-fg,#dfe6ee);font-size:15px}');
    L.Add('.lwm-side{flex:1;overflow:auto}');
    L.Add('.lwm-grp{border-bottom:1px solid var(--lw-sm-sep,rgba(255,255,255,.06))}');
    L.Add('.lwm-head{display:flex;align-items:center;gap:10px;padding:13px 14px;cursor:pointer;user-select:none}');
    L.Add('.lwm-head:hover{background:var(--lw-sm-hover,#37475a)}');
    L.Add('.lwm-arrow{display:inline-block;color:var(--lw-sm-arrow,#9db0c6);font-size:10px;transition:transform .15s}');
    L.Add('.lwm-head.open .lwm-arrow{transform:rotate(90deg)}');
    L.Add('.lwm-item{padding:11px 14px 11px 44px;cursor:pointer;');
    L.Add('  color:var(--lw-sm-fg2,#c9d4e0);font-size:14px}');
    L.Add('.lwm-item:hover{background:var(--lw-sm-hover,#37475a)}');
    L.Add('.lwm-item.on{background:var(--lw-sm-on,#41526a);color:var(--lw-sm-on-fg,#fff);');
    L.Add('  box-shadow:inset 3px 0 0 var(--lw-sm-bar,#4a90d9)}');
    L.Add('.lwm-foot{border-top:1px solid var(--lw-sm-sep,rgba(255,255,255,.08));padding:10px 14px;');
    L.Add('  font-size:12px;color:var(--lw-sm-muted,#93a4b8);line-height:1.6}');
    L.Add('</style>');

    L.Add('<div id="lwmenu" x-data="lwMenu()" class="lwm">');
    L.Add('  <div class="lwm-side">');
    L.Add('    <template x-for="g in groups" :key="g.key">');
    L.Add('      <div class="lwm-grp">');
    L.Add('        <div class="lwm-head" :class="{open: g.open}" @click="toggle(g)">');
    L.Add('          <span class="lwm-arrow">&#9654;</span>');
    L.Add('          <span x-text="g.text"></span>');
    L.Add('        </div>');
    L.Add('        <div x-show="g.open" style="display:none">');
    L.Add('          <template x-for="it in g.items" :key="it.key">');
    L.Add('            <div class="lwm-item" :class="{on: it.key === active}"');
    L.Add('                 @click="pick(it)" x-text="it.text"></div>');
    L.Add('          </template>');
    L.Add('        </div>');
    L.Add('      </div>');
    L.Add('    </template>');
    L.Add('  </div>');
    L.Add('  <div class="lwm-foot" x-text="status"></div>');
    L.Add('</div>');

    L.Add('<script>');
    L.Add('(function () {');
    { 服务端状态：高亮项与状态栏文字。每次重建 HTML 都刷新，帧重渲染后仍一致 }
    L.Add('  window.__lwMenuState = {"active":' + TJSONString.Create(FActiveKey).AsJSON +
      ',"status":' + TJSONString.Create(FStatus).AsJSON + '};');
    L.Add('  if (!window.lwMenu) {');
    L.Add('    window.lwMenu = function () {');
    L.Add('      var st = window.__lwMenuState || { active: "", status: "" };');
    L.Add('      var saved = {};');
    L.Add('      try { saved = JSON.parse(localStorage.getItem("lwMenuOpen") || "{}"); }');
    L.Add('      catch (e) { saved = {}; }');
    L.Add('      function openOf(k, def) {');
    L.Add('        return (saved[k] === undefined) ? def : !!saved[k];');
    L.Add('      }');
    L.Add('      return {');
    L.Add('        active: st.active,');
    L.Add('        status: st.status,');
    L.Add('        groups: [');
    L.Add('          { key: "theory", text: "从业人员理论考核", open: openOf("theory", true), items: [');
    L.Add('            { key: "theory.signup", text: "报名查询" },');
    L.Add('            { key: "theory.score", text: "成绩查询" },');
    L.Add('            { key: "theory.stat", text: "成绩统计" },');
    L.Add('            { key: "theory.schedule", text: "考试安排表下载" } ] },');
    L.Add('          { key: "exam", text: "考试管理", open: openOf("exam", false), items: [');
    L.Add('            { key: "exam.plan", text: "考试计划" },');
    L.Add('            { key: "exam.room", text: "考场安排" },');
    L.Add('            { key: "exam.inv", text: "监考人员" } ] },');
    L.Add('          { key: "qual", text: "资质管理", open: openOf("qual", false), items: [');
    L.Add('            { key: "qual.ent", text: "企业资质" },');
    L.Add('            { key: "qual.cert", text: "人员证书" } ] }');
    L.Add('        ],');
    L.Add('        toggle: function (g) {');
    L.Add('          g.open = !g.open;');
    L.Add('          saved[g.key] = g.open;');
    L.Add('          try { localStorage.setItem("lwMenuOpen", JSON.stringify(saved)); } catch (e) { }');
    L.Add('        },');
    L.Add('        pick: function (it) {');
    L.Add('          this.active = it.key;');
    { 关键一步：走框架的标准事件通道，服务端切 LCL 页签并回传整棵树 }
    L.Add('          if (window.$lwFireByName)');
    L.Add('            window.$lwFireByName("edtMenuKey", "OnChange", { val: it.key });');
    L.Add('        }');
    L.Add('      };');
    L.Add('    };');
    L.Add('  }');
    L.Add('  var host = document.getElementById("lwmenu");');
    L.Add('  function boot() {');
    L.Add('    if (!host || !window.Alpine) return false;');
    L.Add('    try { window.Alpine.initTree(host); } catch (e) { return false; }');
    L.Add('    return true;');
    L.Add('  }');
    L.Add('  if (!boot()) {');
    L.Add('    var n = 0;');
    L.Add('    var timer = setInterval(function () {');
    L.Add('      if (boot() || ++n > 40) clearInterval(timer);');
    L.Add('    }, 50);');
    L.Add('  }');
    L.Add('})();');
    L.Add('</script>');

    Result := L.Text;
  finally
    L.Free;
  end;
end;

end.
