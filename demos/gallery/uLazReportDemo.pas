{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: uLazReportDemo
  ------------------------------------------------------------------
  用 QF_Lazreport（C:\111\ccr\QF_Lazreport）在服务端渲染真实报表模板：
  模板文件是 demos\gallery\混凝土配合比.frf（FastReport 2.46 二进制格式）。

  为什么这里能用 LazReport、而 lwreport 里说不能：
    lwreport 说的是 Lazarus 自带的 components/lazreport —— 它把 TfrReport
    和预览窗体、打印机绑死，nogui widgetset 下跑不起来。
    QF 的这份 fork 补了 LCLNOGUI 支持（lr_ngcanvas：FreeType 把文字直接
    光栅化进 FPImage，不依赖窗口/打印机），并内置了 FastReport 2.46 FRF
    的读取器（fr246_frf + fr246_lrfbridge，TfrReport.LoadFromFile 自动识别），
    所以「载入模板 + 灌数据 + 导出」在无头服务端可用。

  nogui 下的三个坑（本单元都封住了）：
    1) 字体缓存 .fonts.cache 是相对路径；nogui widgetset 会把进程 CWD 改成
       C:\WINDOWS\Fonts（只读），缓存写不进去 → 文字全丢，页面只剩表格线。
       渲染前必须把 CWD 切到可写目录，见 TLazReportCwd。
    2) 模板里的 宋体/黑体 在 FreeType 侧要能解析到真正带中文字形的 TTF；
       出错时统一回落到 SimHei（simhei.ttf 是单字体 TTF，不是 .ttc 集合）。
       顺带把 <sup>3</sup> 这类内联标签换成真字符（画布不解析 HTML 标签）。
    3) HTML 导出在 nogui 下拿不到文字（导出过滤器靠拦截画布文字调用，
       而 nogui 是光栅化绘制），所以出口只留 PDF 和 PNG。

  数据集与变量：
    * 模板里的 [HntphbTable."字段"] 指向名为 HntphbTable 的 TBufDataset，
      组件名必须与模板前缀一致、且挂在 report 同一个 Owner 下（模板是按
      名字在 CurReport.Owner 里找 TDataSet 的）；
    * 需要哪些字段不写死 —— CollectTemplateFields 扫模板自己算出来，
      所以换一版 .frf（字段增删）不用改代码；
    * [jzr] / [a1] / [testname] 这类是 FastReport 变量，走 OnGetValue；
      变量名和字段名共用 FSample 这一张「名字=示例值」表，没有的留空。
}
unit uLazReportDemo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, DB, BufDataset, Graphics, LR_Class, LR_DBSet,
  sqldb, sqlite3conn;

const
  { 模板文件名（与 exe 同目录） }
  REPORT_TEMPLATE = '混凝土配合比.frf';
  { 模板里的数据集名，必须与 .frf 里 [HntphbTable."…"] 前缀一致 }
  REPORT_DATASET = 'HntphbTable';
  { nogui 下可靠的中文字体 }
  CJK_FONT = 'SimHei';
  { 数据来源：SQLite 库（与 exe 同目录下的 data\tfdata.db），表名照 MSSQL 原表 }
  HNT_DB_FILE = 'data' + PathDelim + 'tfdata.db';
  HNT_DB_TABLE = '砼配合比设计';

type
  { 渲染期间把 CWD 切到可写目录，析构时还原。
    不切的话 .fonts.cache 会落到 C:\WINDOWS\Fonts，写失败 → 文字全丢。 }
  TLazReportCwd = class
  private
    FSaved: string;
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
  end;

  { 混凝土配合比设计报告：载入 .frf 模板 + 灌示例数据 + 导出 }
  TLazReportDemo = class
  private
    { 报表与数据集必须挂在同一个 Owner 下：模板里的 [HntphbTable."字段"]
      是「按名字在 CurReport.Owner 里找组件」解析的（lr_utils 的
      frGetDataSetAndField），Owner 为 nil 时字段永远是空。 }
    FOwner: TComponent;
    FReport: TfrReport;
    FDB: TfrDBDataset;
    FData: TBufDataset;
    FTemplate: string;
    { 一份「名字=示例值」的表，数据集字段和模板变量共用：模板里出现的名字
      只要这里有一行就被填上，没有的留空。这样换模板不用改代码。 }
    FSample: TStringList;
    { 本次实际取到的记录：库文件与报告编号（没连上库时为空） }
    FDataFile: string;
    FDataReportNo: string;
    FDataError: string;
    procedure FillSample;
    { 从 SQLite 里取一条记录覆盖 FSample；库不在/读失败时静默返回 False }
    function LoadFromRecord(const ADbFile, AReportNo: string;
      out AUsedNo: string): Boolean;
    { 把库里的列拼成模板要的变量（a*/b*/c*/d*/e*/f*/g*、等级、地址…） }
    procedure ApplyRecordDerived;
    { 扫模板里所有 [HntphbTable."xxx"]，得到它真正要的字段名 }
    procedure CollectTemplateFields(AList: TStrings);
    procedure BuildSampleData;
    procedure FixFonts;
    { 模板里的 [jzr]/[a1]/[testname] 等变量由这个回调逐个给值 }
    procedure DoGetValue(const ParName: String; var ParValue: Variant);
  public
    constructor Create(const ATemplateFile: string);
    destructor Destroy; override;
    { 建数据 + 执行排版。失败时 AError 带回原因 }
    function Prepare(out AError: string): Boolean;
    { 单文件 PDF（字体子集嵌入，浏览器自带查看器可开） }
    function ExportPDF(const AFileName: string): Boolean;
    { 每页一张 PNG（page1.png / page2.png…），返回张数，失败 -1 }
    function ExportPNG(const ABaseName: string): Integer;
    function PageCount: Integer;
    property Report: TfrReport read FReport;
    property TemplateFile: string read FTemplate;
    { 报告里用的是哪条记录（空 = 用了内置示例值） }
    property DataReportNo: string read FDataReportNo;
    property DataFile: string read FDataFile;
    { 读库失败的原因（成功时为空），方便在页面上直接看到为什么没取到数 }
    property DataError: string read FDataError;
  end;

implementation

uses
  lr_e_fclpdf, LR_E_IMG, LR_progr;

{ ---------------- TLazReportCwd ---------------- }

constructor TLazReportCwd.Create(const ADir: string);
begin
  inherited Create;
  FSaved := GetCurrentDir;
  if (ADir <> '') and DirectoryExists(ADir) then
    SetCurrentDir(ADir);
end;

destructor TLazReportCwd.Destroy;
begin
  if (FSaved <> '') and DirectoryExists(FSaved) then
    try
      SetCurrentDir(FSaved);
    except
    end;
  inherited Destroy;
end;

{ ---------------- TLazReportDemo ---------------- }

constructor TLazReportDemo.Create(const ATemplateFile: string);
begin
  inherited Create;
  FTemplate := ATemplateFile;
  FSample := TStringList.Create;
  FSample.NameValueSeparator := '=';
  FOwner := TComponent.Create(nil);
  FReport := TfrReport.Create(FOwner);
  FReport.OnGetValue := @DoGetValue;
  { 服务端渲染必须关掉 LazReport 的进度窗体。
    那是 TfrProgressForm：一个模态窗体 + 一个 LCL TTimer（Timer1）。在
    服务端它有两个致命问题：
      1) 模态窗体没有意义（没人点"取消"，也没有主消息循环去转它）；
      2) Timer1.Enabled := True 要靠 widgetset 分配系统定时器：nogui 的实现
         永远返回 0，win32 的服务工作线程也可能分配不到 → 一律抛
         EOutOfResources「No timers available」（NOTES 坑 48 / 坑 177）。
    关掉后 DoPrepareReport 走 BuildBeforeModal 的非模态分支，纯内存排版。 }
  FReport.ShowProgress := False;
  { 但 ShowProgress=False 还不够。非模态分支最后还是会执行
    `if FinalPass then frProgressForm.ModalDone(mrOk)`，而 ModalDone 里
    第一件事就是 Timer1.Enabled := True —— 依旧 CreateTimer（nogui 返回 0）
    → 抛 EOutOfResources。第一次点"生成"必失败，第二次反而好了：SetEnabled
    在异常前已经把 FEnabled 置成 True，之后就不再重试。
    这个定时器唯一的活是「250ms 后把 Enabled 置回 False」（给模态窗收尾），
    无头渲染完全用不到它，所以直接把 OnTimer 摘掉：TCustomTimer.UpdateTimer
    只在 OnTimer 已赋值时才真的去 CreateTimer，等于让它彻底不碰 widgetset。
    （同一个套路见 lwdispatch 里对 TTreeView 内部 FChangeTimer 的处理。） }
  if Assigned(frProgressForm) then
    frProgressForm.Timer1.OnTimer := nil;
end;

destructor TLazReportDemo.Destroy;
begin
  FReport.Free;
  FData.Free;
  FDB.Free;
  FSample.Free;
  FOwner.Free;
  inherited Destroy;
end;

{ 示例数据：一份「名字=值」的表，数据集字段和模板变量共用它 —— 模板里
  出现的名字（不管是 [HntphbTable."x"] 还是 [x]）只要这里有一行就被填上，
  没有的留空。换模板不用改代码，只往这里补行。

  值刻意写短：模板里的标签是按绝对坐标摆的，值一长就压到右边的标签上去。
  真实项目里换成 TSQLQuery/TDBDataset 即可，模板不用动。 }
procedure TLazReportDemo.FillSample;

  procedure S(const AName, AValue: string);
  begin
    FSample.Values[AName] := AValue;
  end;

begin
  FSample.Clear;

  { ---- 表头 ---- }
  S('报告编号', 'HNT-2026-0158');
  S('见证人单位', '深圳市中正工程监理有限公司');
  S('见证人', '李文博');
  S('送检单位', '深圳市海川建设工程有限公司');
  S('送检日期', '2026-11-04');
  S('工程名称', '滨海商务中心二期');
  S('工程部位', '三层梁板');
  S('强度等级', 'C30');
  S('抗渗等级', 'P6');
  S('抗折等级', '—');
  S('设计规程', 'JGJ 55-2011');
  S('试验单位', '深圳市海川建设工程质量检测有限公司');
  S('单位地址', '深圳市南山区科技园北区海川大厦 1 栋 3 层');
  S('批准人', '陈志远');
  S('校核人', '林小梅');
  S('送检类型', '普通送检');

  { ---- 水泥：产地 / 品种 / 预测强度 ---- }
  S('水泥产地', '英德海螺水泥');
  S('水泥厂名牌号', '英德海螺水泥');
  S('水泥品种', 'P.O 42.5');
  S('水泥预测强度', '47.5');
  S('水泥28天强度', '47.5');

  { ---- 砂①：模板里 [HntphbTable."砂…"] 那一行 ---- }
  S('砂产地', '惠州东江砂场');
  S('砂表观密度', '2630');
  S('砂堆积密度', '1520');
  S('砂细度模数', '2.7');
  S('砂含泥量', '1.2');
  S('砂泥块含量', '0.3');

  { ---- 石① ---- }
  S('石产地', '从化花岗岩');
  S('石针片状', '6.5');
  S('石压碎指标', '8.2');
  S('石含泥量', '0.5');
  S('石泥块含量', '0.2');
  S('石最大粒径', '25');

  { ---- 拌合物性能 ---- }
  S('塌落度', '180');
  S('坍落度', '180');
  S('容重', '2400');
  S('表观密度', '2400');
  S('拌合方法', '机械搅拌');
  S('振捣方法', '机械振捣');
  S('混凝土扩展度', '420');
  S('水胶比', '0.42');

  { ---- 设计配合比：材料用量（kg/m3）与比例 ----
    列序：水 水泥 1.砂 2.砂 1.石 2.石 1.掺合料 2.掺合料 1.外加剂 2.外加剂 }
  S('水用量', '168');
  S('水泥用量', '380');
  S('砂用量', '720');
  S('石用量', '540');
  S('水比例', '0.44');
  S('水泥比例', '1.00');
  S('砂比例', '1.89');
  S('石比例', '1.42');
  S('掺合料比例', '0.18');
  S('掺合料比例1', '0.11');
  S('外加剂比例1', '0.012');
  S('外加剂比例2', '0.0005');

  { ---- 备注：模板把「外附加报告编号 + 备注」放在同一格 ---- }
  S('备注', '28d 抗压强度实测 38.6MPa，满足 C30 配制强度要求。');

  { ================= 模板变量 =================
    a* 是「材料用量」行最右四格：1./2.掺合料、1./2.外加剂的用量数值；
    b* 粉煤灰产地行，c* 掺合料（矿粉）行，d* 外加剂①，e* 外加剂②；
    f* 石子②（第二行石子），g* 砂②（第二行砂）。 }
  S('a1', '70');
  S('a2', '40');
  S('a3', '4.6');
  S('a4', '0.2');

  S('b1', '深圳妈湾电厂');
  S('b2', 'F 类 Ⅱ 级');
  S('b3', '18');
  S('b4', '≥ 40%');
  S('b5', '0.40');

  S('c1', '韶关钢铁厂');
  S('c2', 'S95 矿渣粉');
  S('c3', '10');
  S('c4', '≥ 40%');
  S('c5', '0.40');

  S('d1', '东莞建科');
  S('d2', 'JK-5 减水剂');
  S('d3', '1.2');
  S('d4', '按胶凝材料总量计');

  S('e1', '东莞建科');
  S('e2', 'JK-9 缓凝剂');
  S('e3', '0.05');
  S('e4', '按胶凝材料总量计');

  S('f1', '从化花岗岩');
  S('f2', '5.0');
  S('f3', '8.2');
  S('f4', '0.5');
  S('f5', '0.2');
  S('f6', '25');
  S('f7', '540');
  S('f8', '1.42');

  S('g1', '惠州东江砂场');
  S('g2', '2630');
  S('g3', '1520');
  S('g4', '2.7');
  S('g5', '1.2');
  S('g6', '0.3');
  S('g7', '0');
  S('g8', '0');

  { ---- 表头/页脚上的单值变量 ----
    注意：tld / cdfs / clxs / sjb / QDLS 在模板里是「格子里的说明文字」，
    不是数值 —— 原程序（acs_laz HNTPHB2_pas.pas 的 HntphbRepGetValue）就是
    这么赋的：
      TLD  := 混凝土坍落度 / 混凝土扩展度   （按 扩展度1 切换）
      CDFS := 取代方式（JGJ 55-2000）或 ----
      CLXS := 超量系数（老规程）/ 影响系数  （新规程）
      SJB  := 水灰比（老规程）/ 水胶比      （新规程）
      QDLS := 28天预测强度 / 28天实测强度
    temp 才是数值（水灰比）。 }
  S('jzr', '普通送检');
  S('testname', '王海涛');
  S('nowDATE', FormatDateTime('yyyy-mm-dd', Now));
  S('qddj', 'C30');
  S('ksdj', 'P6');
  S('kzdj', '—');
  S('bzh', 'JGJ 55-2011');
  S('tld', '混凝土坍落度');
  S('QDLS', '28天实测强度');
  S('sjb', '水胶比');
  S('temp', '0.42');
  S('cdfs', '取代方式');
  S('clxs', '影响系数');
  S('userdw', '深圳市海川建设工程质量检测有限公司');
  S('useradd', '深圳市南山区科技园北区海川大厦 1 栋 3 层');
end;

{ 从 SQLite（data\tfdata.db）里读一条记录，把列值按「列名 = 模板里的名字」
  直接铺进 FSample。表是从 MSSQL 2000 的 tfdata.dbo.[砼配合比设计] 搬过来的，
  列名没改，所以大部分列不用映射就能对上模板里的 [HntphbTable."xxx"]。

  库不存在、表不存在、读异常时一律返回 False：报表继续用 FillSample 的
  内置示例值，页面上不会因为缺库而打不开。 }
function TLazReportDemo.LoadFromRecord(const ADbFile, AReportNo: string;
  out AUsedNo: string): Boolean;
var
  conn: TSQLite3Connection;
  tr: TSQLTransaction;
  q: TSQLQuery;
  i: Integer;
  v, sql: string;
  fmt: TFormatSettings;
begin
  Result := False;
  AUsedNo := '';
  FDataFile := '';
  FDataReportNo := '';
  FDataError := '';
  if not FileExists(ADbFile) then
  begin
    FDataError := '找不到数据库：' + ADbFile;
    Exit;
  end;

  { 数值转字符串必须用固定小数点：fcl-db 的 AsString 会跟随区域设置，
    某些环境给出 0,42 这种逗号小数，PDF 上就成了错数 }
  fmt := DefaultFormatSettings;
  fmt.DecimalSeparator := '.';
  fmt.ThousandSeparator := #0;

  conn := TSQLite3Connection.Create(nil);
  tr := TSQLTransaction.Create(nil);
  q := TSQLQuery.Create(nil);
  try
    try
      { fcl-db 的 query 必须挂事务，否则 Open 抛 "Transaction not set" }
      conn.DatabaseName := ADbFile;
      tr.DataBase := conn;
      conn.Transaction := tr;
      conn.Open;
      tr.StartTransaction;
      q.DataBase := conn;
      q.Transaction := tr;
      if AReportNo <> '' then
        sql := 'SELECT * FROM "' + HNT_DB_TABLE + '" WHERE 报告编号 = :no LIMIT 1'
      else
        sql := 'SELECT * FROM "' + HNT_DB_TABLE + '" ORDER BY 报告编号 DESC LIMIT 1';
      q.SQL.Text := sql;
      if AReportNo <> '' then
        q.Params.ParamByName('no').AsString := AReportNo;
      q.Open;
      if q.IsEmpty then
        Exit;

      for i := 0 to q.Fields.Count - 1 do
      begin
        case q.Fields[i].DataType of
          ftFloat, ftCurrency, ftBCD, ftFMTBcd:
            v := FormatFloat('0.####', q.Fields[i].AsFloat, fmt);
        else
          v := Trim(q.Fields[i].AsString);
        end;
        FSample.Values[q.Fields[i].FieldName] := v;
      end;

      AUsedNo := FSample.Values['报告编号'];
      FDataFile := ADbFile;
      FDataReportNo := AUsedNo;
      ApplyRecordDerived;
      Result := True;
    except
      on E: Exception do
      begin
        FDataError := E.ClassName + ': ' + E.Message;
        Result := False;
      end;
    end;
  finally
    q.Free;
    conn.Free;
    tr.Free;
  end;
end;

{ 库里的列 → 模板变量的换算。
  变量名的语义是从原 Delphi 程序（acs_laz/src/HNTPHB2_pas.pas 的
  HntphbRepGetValue / jsqd）里逐条对着抄的，不是猜的：
    a1..a4 材料用量行最右四格（1./2.掺合料、1./2.外加剂）
    b* 掺合料①（粉煤灰）  c* 掺合料②（矿粉）  h* 掺合料③
    d* 外加剂①  e* 外加剂②  j* 外加剂③
    f* 石②（…1 组）  g* 砂②（…1 组）
  本模板只用到 a/b/c/d/e/f/g，h/i/j/k/l 一并算好，换新版模板也够。 }
procedure TLazReportDemo.ApplyRecordDerived;

  function V(const AName: string): string;
  begin
    Result := FSample.Values[AName];
  end;

  { 空值不覆盖：库里有空列时保留 FillSample 的兜底值，避免整格变空 }
  procedure Put(const AKey, AValue: string);
  begin
    if Trim(AValue) <> '' then
      FSample.Values[AKey] := AValue;
  end;

  function Grade: string;
  begin
    Result := V('砼强度等级');
    if Result = '' then
      Result := V('强度等级');
  end;

var
  ks: Integer;
begin
  { ---- 等级类：模板上是 C30 / P6 / f4.5 这种前缀写法 ---- }
  if Grade <> '' then
  begin
    Put('强度等级', Grade);
    Put('qddj', 'C' + Grade);
  end;
  ks := StrToIntDef(V('抗渗等级'), 0);
  if ks > 0 then
    Put('ksdj', 'P' + IntToStr(ks));
  if V('抗折等级') <> '' then
    Put('kzdj', V('抗折等级'));

  { ---- 表头/页脚 ---- }
  Put('设计规程', V('检验依据'));
  Put('bzh', V('检验依据'));
  Put('userdw', V('试验单位'));
  Put('useradd', V('单位地址'));
  Put('jzr', V('送检类型'));

  { ---- 格子里的说明文字：跟原程序一样按规程/强度类型切换 ---- }
  if V('扩展度1') = '1' then
    Put('tld', '混凝土扩展度')
  else
    Put('tld', '混凝土坍落度');
  if V('水泥强度类型') = '1' then
    Put('QDLS', '28天预测强度')
  else
    Put('QDLS', '28天实测强度');
  { 规程只影响 sjb / clxs 两个说法；cdfs（取代方式）两版都一样，
    老代码在新规程下把 cdfs 给成 '----'，画到纸上像个空值，这里统一成文字 }
  Put('cdfs', '取代方式');
  if Pos('55-2000', V('检验依据')) > 0 then
  begin
    Put('sjb', '水灰比');
    Put('clxs', '超量系数');
  end
  else
  begin
    Put('sjb', '水胶比');
    Put('clxs', '影响系数');
  end;
  { temp 是数值：水灰比 }
  Put('temp', V('水灰比'));

  { ---- 材料用量行最右四格 ---- }
  Put('a1', V('掺合料用量'));
  Put('a2', V('掺合料用量1'));
  Put('a3', V('外加剂用量1'));
  Put('a4', V('外加剂用量2'));

  { ---- 掺合料①（产地/名称规格/掺量/方式/取代系数/报告编号） ---- }
  Put('b1', V('掺合料产地'));
  Put('b2', V('掺合料名称规格'));
  Put('b3', V('掺合料掺量'));
  Put('b4', V('掺合料方式'));
  Put('b5', V('掺合料取代系数'));
  Put('b6', V('掺合料报告编号'));

  { ---- 掺合料② ---- }
  Put('c1', V('掺合料产地1'));
  Put('c2', V('掺合料名称规格1'));
  Put('c3', V('掺合料掺量1'));
  Put('c4', V('掺合料方式1'));
  Put('c5', V('掺合料取代系数1'));
  Put('c6', V('掺合料报告编号1'));

  { ---- 外加剂① ---- }
  Put('d1', V('外加剂产地1'));
  Put('d2', V('外加剂名称规格1'));
  Put('d3', V('外加剂掺量1'));
  Put('d4', V('外加剂其它1'));
  Put('d5', V('外加剂报告编号1'));

  { ---- 外加剂② ---- }
  Put('e1', V('外加剂产地2'));
  Put('e2', V('外加剂名称规格2'));
  Put('e3', V('外加剂掺量2'));
  Put('e4', V('外加剂其它2'));
  Put('e5', V('外加剂报告编号2'));

  { ---- 石② ---- }
  Put('f1', V('石产地1'));
  Put('f2', V('石针片状1'));
  Put('f3', V('石压碎指标1'));
  Put('f4', V('石含泥量1'));
  Put('f5', V('石泥块含量1'));
  Put('f6', V('石最大粒径1'));
  Put('f7', V('石用量1'));
  Put('f8', V('石比例1'));

  { ---- 砂② ---- }
  Put('g1', V('砂产地1'));
  Put('g2', V('砂表观密度1'));
  Put('g3', V('砂堆积密度1'));
  Put('g4', V('砂细度模数1'));
  Put('g5', V('砂含泥量1'));
  Put('g6', V('砂泥块含量1'));
  Put('g7', V('砂用量1'));
  Put('g8', V('砂比例1'));
end;

{ 扫模板里所有 [HntphbTable."xxx"] 拿到它真正要的字段名。
  这样换一版模板（字段增删）不用改这里 —— 少一个字段不会报错，
  多一个字段也只是留空。 }
procedure TLazReportDemo.CollectTemplateFields(AList: TStrings);
var
  i, j, p, q, prefixLen: Integer;
  s, fld, prefix: string;
  page: TfrPage;
  o: TfrObject;
begin
  AList.Clear;
  prefix := REPORT_DATASET + '."';
  prefixLen := Length(prefix);
  for i := 0 to FReport.Pages.Count - 1 do
  begin
    page := FReport.Pages[i];
    for j := 0 to page.Objects.Count - 1 do
    begin
      o := TfrObject(page.Objects[j]);
      if not (o is TfrMemoView) then
        Continue;
      s := TfrMemoView(o).Memo.Text;
      p := 1;
      while True do
      begin
        p := PosEx(prefix, s, p);
        if p = 0 then
          Break;
        q := PosEx('"', s, p + prefixLen);
        if q = 0 then
          Break;
        fld := Copy(s, p + prefixLen, q - (p + prefixLen));
        if (fld <> '') and (AList.IndexOf(fld) < 0) then
          AList.Add(fld);
        p := q + 1;
      end;
    end;
  end;
end;

procedure TLazReportDemo.BuildSampleData;
var
  names: TStringList;
  i: Integer;
begin
  FillSample;
  { 有库就用库里的记录覆盖兜底值（表结构见 tools/make_hntphb_demo_db.py）；
    没库/读失败时静默跳过，仍用上面那套示例值，页面不会打不开 }
  LoadFromRecord(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    HNT_DB_FILE, '', FDataReportNo);

  names := TStringList.Create;
  try
    CollectTemplateFields(names);
    if names.Count = 0 then
    begin
      { 一个字段都没扫到时兜底：宁可留空也不要因为没字段而崩 }
      names.Add('报告编号');
      names.Add('工程名称');
      names.Add('工程部位');
    end;

    { 数据集必须叫 HntphbTable：模板里的 [HntphbTable."字段"] 是「在
      report.Owner 下按名字找组件、且要求它是 TDataSet/TDataSource」，
      所以数据集本身要叫这个名字并挂在同一个 Owner 下 }
    FData := TBufDataset.Create(FOwner);
    FData.Name := REPORT_DATASET;
    for i := 0 to names.Count - 1 do
      FData.FieldDefs.Add(names[i], ftString, 80);
    FData.CreateDataSet;
    FData.Open;
    FData.Append;
    for i := 0 to names.Count - 1 do
      FData.FieldByName(names[i]).AsString := FSample.Values[names[i]];
    FData.Post;
  finally
    names.Free;
  end;
end;

{ 变量取值回调：模板里 [jzr]/[a1]/[testname] 这些括号里的名字都会问到这儿。
  用每份报表自己的 OnGetValue，而不是全局 frVariables —— 画廊是多会话
  共用进程，全局变量会串会话。 }
procedure TLazReportDemo.DoGetValue(const ParName: String; var ParValue: Variant);
var
  i: Integer;
begin
  { 关键：只在真的命中时才写 ParValue，不能给"不认识的名字"赋空串 ——
    引擎（lr_class 里 GetIntrpValue → 数据集兜底）的判断是「Variant 仍是
    varEmpty 才去按 [数据集."字段"] 解析」。一旦这里赋了 ''（varString），
    它就把 [HntphbTable."送检单位"] 当成"变量存在、值为空"，整列字段全空白。
    这就是「数据集有值但报表不显示」的唯一原因。 }
  i := FSample.IndexOfName(ParName);
  if i >= 0 then
    ParValue := FSample.ValueFromIndex[i];
end;

{ 载入模板后做三处规范化：
  1) 字体：模板写的是 宋体 / 黑体，nogui 的 FreeType 侧只认单字体 TTF
     （宋体是 simsun.ttc 字体集合，解析不到就画方框），统一换成 SimHei；
  2) 内联标签：QF 的 fr246 读取器会把老式上标标记（kg/m~3|）还原成
     FastReport 4 风格的 <sup>3</sup>，而 nogui 画布是按纯文本画的，
     标签会原样印到纸上 → 上标/下标换 Unicode 字符，其余标签直接剥掉；
  3) 空 memo 补一个空格：fcl-pdf 导出器在 lr_e_fclpdf.pas:507 直接取
     ms[0]，memo 文本为空时 TStringList 无元素 → EStringListError
     "List index (0) out of bounds"，整个导出中断。模板里那个透明的
     大背景框就是空 memo，必须补位。 }
procedure TLazReportDemo.FixFonts;

  function Plain(const S: string): string;
  begin
    { <sup>/<sub> 必须留着：PDF 导出器（lr_e_fclpdf 的 WriteRichText）会按
      这两个标签换一半字号并抬/降基线，删掉就成了 kg/m3。粗体/斜体/下划线
      在 nogui 的画布上只画字形不带样式，标签留着没意义，剥掉。 }
    Result := StringReplace(S, '<b>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '</b>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '<i>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '</i>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '<u>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '</u>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '<strike>', '', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, '</strike>', '', [rfReplaceAll, rfIgnoreCase]);
  end;

var
  i, j: Integer;
  page: TfrPage;
  o: TfrObject;
  mv: TfrMemoView;
  t: string;
begin
  for i := 0 to FReport.Pages.Count - 1 do
  begin
    page := FReport.Pages[i];
    for j := 0 to page.Objects.Count - 1 do
    begin
      o := TfrObject(page.Objects[j]);
      if not (o is TfrMemoView) then
        Continue;
      mv := TfrMemoView(o);
      if not SameText(mv.Font.Name, CJK_FONT) then
        mv.Font.Name := CJK_FONT;
      t := Plain(mv.Memo.Text);
      if Trim(t) = '' then
        t := ' ';
      if t <> mv.Memo.Text then
        mv.Memo.Text := t;
    end;
  end;
end;

function TLazReportDemo.Prepare(out AError: string): Boolean;
var
  guard: TLazReportCwd;
begin
  Result := False;
  AError := '';
  if not FileExists(FTemplate) then
  begin
    AError := '模板文件不存在：' + FTemplate;
    Exit;
  end;

  { .fonts.cache 与模板内的相对路径都要在可写目录里处理 }
  guard := TLazReportCwd.Create(ExtractFilePath(ParamStr(0)));
  try
    try
      { 上一次生成留下的数据集组件必须先释放。BuildSampleData 每次都建一个
        名为 HntphbTable 的 TBufDataset，Prepare 又建一个 TfrDBDataset ——
        它们都挂在同一个 FOwner 下，不释放就重名，TComponent 直接抛
        EComponentError「Duplicate name」（第二次点"生成报表"必崩）。 }
      FReport.Dataset := nil;
      FreeAndNil(FDB);
      FreeAndNil(FData);

      FReport.Pages.Clear;
      FReport.LoadFromFile(FTemplate);
      FixFonts;

      { 示例值（含数据集字段与模板变量）在 BuildSampleData 里一次性铺好 }
      BuildSampleData;
      FDB := TfrDBDataset.Create(FOwner);
      FDB.Name := 'HntphbData';     { 主数据带用的桥接组件，名字随意 }
      FDB.DataSet := FData;
      FReport.Dataset := FDB;

      if not FReport.PrepareReport then
      begin
        AError := 'PrepareReport 返回 False（版面或数据集有问题）';
        Exit;
      end;
      Result := FReport.EMFPages.Count > 0;
      if not Result then
        AError := '报表没有产生任何页面';
    except
      on E: Exception do
        AError := E.ClassName + ': ' + E.Message;
    end;
  finally
    guard.Free;
  end;
end;

function TLazReportDemo.ExportPDF(const AFileName: string): Boolean;
var
  guard: TLazReportCwd;
begin
  guard := TLazReportCwd.Create(ExtractFilePath(ParamStr(0)));
  try
    Result := FReport.ExportTo(TlrPdfExportFilter, AFileName);
  finally
    guard.Free;
  end;
end;

function TLazReportDemo.ExportPNG(const ABaseName: string): Integer;
var
  guard: TLazReportCwd;
begin
  guard := TLazReportCwd.Create(ExtractFilePath(ParamStr(0)));
  try
    try
      if FReport.ExportTo(TfrImageExportFilter, ABaseName) then
        Result := FReport.EMFPages.Count
      else
        Result := -1;
    except
      Result := -1;
    end;
  finally
    guard.Free;
  end;
end;

function TLazReportDemo.PageCount: Integer;
begin
  Result := FReport.EMFPages.Count;
end;

end.
