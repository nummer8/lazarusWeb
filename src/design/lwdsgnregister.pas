{
  lazarusWeb :: lwdsgnregister
  ------------------------------------------------------------------
  设计期包（lwdesign）的注册单元。装上这个包以后，IDE 里会多出：

    1. 新建工程 -> 两个模板，差别只在 .lpi 的 widgetset 档位：
       "lazarusWeb Application"          默认 widgetset 构建（IDE 里直接 F9，
                                         启动后弹服务端面板窗口，调试最方便）；
       "lazarusWeb Application (nogui)"  LCLWidgetType=nogui 的控制台服务程序
                                         （部署档，只能 lazbuild --ws=nogui 编译）。
       主窗体直接就是 TLWForm，可以像普通窗体一样拖控件。

       落盘时机与 Lazarus 自带模板完全一致 —— 选中模板后不弹任何对话框、
       不建目录、不写文件：工程此刻是"虚拟工程"（ProjectInfoFile 为空），
       .lpr 的源码、主窗体单元的源码和 .lfm 全在内存里，标题栏显示
       "project1 (*lpi)"（工程名和标准模板一样先给个占位名）。用户按保存
       （Ctrl+S / 保存全部）时 IDE 才弹标准的"保存项目"对话框，工程名和
       目录那时才确定（目录默认就是 IDE 选项"环境 / 文件"里的
       "项目构建测试的目录"），文件在这一步真正落盘。
       build.bat / build.sh 和 nogui 档的 widgetset 宏由保存钩子补写，
       见 TLWProjectFinalizer。

    2. 新建文件 -> "lazarusWeb Form" / "lazarusWeb Login form"
       前者是空白 TLWForm 单元（.pas + .lfm），ResourceClass 设为 TLWForm，
       IDE 会为它打开窗体设计器；
       后者预置了登录窗体骨架（TLWLoginForm 子类）：用户名/密码编辑框、
       登录/重置按钮、OnLogin 认证回调，新建即能跑，认证逻辑改 DoLoginEx。

    3. 组件面板 -> "lazarusWeb" 页
       TLWFileUpload / TLWDBGrid / TLWDBNavigator / TLWChart / TLWGauge /
       TLWColorPicker / TLWHTMLFrame / TLWPDFFrame / TLWSideMenu
       （左侧折叠菜单，非可视，拖到窗体上后双击即开 IDE 原生菜单编辑器，
       与 TMainMenu 完全一致）。

       面板上只放"能往窗体上拖的控件"。TLWForm / TLWLoginForm 是窗体基类，
       不进面板 —— 它们由向导生成（新建工程 / 新建文件），没有任何拖放语义。

       这些类注册进 IDE 是"带自定义控件的窗体能在设计期打开"的前提 ——
       读 lfm 时按类名 GetClass，IDE 进程里没注册就直接报未知类。

    4. TLWForm / TLWLoginForm 注册为设计期基类
       FormEditingHook.RegisterDesignerBaseClass —— 这样它们的后代才能在
       设计器里正常打开（与 uniGUI 的 TUniForm 一个道理）。设计期基类
       注册表正好也是 IDE 解析 lfm 祖先类名时的查找目标
       （SearchComponentClass -> FindDesignerBaseClassByName），
       所以拿掉面板注册不会丢祖先解析能力。

  注意：TLWForm 是真正的 TForm 后代，不是 uniGUI 那种"影子类"，
  所以不需要设计期代理类（DesignProxy）—— 拖上去的 TButton/TEdit 就是
  LCL 自己的控件，属性面板、事件页、对齐工具全部照常可用。
}
unit lwdsgnregister;

{$mode objfpc}{$H+}

interface

procedure Register;

implementation

uses
  Classes, SysUtils, TypInfo, Forms, Controls, Dialogs, StdCtrls, LCLType,
  LResources, ProjectIntf, LazIDEIntf, FormEditingIntf, IDEIntf, CompOptsIntf,
  LazFileUtils, PackageIntf, ExtCtrls,
  lwbase, lwform, lwfileupload, lwcamera, lwnewproject, lwlogin, lwcaptcha,
  { 下面这些来自 lwserver 包：注册进 IDE 后，带自定义控件的窗体才能
    在设计器里打开（不然读 lfm 报 "unknown class TLWDBGrid"），
    同时也进组件面板，Object Inspector 能直接编辑它们的新属性 }
  lwdbgrid, lwdbnav, lwchart, lwui, lwweb, lwreport, lwsidemenu;

const
  sLWProjectName      = 'lazarusWeb Application';
  sLWProjectDesc      = '用真实 LCL 控件生成 Web 服务程序（Ext JS 前端）。' + LineEnding +
    '默认 widgetset 构建：IDE 里直接 F9 调试，启动后弹服务端面板窗口。';
  sLWProjectNoguiName = 'lazarusWeb Application (nogui)';
  sLWProjectNoguiDesc = '同 lazarusWeb Application，但 .lpi 固定 LCLWidgetType=nogui：' + LineEnding +
    '纯控制台服务程序，无窗口，只能用 lazbuild --ws=nogui 编译（部署档）。';
  sLWFormName    = 'lazarusWeb Form';
  sLWFormDesc    = '一个 TLWForm 窗体单元，可直接在 IDE 里设计';
  sLWLoginName   = 'lazarusWeb Login form';
  sLWLoginDesc   = '一个 TLWLoginForm 登录窗体单元，新建即用：' + LineEnding +
    '用户名/密码编辑框与登录/重置按钮已备好（约定名 edUser / edPass，' + LineEnding +
    '基类自动识别），认证逻辑写在生成的 DoLoginEx 里（默认 admin / admin）。' + LineEnding +
    '也可以在窗体设计器里放同名控件，模板检测到后不再自动补建。';
  sLWPaletteTab  = 'lazarusWeb';

const
  { 新建工程时的默认名字（与 Lazarus 自带模板给 project1 / unit1 一个意思）：
    用户第一次保存时在"保存项目"对话框里改名，这三个名字只是初值 ——
    .lpr 的 program 名会被 IDE 自动跟着改，uses 里的 umain 与
    主窗体单元的默认名必须一致，所以两边都用 sLWDefaultUnitName。

    默认名必须带数字：'LWApp' 不能当工程名 —— program LWApp 与 .lpr 里
    uses 的 lwapp（框架核心单元）在 Windows 上（文件名不分大小写）
    直接撞成 FPC "Duplicate identifier: LWAPP"。'LWApp1' 与 lwapp 不
    同名，编译通过；用户自己改成 LWApp 时由保存钩子给出警告。 }
  sLWDefaultProjectName = 'LWApp1';
  sLWDefaultUnitName    = 'umain';
  sLWDefaultFormName    = 'MainForm';

type
  { ---------------------------------------------------------------
    新建工程（两个模板的共同实现）
    ---------------------------------------------------------------
    档位（GUI / nogui）由子类的 GetHeadless 固定，**不放在实例字段里**：
    这样即使 IDE 复制/重建描述符实例，档位也不会丢 —— 之前用可变字段
    时出现过两个模板编出来一模一样（都按 nogui 的 $APPTYPE CONSOLE 生成）
    的问题，改成本质属性后没有可丢失的状态。 }
  TProjectLWAppBase = class(TProjectDescriptor)
  protected
    { True = nogui 档（.lpr 写 $APPTYPE CONSOLE、.lpi 需要 LCLWidgetType=nogui）；
      False = 默认 widgetset 档（$APPTYPE GUI，IDE 里 F9 直接跑） }
    function GetHeadless: Boolean; virtual; abstract;
  public
    function InitProject(AProject: TLazProject): TModalResult; override;
    function CreateStartFiles(AProject: TLazProject): TModalResult; override;
  end;

  { 默认档：正常 GUI 程序，不要黑色控制台窗口 }
  TProjectLWApp = class(TProjectLWAppBase)
  protected
    function GetHeadless: Boolean; override;
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { 部署档：控制台服务程序，无任何窗口 }
  TProjectLWAppNogui = class(TProjectLWAppBase)
  protected
    function GetHeadless: Boolean; override;
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
  end;

  { ---------------------------------------------------------------
    新建工程时在内存里建主窗体单元用的文件描述符
    ---------------------------------------------------------------
    只在向导内部用（VisibleInNewDialog=False），与"新建文件"里的
    "lazarusWeb Form" 不是一回事：这个预置了模板骨架（标题/编辑框/按钮/日志）。

    为什么走文件描述符而不是自己 CreateProjectFile 塞源码：
    只有 DoNewEditorFile 这条标准路径会顺手给单元建好编辑器页和窗体设计器，
    并且把 .lfm 也建成内存缓冲（不落盘）。自己塞源码的单元在 IDE 眼里只是
    一段文本，没有设计器，保存时也不会写出 .lfm。 }
  TLWMainFormFileDesc = class(TFileDescPascalUnitWithResource)
  private
    { 模板标题（.lpr 的 Application.Title 与窗体 Caption） }
    FTitle: string;
    FHeadless: Boolean;
    { CreateSource 给的单元名/窗体名：Initialized 里要用同两个名字整篇重写
      模板源码（IDE 拼的那份只是占位，见 Initialized） }
    FUnitName: string;
    FFormName: string;
  public
    constructor Create; override;
    function GetInterfaceUsesSection: string; override;
    function GetInterfaceSource(const Filename, SourceName,
      ResourceName: string): string; override;
    function GetImplementationSource(const Filename, SourceName,
      ResourceName: string): string; override;
    function GetResourceSource(const ResourceName: string): string; override;
    function Initialized(NewFile: TLazProjectFile): TModalResult; override;
    property Title: string read FTitle write FTitle;
    property Headless: Boolean read FHeadless write FHeadless;
  end;

  { ---------------------------------------------------------------
    新建 -> lazarusWeb Form
    --------------------------------------------------------------- }
  TLWFormFileDesc = class(TFileDescPascalUnitWithResource)
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
    function GetInterfaceUsesSection: string; override;
  end;

  TLWLoginFormFileDesc = class(TFileDescPascalUnitWithResource)
  public
    constructor Create; override;
    function GetLocalizedName: string; override;
    function GetLocalizedDescription: string; override;
    function GetInterfaceUsesSection: string; override;
    function GetInterfaceSource(const Filename, SourceName,
      ResourceName: string): string; override;
    function GetImplementationSource(const Filename, SourceName,
      ResourceName: string): string; override;
    { 新建时直接给出带全部控件的 lfm：设计器里立即看到标题/编辑框/按钮，
      运行时走 lfm 流式加载，字段被回填后 AfterConstruction 不再补建。
      （默认实现返回空串，IDE 只生成空 lfm —— 设计器里就是一张白板。） }
    function GetResourceSource(const ResourceName: string): string; override;
  end;

  { ---------------------------------------------------------------
    保存钩子：工程落盘后补两样 IDE 写不出来的东西
    ---------------------------------------------------------------
    工程在内存里创建，.lpi 由 IDE 保存时按内存模型写出，于是有两样它写不了：

      1. build.bat / build.sh —— 它们不是工程单元，IDE 不管；
      2. nogui 档 .lpi 里的 LCLWidgetType=nogui 宏 —— IDEIntf 没有设置
         工程宏的接口（TLazProject 只暴露编译选项与包依赖），而宏错位会让
         IDE 用 win32 widgetset 编 nogui 工程，运行期随机 AV
         （见 docs/NOTES.md 坑 19 / 坑 43）。

    为什么不能"收到保存通知就立刻补"：虚拟工程的第一次保存（Ctrl+S）走的是
    SaveProject，它的顺序是

        SaveProjectInfo（弹"保存项目"对话框 + 写 .lpi）
        -> 逐个写单元（这时 SaveEditorFile 钩子触发）
        -> SaveProjectInfo（**又写一遍 .lpi**，把宏冲掉）
        -> UpdateProjectAutomaticFiles

    也就是说，单元写完之后我们补的宏，会被最后那次 .lpi 写入覆盖 —— 坑 170
    的现场（C:\3\lwapp1：build.bat 在、.lpi 里一行 LCLWidgetType 都没有，
    同目录 backup/lwapp1.lpi 里却还有我们补的那段）就是这么来的。而且这条
    路径**不经过 DoSaveAll**，所以 AddHandlerOnSavedAll 根本不会触发。

    --- 坑 172：绝对不能在保存事务里弹框 / 重载工程 -------------------
    早先的实现是"钩子只排队，真正的活交给 Application.QueueAsyncCall"，
    以为消息循环空闲时保存早就结束了。事实不是这样：SaveProject 内部会
    ProcessMessages（写单元、刷进度），QueueAsyncCall 排的回调就在那一刻
    被执行 —— 此时 .lpi 已经写过第一遍、而 umain.pas **还没写到盘上**。
    回调里弹的"是否重新加载工程"一旦选"是"，DoOpenProjectFile 会在保存
    事务中间把工程关掉重读，于是 IDE 去打开 .lpi 里登记的 umain.pas，
    盘上没有（还没写）—— 弹出"文件未找到 C:\3\umain.pas"，整个保存
    就此崩掉，工程目录里只剩下半截文件。

    结论（现在的做法）：
      1. 保存钩子**只启动一个 1 秒定时器**，不排队、不弹框、不重载；
      2. 定时器每轮先做"保存写完了吗"的判定 —— 工程里每个属于工程的单元
         都必须已经落盘（TLazProjectFile.GetFullFilename 为空 = 还没落盘）
         且 .lpi 在盘上；没写完就重置计数、下一轮再看；
      3. 要连续两轮都判定"写完了"才动手，避开 SaveProject 末尾那次 .lpi
         重写（坑 171）；
      4. 动手时也只补文件，弹框（重名提醒 / 客户端资源 / 重载询问）都在
         这里，即保存事务确实结束之后。
    补写"缺什么补什么"，重复执行无副作用。 }
  TLWProjectFinalizer = class
  private
    { 上次为哪个工程报过"工程名与框架单元重名"。同一个工程只弹一次 ——
      保存钩子每次保存都会跑，不记一下会连弹好几次 }
    FWarnedFor: string;
    { 上次为哪个工程提示过"nogui 宏要重新打开工程才生效" }
    FHintedFor: string;
    { 上次为哪个工程提示过"客户端资源没拷成功" }
    FClientWarnedFor: string;
    { 兜底定时器：保存钩子只负责启动它，真正的活在保存事务结束后干
      （为什么不能直接干，见类注释里坑 172） }
    FTimer: TTimer;
    { 连续判定"保存已写完"的轮数。要求 >=2 才动手：SaveProject 末尾还会
      再写一遍 .lpi（坑 171），中间隔一轮才不会补了又被冲掉 }
    FStableChecks: Integer;
    { 已经等了几个 1 秒周期。用户中途放弃保存时不能永远等下去 }
    FTries: Integer;
    { 真正干活：写 build.bat/sh、补 nogui 宏、拷客户端资源、工程名撞名提醒。
      True = 处理完毕；False = 保存事务还没结束，下一轮再试 }
    function EnsureExtras: Boolean;
    { 这个工程的所有单元是不是都已经落到盘上了。
      TLazProjectFile.GetFullFilename 为空 = IDE 认为它还没保存过；
      再补一次 FileExists 兜住"IDE 认为写过、其实被删了"的情况。 }
    function UnitsOnDisk(P: TLazProject; out AMissing: string): Boolean;
    { 启动/续期定时器（保存钩子调用；已在等就不重置） }
    procedure QueueEnsure;
    { 定时器到点：先判定保存是否结束，稳定两轮才调 EnsureExtras }
    procedure EnsureOnTimer({%H-}Sender: TObject);
  public
    function FileSaved(Sender: TObject; aFile: TLazProjectFile;
      SaveStep: TSaveEditorFileStep; TargetFilename: string): TModalResult;
    { 保存全部之后（.lpi 此时已落盘）—— 同样只是启动定时器 }
    function SavedAll({%H-}Sender: TObject): TModalResult;
  end;

var
  LWProjectDescriptor: TProjectLWApp = nil;             { GUI 档 }
  LWProjectNoguiDescriptor: TProjectLWAppNogui = nil;   { nogui 档 }
  LWMainFormDescriptor: TLWMainFormFileDesc = nil;
  LWFormDescriptor: TLWFormFileDesc = nil;
  LWLoginFormDescriptor: TLWLoginFormFileDesc = nil;
  LWProjectFinalizer: TLWProjectFinalizer = nil;

{ ================= TProjectLWApp ================= }

constructor TProjectLWApp.Create;
begin
  inherited Create;
  { Name 是 IDE 内部的唯一标识（RegisterProjectDescriptor 强制要求非空，
    否则装包时直接弹 "Descriptor.Name empty" 异常，重复还会被改名成 xxx2）；
    显示名走 GetLocalizedName（sLWProjectName），两者是两回事 }
  Name := 'lazarusWebApp';
end;

constructor TProjectLWAppNogui.Create;
begin
  inherited Create;
  Name := 'lazarusWebAppNogui';
end;

function TProjectLWApp.GetHeadless: Boolean;
begin
  Result := False;
end;

function TProjectLWAppNogui.GetHeadless: Boolean;
begin
  Result := True;
end;

function TProjectLWApp.GetLocalizedName: string;
begin
  Result := sLWProjectName;
end;

function TProjectLWApp.GetLocalizedDescription: string;
begin
  Result := sLWProjectDesc;
end;

function TProjectLWAppNogui.GetLocalizedName: string;
begin
  Result := sLWProjectNoguiName;
end;

function TProjectLWAppNogui.GetLocalizedDescription: string;
begin
  Result := sLWProjectNoguiDesc;
end;

{ 不再重写 DoInitDescriptor：标准模板（TProjectApplicationDescriptor）在这里
  什么也不问，选完模板就直接建"虚拟工程"。所以这里保留基类的 mrOk。 }

function TProjectLWAppBase.InitProject(AProject: TLazProject): TModalResult;
var
  O: TLWNewProject;
  MainFile: TLazProjectFile;
  CO: TLazCompilerOptions;
begin
  Result := inherited InitProject(AProject);
  if Result <> mrOk then Exit;

  O := LWDefaultProject(sLWDefaultProjectName);
  O.Port := 8090;
  O.Headless := GetHeadless;

  { 关键：不设 ProjectInfoFile、不建目录、不写盘 —— 工程保持虚拟状态
    （TProject.IsVirtual 判据就是 ProjectInfoFile 为空）。
    文件名一律用相对名，和 Lazarus 自带 "Application" 模板写 'project1.lpr'
    是同一套做法：相对名在保存时自动落到工程目录下。 }
  { 先摘掉这三个标志：留着 pfMainUnitHasTitleStatement 时 IDE 会往 .lpr 里插
    Application.Title / Application.Scaled 语句，和我们模板自己写的重复
    （模板用 TLWApp.Register 注册窗体，不用 Application.CreateForm）。 }
  AProject.Flags := AProject.Flags -
    [pfMainUnitHasCreateFormStatements, pfMainUnitHasTitleStatement,
     pfMainUnitHasScaledStatement];
  { Title 不设：保持基类的默认值（等价于标准模板的 'project1'），
    保存时 IDE 会按用户定的工程名自动改掉（TitleIsDefault 认这个默认值）。 }

  MainFile := AProject.CreateProjectFile(O.Name + '.lpr');
  MainFile.IsPartOfProject := True;
  AProject.AddFile(MainFile, False);
  AProject.MainFileID := 0;
  MainFile.SetSourceText(LWProjectSource(O));

  CO := AProject.LazCompilerOptions;
  CO.TargetFilename := O.Name;
  CO.TargetFilenameApplyConventions := True;
  CO.UnitOutputDirectory := 'lib' + PathDelim + '$(TargetCPU)-$(TargetOS)';
  { 服务程序：nogui 档要控制台子系统（日志直接进 stdout）；GUI 档要 Windows
    GUI 子系统，否则会跟一个黑窗口 —— 与模板 .lpr 里的 $APPTYPE 一致 }
  CO.Win32GraphicApp := not O.Headless;
  CO.GenerateDebugInfo := True;

  { 依赖运行时包：工程里不用写任何源码路径，搬到别的机器也能编译 }
  AProject.AddPackageDependency('LCL');
  AProject.AddPackageDependency('lwserver');

  Result := mrOk;
end;

function TProjectLWAppBase.CreateStartFiles(AProject: TLazProject): TModalResult;
begin
  { 主窗体单元同样只在内存里建：DoNewEditorFile 会给它开编辑器页、建窗体
    设计器，并把 .lfm 也做成内存缓冲。源码与 .lfm 都要等用户保存才写盘 ——
    这正是 Lazarus 自带模板在 CreateStartFiles 里干的事（那里传的是
    标准的 LCL Form 描述符，这里换成 lazarusWeb 的主窗体描述符）。 }
  LWMainFormDescriptor.Title := LWDefaultProject(sLWDefaultProjectName).Title;
  LWMainFormDescriptor.Headless := GetHeadless;
  Result := LazarusIDE.DoNewEditorFile(LWMainFormDescriptor, '', '',
    [nfIsPartOfProject, nfOpenInEditor, nfCreateDefaultSrc]);
  if Result = mrCancel then
    Result := mrOk;
end;

{ ================= TLWMainFormFileDesc ================= }

constructor TLWMainFormFileDesc.Create;
begin
  inherited Create;
  { 只在"新建工程"内部用，不进"新建文件"对话框 }
  Name := 'lazarusWebProjectForm';
  VisibleInNewDialog := False;
  { IDE 因此认定新单元是窗体：开设计器、生成的基类是 TLWForm、
    保存时自动写出 .lfm（实现段的 R *.lfm 由基类给） }
  ResourceClass := TLWForm;
  { 不给 Application.CreateForm：窗体由 .lpr 里的 TLWApp.Register 注册 }
  UseCreateFormStatements := False;
  { DefaultSourceName 决定新单元的默认名，必须与 .lpr 的 uses 一致；
    DefaultResourceName 决定窗体变量名（.lpr 里写的是 TMainForm） }
  DefaultFilename := sLWDefaultUnitName + '.pas';
  DefaultSourceName := sLWDefaultUnitName;
  DefaultResourceName := sLWDefaultFormName;
  AddToProject := True;
  { 单元只用 lwform（在 lwcore 里），但工程本来就依赖 lwserver（它再依赖
    lwcore）—— 填已有的直接依赖，AddProjectDependencies 不会有任何提示框 }
  RequiredPackages := 'lwserver';
  FTitle := LWDefaultProject(sLWDefaultProjectName).Title;
end;

function TLWMainFormFileDesc.GetInterfaceUsesSection: string;
begin
  Result := 'Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, lwform';
end;

{ 下面三段只是"占位"：IDE 拼出源码后立刻调 Initialized，把整篇换成模板原文。
  占位版也要能通过语法检查（同一份类声明与事件方法名），万一 Initialized
  没跑到，至少设计器还能对上 lfm 里的控件与事件。 }
function TLWMainFormFileDesc.GetInterfaceSource(const Filename, SourceName,
  ResourceName: string): string;
const
  LE = LineEnding;
begin
  FUnitName := SourceName;
  FFormName := ResourceName;
  Result :=
     'type' + LE
    + '  T' + ResourceName + ' = class(TLWForm)' + LE
    + '    lblTitle: TLabel;' + LE
    + '    lblName: TLabel;' + LE
    + '    edtName: TEdit;' + LE
    + '    btnSay: TButton;' + LE
    + '    lblResult: TLabel;' + LE
    + '    mmoLog: TMemo;' + LE
    + '    procedure FormCreate(Sender: TObject);' + LE
    + '    procedure btnSayClick(Sender: TObject);' + LE
    + '  end;' + LE
    + LE
    + 'var' + LE
    + '  ' + ResourceName + ': T' + ResourceName + ';' + LE
    + LE;
end;

function TLWMainFormFileDesc.GetImplementationSource(const Filename, SourceName,
  ResourceName: string): string;
const
  LE = LineEnding;
begin
  Result := '{$R *.lfm}' + LE + LE;
end;

function TLWMainFormFileDesc.GetResourceSource(const ResourceName: string): string;
var
  O: TLWNewProject;
begin
  { 模板 lfm 原文，窗体名用 IDE 给的那个（通常 MainForm，冲突时会是
    MainForm1 —— 类名 T<窗体名>、.lpr 里的 TMainForm 都由它派生） }
  O := LWDefaultProject(sLWDefaultProjectName);
  O.FormName := ResourceName;
  O.Title := FTitle;
  Result := LWFormResourceSource(O);
end;

function TLWMainFormFileDesc.Initialized(NewFile: TLazProjectFile): TModalResult;
var
  O: TLWNewProject;
begin
  Result := mrOk;
  if (FUnitName = '') or (FFormName = '') then Exit;
  { IDE 已经按基类默认版式拼了一份源码，还自动美化过一遍。这里整篇换成
    模板原文：与命令行 tools\lwnew 生成的 umain.pas 逐字节一致 ——
    注释、排版、事件方法体一处不差，两条生成路径只认 lwnewproject 这一份
    模板。本方法在打开编辑器 / 建设计器之前调用，换掉的就是最终内容。 }
  O := LWDefaultProject(sLWDefaultProjectName);
  O.UnitName := FUnitName;
  O.FormName := FFormName;
  O.Title := FTitle;
  O.Headless := FHeadless;
  NewFile.SetSourceText(LWFormUnitSource(O));
end;

{ ================= TLWFormFileDesc ================= }

constructor TLWFormFileDesc.Create;
begin
  inherited Create;
  Name := 'lazarusWebForm';
  { ResourceClass 决定三段：
      1. IDE 认为新单元"是个窗体"，从而打开设计器；
      2. 生成的类声明是 = class(TLWForm)；
      3. 保存时由 IDE 自动写出 .lfm（TFileDescPascalUnitWithResource
         会在实现段写 R *.lfm 编译指令）。 }
  ResourceClass := TLWForm;
  { 不给 Application.CreateForm：窗体由 TLWApp.Register 注册 }
  UseCreateFormStatements := False;
  DefaultFilename := 'unit1.pas';
  DefaultResourceName := 'LWForm';
  VisibleInNewDialog := True;
  RequiredPackages := 'lwcore';
  AddToProject := True;
end;

function TLWFormFileDesc.GetLocalizedName: string;
begin
  Result := sLWFormName;
end;

function TLWFormFileDesc.GetLocalizedDescription: string;
begin
  Result := sLWFormDesc;
end;

function TLWFormFileDesc.GetInterfaceUsesSection: string;
begin
  { 在标准 uses 后面补上窗体相关的 LCL 单元和 lwform，生成的单元直接能编译 }
  Result := inherited GetInterfaceUsesSection +
    ', Forms, Controls, Graphics, Dialogs, StdCtrls, lwform';
end;

{ ================= TLWLoginFormFileDesc ================= }

constructor TLWLoginFormFileDesc.Create;
begin
  inherited Create;
  Name := 'lazarusWebLoginForm';
  { ResourceClass 同 TLWFormFileDesc：IDE 认出"是窗体"并打开设计器，
    生成的类声明基类是 TLWLoginForm }
  ResourceClass := TLWLoginForm;
  { 不给 Application.CreateForm：登录窗体由 lwlogin 框架按会话创建 }
  UseCreateFormStatements := False;
  DefaultFilename := 'unit1.pas';
  DefaultResourceName := 'LoginForm';
  VisibleInNewDialog := True;
  { lwlogin 在 lwserver 包里（lwcore 只含 lwform），两个都要 }
  RequiredPackages := 'lwcore;lwserver';
  AddToProject := True;
end;

function TLWLoginFormFileDesc.GetLocalizedName: string;
begin
  Result := sLWLoginName;
end;

function TLWLoginFormFileDesc.GetLocalizedDescription: string;
begin
  Result := sLWLoginDesc;
end;

function TLWLoginFormFileDesc.GetInterfaceUsesSection: string;
begin
  Result := inherited GetInterfaceUsesSection +
    ', Forms, Controls, StdCtrls, lwform, lwlogin, lwcaptcha';
end;

{ 生成的类：控件字段声明在前（默认 published，lfm 可回填），
  AfterConstruction 负责在字段为空时自动补建控件（见实现段），
  认证回调 DoLoginEx 挂到基类 OnLogin }
function TLWLoginFormFileDesc.GetInterfaceSource(const Filename,
  SourceName, ResourceName: string): string;
const
  LE = LineEnding;
begin
  Result :=
     'type' + LE
    + '  { 登录窗体（TLWLoginForm 子类），新建即用：' + LE
    + '    - 控件已在模板 lfm 里放好：约定名 edUser / edPass / edCode ' + LE
    + '      基类自动识别；TLWCaptcha 就是图形验证码（点图换一张），' + LE
    + '      基类会在提交前自动校验；按钮挂基类的 DoLogin / DoReset；' + LE
    + '    - 认证逻辑写在 DoLoginEx（默认演示账号 admin / admin，' + LE
    + '      真实项目改成查数据库 / LDAP / 权限表）。' + LE
    + '    界面可以整个删掉重画：一个控件都不剩时，基类 TLWLoginForm' + LE
    + '    会在 AfterConstruction 里自动补建账号/密码/验证码/按钮。 }' + LE
    + '  T' + ResourceName + ' = class(TLWLoginForm)' + LE
    + '    lblTitle: TLabel;' + LE
    + '    lblUser: TLabel;' + LE
    + '    lblPass: TLabel;' + LE
    + '    lblCode: TLabel;' + LE
    + '    edUser: TEdit;' + LE
    + '    edPass: TEdit;' + LE
    + '    edCode: TEdit;' + LE
    + '    captcha1: TLWCaptcha;' + LE
    + '    btnOk: TButton;' + LE
    + '    btnReset: TButton;' + LE
    + '  public' + LE
    + '    procedure AfterConstruction; override;' + LE
    + '  published' + LE
    + '    procedure DoLoginEx(Sender: TObject; const AUser, APass: string;' + LE
    + '      var AOk: Boolean; var AErr: string);' + LE
    + '  end;' + LE
    + LE;
end;

{ lfm 源：控件布局与运行时补建版完全一致（同一套坐标）。
  - edUser/edPass 显式 Text = ''：lfm 流式加载时 LCL SetName 会把空
    Text 填成组件名，必须压住（见 NOTES 坑 54）；
  - OnClick 直接引用基类 published 的 DoLogin / DoReset；
  - 窗体尺寸用 Width/Height（窗口外框），与补建版一致。 }
function TLWLoginFormFileDesc.GetResourceSource(
  const ResourceName: string): string;
const
  LE = LineEnding;
begin
  Result :=
     'object ' + ResourceName + ': T' + ResourceName + LE
    + '  Left = 300' + LE
    + '  Height = 270' + LE
    + '  Top = 200' + LE
    + '  Width = 390' + LE
    + '  Caption = ''登录''' + LE
    + '  object lblTitle: TLabel' + LE
    + '    Left = 24' + LE
    + '    Height = 18' + LE
    + '    Top = 18' + LE
    + '    Width = 340' + LE
    + '    Caption = ''登录（演示账号 admin / admin）''' + LE
    + '  end' + LE
    + '  object lblUser: TLabel' + LE
    + '    Left = 24' + LE
    + '    Height = 18' + LE
    + '    Top = 62' + LE
    + '    Width = 60' + LE
    + '    Caption = ''用户名''' + LE
    + '  end' + LE
    + '  object edUser: TEdit' + LE
    + '    Left = 110' + LE
    + '    Height = 26' + LE
    + '    Top = 58' + LE
    + '    Width = 250' + LE
    + '    Text = ''''' + LE
    + '  end' + LE
    + '  object lblPass: TLabel' + LE
    + '    Left = 24' + LE
    + '    Height = 18' + LE
    + '    Top = 102' + LE
    + '    Width = 60' + LE
    + '    Caption = ''密 码''' + LE
    + '  end' + LE
    + '  object edPass: TEdit' + LE
    + '    Left = 110' + LE
    + '    Height = 26' + LE
    + '    Top = 98' + LE
    + '    Width = 250' + LE
    + '    PasswordChar = ''*''' + LE
    + '    Text = ''''' + LE
    + '  end' + LE
    + '  object lblCode: TLabel' + LE
    + '    Left = 24' + LE
    + '    Height = 18' + LE
    + '    Top = 142' + LE
    + '    Width = 60' + LE
    + '    Caption = ''验证码''' + LE
    + '  end' + LE
    + '  object captcha1: TLWCaptcha' + LE
    + '    Left = 110' + LE
    + '    Height = 34' + LE
    + '    Top = 136' + LE
    + '    Width = 110' + LE
    + '    CaptchaLength = 4' + LE
    + '  end' + LE
    + '  object edCode: TEdit' + LE
    + '    Left = 230' + LE
    + '    Height = 26' + LE
    + '    Top = 140' + LE
    + '    Width = 130' + LE
    + '    Text = ''''' + LE
    + '  end' + LE
    + '  object btnOk: TButton' + LE
    + '    Left = 110' + LE
    + '    Height = 30' + LE
    + '    Top = 196' + LE
    + '    Width = 110' + LE
    + '    Caption = ''登 录''' + LE
    + '    OnClick = DoLogin' + LE
    + '  end' + LE
    + '  object btnReset: TButton' + LE
    + '    Left = 250' + LE
    + '    Height = 30' + LE
    + '    Top = 196' + LE
    + '    Width = 110' + LE
    + '    Caption = ''重 置''' + LE
    + '    OnClick = DoReset' + LE
    + '  end' + LE
    + 'end' + LE;
end;

{ 实现段：R 编译指令（*.lfm）与基类 rtRes 行为一致（窗体设计器照常可用），
  后面是补建控件与认证骨架。控件创建走约定名（edUser / edPass），
  这样无论自动补建还是 lfm 设计，TLWLoginForm 都认得 }
function TLWLoginFormFileDesc.GetImplementationSource(const Filename,
  SourceName, ResourceName: string): string;
const
  LE = LineEnding;
begin
  Result :=
     '{$R *.lfm}' + LE
    + LE
    + '{ 界面（含图形验证码）已在模板 lfm 里放好，这里只挂认证回调。' + LE
    + '  万一用户把控件全删了：基类 TLWLoginForm 会在 AfterConstruction' + LE
    + '  里按同一套坐标自动补建一套（AutoBuildUI=True），仍然可用。 }' + LE
    + 'procedure T' + ResourceName + '.AfterConstruction;' + LE
    + 'begin' + LE
    + '  inherited AfterConstruction;' + LE
    + '  OnLogin := @DoLoginEx;' + LE
    + 'end;' + LE
    + LE
    + '{ 认证逻辑：真实项目在这里查数据库 / LDAP / 权限表，' + LE
    + '  并把用户信息存到服务端会话级变量（按 sid 索引）。 }' + LE
    + 'procedure T' + ResourceName + '.DoLoginEx(Sender: TObject;' + LE
    + '  const AUser, APass: string; var AOk: Boolean; var AErr: string);' + LE
    + 'begin' + LE
    + '  AOk := (AUser = ''admin'') and (APass = ''admin'');' + LE
    + '  if not AOk then' + LE
    + '    AErr := ''用户名或密码错误'';' + LE
    + 'end;' + LE
    + LE;
end;

{ ================= TLWProjectFinalizer ================= }

{ 按字节读写：.lpi 是 UTF-8（可能带 BOM），build.bat 是纯 ASCII + CRLF，
  build.sh 是 LF —— 一律不能经过字符串编码转换。 }
function ReadRawText(const FN: string): AnsiString;
var
  fs: TFileStream;
begin
  Result := '';
  try
    if not FileExistsUTF8(FN) then Exit;
    fs := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, fs.Size);
      if fs.Size > 0 then
        fs.ReadBuffer(Result[1], fs.Size);
    finally
      fs.Free;
    end;
  except
    Result := '';
  end;
end;

function WriteRawText(const FN, Text: AnsiString): Boolean;
var
  fs: TFileStream;
begin
  Result := False;
  try
    fs := TFileStream.Create(FN, fmCreate);
    try
      if Text <> '' then
        fs.WriteBuffer(Text[1], Length(Text));
    finally
      fs.Free;
    end;
    Result := True;
  except
    { 补文件失败不影响保存结果，工程本身已经落盘 }
  end;
end;

{ 给工程 .lpi 补上 widgetset 档位（nogui 档）的 XML。

  内容不是在这里手写的 —— 直接用 lwnewproject 里 LWProjectInfo 用的同一份
  生成函数（LWProjectMacroValuesXml / LWProjectSharedMatrixXml）。两个档位
  的差别只在那一处判断，这里只管"把模板的答案搬进 IDE 写的 .lpi 里"，
  避免两处各写一份、又各错一份（坑 170 的教训）。

  nogui 档必须写**两段**，缺一段都不生效（实测 2026-11-17）：

    1. ProjectOptions/MacroValues/Count + Macro1/Name|Value
       —— LoadMacroValues 读这里，给默认构建模式登记宏值；
    2. ProjectOptions/BuildModes/SharedMatrixOptions/Item1
       —— 这才是"启用"宏的地方（Type="IDEMacro"）。只写第 1 段时 lazbuild
       仍用全局 win32 widgetset（日志 LCL=False），写上第 2 段才切到 nogui。

  插入位置：第 1 段在 <BuildModes> 那一行的行首，第 2 段在 </BuildModes>
  那一行的行首（生成的片段自带缩进，所以不管文件本身缩进几个空格都对得齐；
  XMLConfig 按路径取值，元素顺序本身无所谓，但 IDE 自己就是这么排的）。
  工程里真有 <SharedMatrixOptions>（用户动过构建模式矩阵）时不再插第 2 段：
  XMLConfig 只认第一段，插了会被遮蔽。

  AInserted=True 表示这次真的插进去了。IDE 内存里的工程选项不会跟着变，
  调用方要提醒用户：要么重新打开工程，要么用 build.bat（lazbuild）。 }
function EnsureWidgetsetXml(const LpiFile: string; const O: TLWNewProject;
  out AInserted: Boolean): Boolean;
var
  txt: AnsiString;
  le, sMacro, sMatrix, sAdd: string;
  pOpen, pClose: Integer;

  { 生成函数用的是 LineEnding；.lpi 可能来自别的平台，换成文件自己的风格 }
  function FixLE(const S: string): string;
  begin
    Result := S;
    if le = #10 then
      Result := StringReplace(Result, #13#10, #10, [rfReplaceAll]);
  end;

  { APos 所在行的第一个字符位置（用来在整行之前插入，缩进才不会错位） }
  function LineStartOf(const T: AnsiString; APos: Integer): Integer;
  begin
    Result := APos;
    while (Result > 1) and (T[Result - 1] <> #10) do
      Dec(Result);
  end;

begin
  Result := False;
  AInserted := False;
  { GUI 档：模板里没有宏，.lpi 也就该没有 }
  if not O.Headless then Exit(True);
  txt := ReadRawText(LpiFile);
  if txt = '' then Exit;
  { 已经有 LCLWidgetType 就不动：可能是本钩子补过的，也可能是用户自己设的 }
  if Pos('LCLWidgetType', txt) > 0 then Exit(True);
  if Pos('</ProjectOptions>', txt) = 0 then Exit;
  if Pos(#13#10, txt) > 0 then
    le := #13#10
  else
    le := #10;

  sMacro := FixLE(LWProjectMacroValuesXml(O));
  sMatrix := FixLE(LWProjectSharedMatrixXml(O));
  if Pos('<SharedMatrixOptions', txt) > 0 then
    sMatrix := '';

  { '<BuildModes' 不会匹配到 '</BuildModes>'（那个是 '/'） }
  pOpen := Pos('<BuildModes', txt);
  pClose := Pos('</BuildModes>', txt);
  if (pOpen > 0) and (pClose > pOpen) then
  begin
    { 先插靠后的那段，前面那段的位置才不会被挪动 }
    if sMatrix <> '' then
      Insert(AnsiString(sMatrix), txt, LineStartOf(txt, pClose));
    Insert(AnsiString(sMacro), txt, LineStartOf(txt, pOpen));
  end
  else
  begin
    { 很旧的 .lpi 没有 <BuildModes>（那种格式走 LoadOldFormat）：整段补上，
      否则宏值有、启用它的矩阵没有，nogui 依旧不生效 }
    sAdd := sMacro +
      '    <BuildModes>' + le +
      FixLE(LWProjectBuildModeItemXml(O)) +
      FixLE(LWProjectSharedMatrixXml(O)) +
      '    </BuildModes>' + le;
    Insert(AnsiString(sAdd), txt, LineStartOf(txt, Pos('</ProjectOptions>', txt)));
  end;

  Result := WriteRawText(LpiFile, txt);
  AInserted := Result;
end;

{ 判断这个工程是不是本套模板造的：看主程序源码里的两个特征 ——
  TLWApp.Register（本框架独有的窗体注册方式）与 .lpr 里的 $APPTYPE 档位
  （nogui 档写 CONSOLE，GUI 档写 GUI）。IDE 没有对外暴露"工程用的是哪个
  描述符"，源码特征反而是最可靠的判据：新建的工程、重开的旧工程都成立，
  顺手还能把被改坏/被 IDE 重写掉的 .lpi 宏补回来。 }
function LWIsTemplateProject(P: TLazProject; out AHeadless: Boolean): Boolean;
var
  src: string;
begin
  Result := False;
  AHeadless := False;
  if (P = nil) or (P.MainFile = nil) then Exit;
  src := P.MainFile.GetSourceText;
  if Pos('TLWApp.Register', src) = 0 then Exit;
  AHeadless := Pos('{$APPTYPE CONSOLE}', src) > 0;
  Result := True;
end;

{ 找框架的 src/client 目录 —— 不写死任何盘符或安装路径。

  主路径：工程"需要的软件包"里那个 **lwserver**（工程检查器里能看到的那个），
  向 IDE 的包表要它的 TIDEPackage，取包文件路径反推：
      <框架>/src/lwserver.lpk  ->  <框架>/src/client
  这是最靠谱的一条：包的路径是 IDE 自己记着的，跟工程当前选中哪个构建模式、
  编译器搜索路径配得对不对都无关。lwcore（lwapp.pas 所在的包）再兜一次。

  兜底：用 LazarusIDE.FindSourceFile 逐个试框架里的标志文件。

  LWClientAssetsDirNear 会先看包目录下的 client，再看上一级的 client，
  所以 <框架>/src/*.lpk 与 <框架>/src/core/*.pas 两种布局都能命中。 }
function LWFindClientSourceDir(out AHow: string): string;
const
  PkgProbes: array[0..1] of string = ('lwserver', 'lwcore');
  UnitProbes: array[0..0] of string = ('lwapp');
  FileProbes: array[0..2] of string = ('lwapp.pas', 'lwcore.lpk', 'lwserver.lpk');
var
  i: Integer;
  pkg: TIDEPackage;
  u: string;
begin
  Result := '';
  AHow := '';

  { 1. 按包名：工程依赖 lwserver，IDE 一定知道它在哪 }
  for i := Low(PkgProbes) to High(PkgProbes) do
  begin
    if PackageEditingInterface = nil then
    begin
      AHow := AHow + 'PackageEditingInterface=nil; ';
      Break;
    end;
    pkg := PackageEditingInterface.FindPackageWithName(PkgProbes[i]);
    if pkg = nil then
    begin
      AHow := AHow + '包 ' + PkgProbes[i] + '=未安装; ';
      Continue;
    end;
    Result := LWClientAssetsDirNear(pkg.Filename);
    if Result <> '' then
    begin
      AHow := AHow + '包 ' + PkgProbes[i] + '=' + pkg.Filename + ' -> client 命中';
      Exit;
    end;
    AHow := AHow + '包 ' + PkgProbes[i] + '=' + pkg.Filename + '(旁边没有 client); ';
  end;

  { 2. 按单元反查包：lwapp.pas 属于 lwcore }
  for i := Low(UnitProbes) to High(UnitProbes) do
  begin
    if PackageEditingInterface = nil then Break;
    pkg := PackageEditingInterface.FindInstalledPackageWithUnit(UnitProbes[i]);
    if pkg = nil then
    begin
      AHow := AHow + '单元 ' + UnitProbes[i] + '=找不到所属包; ';
      Continue;
    end;
    Result := LWClientAssetsDirNear(pkg.Filename);
    if Result <> '' then
    begin
      AHow := AHow + '单元 ' + UnitProbes[i] + ' -> ' + pkg.Filename +
        ' -> client 命中';
      Exit;
    end;
    AHow := AHow + '单元 ' + UnitProbes[i] + ' -> ' + pkg.Filename +
      '(旁边没有 client); ';
  end;

  { 3. 兜底：让 IDE 在自己的搜索路径里找标志文件 }
  for i := Low(FileProbes) to High(FileProbes) do
  begin
    u := LazarusIDE.FindSourceFile(FileProbes[i], '', []);
    if u = '' then
    begin
      AHow := AHow + FileProbes[i] + '=未找到; ';
      Continue;
    end;
    Result := LWClientAssetsDirNear(u);
    if Result <> '' then
    begin
      AHow := AHow + FileProbes[i] + '=' + u + ' -> client 命中';
      Exit;
    end;
    AHow := AHow + FileProbes[i] + '=' + u + '(旁边没有 client); ';
  end;
end;

{ 向导在 IDE 里跑，出问题时用户没法看到异常，只能凭现象描述 —— 留一份
  简单的日志（%TEMP%/lazarusweb-wizard.log），排查时直接看时间线。
  超过 256 KB 时重开，避免无限增长。 }
procedure LwWizardLog(const S: string);
var
  fn: string;
  fs: TFileStream;
  line: AnsiString;
begin
  try
    fn := IncludeTrailingPathDelimiter(GetTempDir) + 'lazarusweb-wizard.log';
    { 太长就重新开一份（没有 RTL 的"按文件名取大小"，借 TFileStream 读） }
    if FileExistsUTF8(fn) then
    begin
      fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyWrite);
      try
        if fs.Size > 256 * 1024 then
          DeleteFileUTF8(fn);
      finally
        fs.Free;
      end;
    end;
    line := AnsiString(FormatDateTime('yyyy-mm-dd hh:nn:ss ', Now) + S + LineEnding);
    fs := TFileStream.Create(fn, fmCreate or fmOpenWrite or fmShareDenyWrite);
    try
      fs.Seek(0, soEnd);
      if line <> '' then
        fs.WriteBuffer(line[1], Length(line));
    finally
      fs.Free;
    end;
  except
    { 日志写不了不算错误 }
  end;
end;

function TLWProjectFinalizer.UnitsOnDisk(P: TLazProject;
  out AMissing: string): Boolean;
var
  i: Integer;
  f: TLazProjectFile;
  fn, dir: string;
begin
  Result := True;
  AMissing := '';
  if (P = nil) or (P.FileCount = 0) then
  begin
    Result := False;
    AMissing := '<工程里没有文件>';
    Exit;
  end;
  dir := ExtractFilePath(ExpandFileNameUTF8(P.ProjectInfoFile));
  for i := 0 to P.FileCount - 1 do
  begin
    f := P.Files[i];
    if (f = nil) or (not f.IsPartOfProject) then Continue;
    { 内存里可能是绝对路径，也可能是尚未分配目录的相对名（IDE 的约定：
      没保存过的文件只带文件名不带路径），两种都按工程目录解析。
      不直接用 GetFullFilename：它就是返回 Filename，判不出"有没有路径"。 }
    fn := f.Filename;
    if fn = '' then
    begin
      Result := False;
      AMissing := '<单元 #' + IntToStr(i) + ' 还没有文件名>';
      Exit;
    end;
    if not FilenameIsAbsolute(fn) then
      fn := dir + fn;
    if not FileExistsUTF8(fn) then
    begin
      Result := False;
      AMissing := fn;
      Exit;
    end;
  end;
end;

function TLWProjectFinalizer.EnsureExtras: Boolean;
var
  P: TLazProject;
  dir: string;
  O: TLWNewProject;
  hd: Boolean;
  clash: string;
  inserted: Boolean;
  srcClient, err, how, missing: string;
  copied: Integer;
begin
  Result := True;   { 默认"处理完了"，下面任何早退都不再重试 }
  P := LazarusIDE.ActiveProject;
  if (P = nil) or P.IsVirtual or (P.ProjectInfoFile = '') then Exit;
  { 只管本套模板的工程；别的工程一个字节都不碰 }
  if not LWIsTemplateProject(P, hd) then Exit;
  { .lpi 本身也必须在盘上：SaveProject 先写 .lpi 再写单元，反过来不该发生 }
  if not FileExistsUTF8(P.ProjectInfoFile) then
  begin
    LwWizardLog('EnsureExtras: .lpi 还没落盘，等下一轮：' + P.ProjectInfoFile);
    Exit(False);
  end;
  { 关键守卫（坑 172）：所有单元都写完了才继续。没写完就跑下去，轻则补的
    宏被下一次 .lpi 写入冲掉，重则（早先版本的教训）在保存事务里弹框/重载
    工程，把整个保存搞崩。 }
  if not UnitsOnDisk(P, missing) then
  begin
    LwWizardLog('EnsureExtras: 保存还没写完，等下一轮（缺 ' + missing + '）');
    Exit(False);
  end;
  dir := ExtractFilePath(ExpandFileNameUTF8(P.ProjectInfoFile));
  if dir = '' then Exit;
  O := LWDefaultProject(ExtractFileNameOnly(P.ProjectInfoFile));
  O.Headless := hd;
  LwWizardLog(Format('EnsureExtras: lpi=%s headless=%s', [P.ProjectInfoFile,
    BoolToStr(hd, 'nogui', 'gui')]));
  { 工程名撞了框架单元就编不过（program LWApp 与 uses 的 lwapp 同名）。
    IDE 的"保存项目"对话框不查这个，只能在这里提醒一次：宏/脚本照补，
    警告单独弹，用户改个名字就好。 }
  clash := LWProjectNameConflict(O.Name, O.UnitName);
  if (clash <> '') and (FWarnedFor <> P.ProjectInfoFile) then
  begin
    FWarnedFor := P.ProjectInfoFile;
    MessageDlg('工程名与框架单元重名',
      '工程名 "' + O.Name + '" 与单元 ' + clash + ' 同名，编译时会报' +
      LineEnding + '"Duplicate identifier: ' + UpperCase(O.Name) + '"。' +
      LineEnding + LineEnding +
      '请用 文件 → 工程另存为 换个名字（例如 ' + O.Name + '2）再编译。',
      mtWarning, [mbOK], 0);
  end;
  if not FileExistsUTF8(dir + 'build.bat') then
    WriteRawText(dir + 'build.bat', LWBuildBatch(O));
  if not FileExistsUTF8(dir + 'build.sh') then
    WriteRawText(dir + 'build.sh', LWBuildShell(O));

  { 客户端静态资源：运行期按 <exe 目录>/lw/<文件名> 找（扁平部署），
    exe 就在工程目录里，所以拷到 <工程目录>/lw/。
    第一次落盘时拷一份，已经有的文件不覆盖（用户可能改过样式/JS）。 }
  err := '';
  if not FileExists(IncludeTrailingPathDelimiter(dir) + sLWClientSubDir +
    PathDelim + 'lw.js') then
  begin
    how := '';
    srcClient := LWFindClientSourceDir(how);
    copied := 0;
    if srcClient = '' then
      err := '没找到框架的 src/client 目录（IDE 源码搜索未命中：' + how + '）'
    else
    begin
      copied := LWCopyClientAssets(srcClient, dir, err);
      LwWizardLog(Format('  client: src=%s -> %s, copied=%d err=%s',
        [srcClient, dir + sLWClientSubDir, copied, err]));
    end;
    if (srcClient = '') then
      LwWizardLog('  client: ' + how);
    if (err <> '') and (FClientWarnedFor <> P.ProjectInfoFile) then
    begin
      FClientWarnedFor := P.ProjectInfoFile;
      MessageDlg('客户端资源未部署',
        err + LineEnding + LineEnding +
        '请手动把 src/client 下的文件（lw.js / lw.css / alpine.min.js …）拷到：' +
        LineEnding + IncludeTrailingPathDelimiter(dir) + sLWClientSubDir +
        LineEnding + '否则浏览器打开是白屏。',
        mtWarning, [mbOK], 0);
    end;
  end;

  { 站点图标 favicon.ico 放**工程根目录**（不是 lw/）：lwhttp 按
    <root>/favicon.ico → <exe 目录>/favicon.ico 找，exe 就在工程目录里。
    没有它浏览器标签页是空白图标。放在客户端资源外面单独判一次，因为上面
    的 client 拷贝只在"lw/lw.js 还不存在"时跑，而图标可能被用户删掉了。 }
  if not FileExists(IncludeTrailingPathDelimiter(dir) + 'favicon.ico') then
  begin
    if srcClient = '' then
    begin
      how := '';
      srcClient := LWFindClientSourceDir(how);
    end;
    if srcClient <> '' then
      LwWizardLog(Format('  favicon: src=%s -> %s, ok=%s',
        [srcClient, dir + 'favicon.ico',
         BoolToStr(LWCopyFavicon(srcClient, dir), True)]))
    else
      LwWizardLog('  favicon: 没找到 src/client，跳过（' + how + '）');
  end;

  { .lpi 万一还没落盘，EnsureWidgetsetXml 读不到文件会自带返回，不算错 }
  inserted := False;
  EnsureWidgetsetXml(P.ProjectInfoFile, O, inserted);
  LwWizardLog(Format('  widgetset: inserted=%s', [BoolToStr(inserted, True)]));
  if inserted and (FHintedFor <> P.ProjectInfoFile) then
  begin
    { 宏只写进了文件，IDE 内存里的工程选项仍是老的 —— 此刻按 F9 还会用
      win32 widgetset（弹出服务端面板窗口），跟"没生效"一模一样。
      直接问一句要不要重新加载工程：重开后 IDE 从 .lpi 读到 nogui，
      F9 就正常了。不重开也行，用工程目录里的 build.bat 编。

      这一段是坑 172 之后唯一还会碰"重载工程"的地方，安全性靠两个前提：
        1. 调用者是定时器，且已经连续两轮确认所有单元都在盘上（保存事务
           真的结束了）—— 早期版本在保存事务中间重载，直接把还没落盘的
           umain.pas 弄丢，弹出"文件未找到"；
        2. 必须用户点"是"才重载，默认按钮是"否"。 }
    FHintedFor := P.ProjectInfoFile;
    if MessageDlg('nogui 档：重新加载工程后生效',
      '已为工程写入 LCLWidgetType=nogui（' + ExtractFileName(P.ProjectInfoFile) + '）。'
      + LineEnding + LineEnding +
      'IDE 内存里的工程选项不会自动跟着变，现在按 F9 仍然会用 win32 '
      + 'widgetset 编译（会弹出服务端面板窗口）。' + LineEnding + LineEnding +
      '现在关闭并重新加载本工程吗？（文件已全部保存，安全）' + LineEnding +
      '选"否"：请用工程目录里的 build.bat 编译，或下次打开工程时自动生效。',
      mtConfirmation, [mbNo, mbYes], 0) = mrYes then
    begin
      LwWizardLog('  reload project to apply nogui');
      try
        LazarusIDE.DoOpenProjectFile(P.ProjectInfoFile,
          [ofProjectLoading, ofQuiet]);
      except
        { 重开失败就维持现状：文件已经是正确的，下次打开自然生效 }
      end;
    end;
  end;
end;

procedure TLWProjectFinalizer.QueueEnsure;
begin
  { 保存过程里什么都不做，只保证定时器在跑（坑 172）。
    已在等就不重置计数：一轮保存里会连着触发好几次 SaveEditorFile 钩子，
    重置的话永远等不到"稳定两轮"。 }
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    { 0.5 秒一轮：两轮"写完了"才动手，所以保存后约 1 秒补 build.bat 与宏。
      再长会让用户保存完立刻 F9 撞上"宏还没补"的空窗；再短则容易在
      SaveProject 末尾那次 .lpi 写入之前就动手（坑 171）。 }
    FTimer.Interval := 500;
    FTimer.OnTimer := @EnsureOnTimer;
  end;
  if FTimer.Enabled then Exit;
  FStableChecks := 0;
  FTries := 0;
  FTimer.Enabled := True;
end;

procedure TLWProjectFinalizer.EnsureOnTimer({%H-}Sender: TObject);
var
  P: TLazProject;
  missing: string;
  finished: Boolean;
begin
  FTimer.Enabled := False;
  Inc(FTries);
  if FTries > 120 then
  begin
    { 一分钟（120 轮 × 0.5 秒）还没等到"写完"：多半是用户取消了保存，
      或者工程被切走了。不弹任何框（正在保存/加载时弹框会重入 IDE），
      只留一行日志。 }
    LwWizardLog('EnsureOnTimer: 放弃——保存似乎一直没有结束');
    Exit;
  end;

  try
    P := LazarusIDE.ActiveProject;
    if (P = nil) or P.IsVirtual or (P.ProjectInfoFile = '') then
      Exit;   { 没有工程可管，不用再等 }
    finished := FileExistsUTF8(P.ProjectInfoFile) and UnitsOnDisk(P, missing);
  except
    finished := False;
  end;

  if not finished then
  begin
    { 保存事务还没走完（.lpi 未写或单元未落盘）—— 重置稳定计数，下一轮再看 }
    FStableChecks := 0;
    FTimer.Enabled := True;
    Exit;
  end;

  Inc(FStableChecks);
  if FStableChecks < 2 then
  begin
    { 再等一轮：SaveProject 末尾还会再写一次 .lpi（坑 171），
      这一轮之间没有新的写入，才说明真的结束了 }
    FTimer.Enabled := True;
    Exit;
  end;

  FStableChecks := 0;
  try
    EnsureExtras;
  except
    { 补不出来不能让 IDE 崩：工程本身已经落盘了 }
  end;
end;

function TLWProjectFinalizer.FileSaved(Sender: TObject;
  aFile: TLazProjectFile; SaveStep: TSaveEditorFileStep;
  {%H-}TargetFilename: string): TModalResult;
begin
  Result := mrOk;
  if SaveStep <> sefsAfterWrite then Exit;
  if (aFile = nil) or not aFile.IsPartOfProject then Exit;
  QueueEnsure;
end;

function TLWProjectFinalizer.SavedAll({%H-}Sender: TObject): TModalResult;
begin
  Result := mrOk;
  QueueEnsure;
end;

{ ================= 注册 ================= }

procedure Register;
begin
  { 1. 窗体基类：TLWForm / TLWLoginForm 不是"能拖到窗体上"的组件，
    不进组件面板；只做两件事：
      - RegisterClass：IDE 读 .lfm 时按类名 GetClass 能找到它们；
      - RegisterDesignerBaseClass：IDE 才用窗体设计器打开它们的后代，
        同时这也是解析 lfm 祖先类名（TLWLoginForm 只出现在祖先位置）
        的查找目标 —— 正是坑 64 里唯一命中过的两条路。 }
  RegisterClass(TLWForm);
  RegisterClass(TLWLoginForm);
  FormEditingHook.RegisterDesignerBaseClass(TLWForm);
  FormEditingHook.RegisterDesignerBaseClass(TLWLoginForm);

  { 2. 新建工程向导：两个模板，差别只有 widgetset 档位与 .lpr 的 $APPTYPE。
    注册顺序 = 新建工程对话框里的显示顺序；GUI 档调试最顺手，放前面。
    档位写死在类里（TProjectLWApp / TProjectLWAppNogui），传参设标志的
    老做法在实例被 IDE 复制时会丢档位，见坑 170。 }
  LWProjectDescriptor := TProjectLWApp.Create;
  RegisterProjectDescriptor(LWProjectDescriptor);
  LWProjectNoguiDescriptor := TProjectLWAppNogui.Create;
  RegisterProjectDescriptor(LWProjectNoguiDescriptor);

  { 2b. 新建工程时在内存里建主窗体单元用的描述符：只在向导内部用，
      不进"新建文件"对话框（VisibleInNewDialog=False） }
  LWMainFormDescriptor := TLWMainFormFileDesc.Create;
  RegisterProjectFileDescriptor(LWMainFormDescriptor);

  { 2c. 保存钩子：工程落盘之后补 build.bat / build.sh 与 nogui 档的
      widgetset 宏 —— 这两样 IDE 的工程模型写不出来，只能等 .lpi 有了
      目录再补。两个钩子都**只启动一个定时器**，绝不在保存事务里干活：
        SaveEditorFile：每个单元写盘后触发
        SavedAll：保存全部之后触发（这条路径虚拟工程第一次保存不会走）
      真正的补写在定时器里，且要先确认"所有单元都已落盘 + 连续两轮稳定"，
      详见 TLWProjectFinalizer 的类注释（坑 171 / 172）。 }
  LWProjectFinalizer := TLWProjectFinalizer.Create;
  LazarusIDE.AddHandlerOnSaveEditorFile(@LWProjectFinalizer.FileSaved);
  LazarusIDE.AddHandlerOnSavedAll(@LWProjectFinalizer.SavedAll);

  { 3. 新建文件 -> lazarusWeb Form / lazarusWeb Login form }
  LWFormDescriptor := TLWFormFileDesc.Create;
  RegisterProjectFileDescriptor(LWFormDescriptor);
  LWLoginFormDescriptor := TLWLoginFormFileDesc.Create;
  RegisterProjectFileDescriptor(LWLoginFormDescriptor);

  { 5. 组件面板：只放能拖到窗体上的控件。
    RegisterComponents 内部会 RegisterClass，IDE 读 lfm 因此能找到这些类 ——
    这是"带自定义控件的窗体能在设计期打开"的前提，缺了就报未知类。
    TLWReport 是非可视 TComponent，注册类名但不进面板。

    窗体基类（TLWForm / TLWLoginForm）不进面板：它们不是"往窗体上拖"的
    组件，而是向导生成的窗体基类，见上面第 1 段。曾经靠面板注册来顺带
    解决祖先类名解析（坑 64），现在改为 RegisterDesignerBaseClass ——
    SearchComponentClass 的查找顺序里，"设计期基类"排在面板注册表之后
    同样能命中，且不会在面板上多出两个拖不下来的条目。 }
  RegisterComponents(sLWPaletteTab, [
    { 图形验证码：拖到 TLWLoginForm 上即生效（基类自动找到它并校验输入；
      约定名 edCode 的编辑框当输入框，也可以自己指定 LoginCodeEdit）}
    TLWCaptcha,
    TLWFileUpload,
    { 移动端拍照：TLWFileUpload 的专用后代，点了唤起系统相机，
      拍完走同一条上传通道（见 lwcamera 单元头） }
    TLWCamera,
    TLWDBGrid, TLWDBNavigator,
    TLWChart, TLWGauge, TLWColorPicker,
    TLWHTMLFrame, TLWPDFFrame,
    { 左侧折叠菜单。它是 TMenu 的后裔（非可视组件）：
      - 拖到窗体上落在非可视组件栏，选中后可在对象观察器里改
        SideWidth / ItemHeight / HeaderCaption / FirstGroupOpen；
      - 双击组件（或右键 "Menu Editor…"）弹出 IDE 原生菜单编辑器 ——
        IDE 用 RegisterComponentEditor(TMenu, TMainMenuComponentEditor)
        按继承查找，Edit 里就是 ShowMenuEditor(Component as TMenu)，
        增删菜单项、拖成子菜单、设 Caption/ShortCut/Checked、
        "Add icon from file…" 设图标、挂各叶子项的 OnClick 全都一样；
      - lfm 里就是这么存的（object 侧栏: TLWSideMenu + 嵌套 TMenuItem），
        运行时由 lwwriter 序列化成前端侧栏。 }
    TLWSideMenu]);
  RegisterClass(TLWReport);
end;

initialization
  { 组件面板图标：24x24 PNG（icons/*.png），资源名 = 组件类名
    （RegisterComponents 注册的类，IDE 按类名在 LazarusResources 里找
    'TLWxxx' PNG，找不到才落默认方块）。只有进面板的控件才需要图标；
    TLWForm / TLWLoginForm 已不在面板上，图标也一并去掉了。
    改图标后用 lazres 重新生成：
      cd icons && python gen_icons.py
      ../ 下执行：lazres lwdesign_icons.lrs TLWFileUpload.png TLWDBGrid.png
        TLWDBNavigator.png TLWChart.png TLWGauge.png TLWColorPicker.png
        TLWHTMLFrame.png TLWPDFFrame.png TLWSideMenu.png }
  {$I lwdesign_icons.lrs}

end.
