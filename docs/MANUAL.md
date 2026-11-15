# lazarusWeb 使用手册

> 版本基准：LW_VERSION 0.9.0（`src/core/lwbase.pas`），2026-11-13 整理。
> 分两篇：**使用篇**（跑 demo、写程序、部署、排障）与**开发篇**（读码、
> 调试、扩展、测试）。细节以各专题文档为准，本文负责把它们串成一条路。

---

# 第一篇 使用篇

## 1. 这是什么

lazarusWeb 让一个普通的 Lazarus/FPC 桌面程序**不改架构**跑进浏览器：

- 业务窗体基类从 `TForm` 改成 `TLWForm`（真实 TForm 后代），`.lfm`、事件、
  业务代码原样保留；
- 编译为 `--ws=nogui` 无头服务（虚拟显示器补丁 `lwws.pas`）；
- 服务端每个浏览器页签持有一棵真实 LCL 控件树，事件经 HTTP/WebSocket
  回来后 RTTI 派发给真实控件事件；`ShowModal`/`ShowMessage`/`TOpenDialog`
  自动改道成浏览器模态框，服务端真的阻塞等待；
- 浏览器端由 `lw-alpine.js`（Alpine.js 3.14.9，**默认**）或 `lw.js`
  （Ext JS x.x.x，可选）渲染并按 id 对账增量更新；`--patch=1` 时事件只回
  2~4KB 差量。

对标商业产品 uniGUI。技术总览见 `docs/ARCHITECTURE.md`。

## 2. 环境与构建

工具链：FPC 3.3.1 + Lazarus（本机在 `c:\111\fpc`、`c:\111\lazarus`）。
`build.bat` 自动探测 lazbuild（环境变量 `LAZBUILD` → Program Files →
`C:\111\lazarus`）。

```
build.bat              :: 编译全部 10 个 demo（lazbuild -B --ws=nogui）
build.bat grid         :: 只编译 demos\grid（db→dbdemo、files→filedemo 自动识别）
```

要点：

- **必须带 `-B`**：lazbuild 不跟踪 `.lfm` 依赖，改了窗体不加 `-B` 会静默
  链接旧 `.o`（这是最常见的"改了没生效"）；
- 编译前**先关掉正在跑的 exe**，否则报 "Can't create object file (error 5)"；
- `build.bat` 必须保持 ASCII + CRLF（cmd.exe 解析 UTF-8 中文注释会挂）；
- 产物落在各 demo 目录本身（如 `demos\db\dbdemo.exe`）；
- Linux/macOS 用 `build.sh`。

## 3. 跑第一个 demo

```
demos\multi\multi.exe --port=8090        :: 菜单/多标签/同步模态
demos\db\dbdemo.exe --port=8095          :: SQLite 增删改查（需 demos\db\sqlite3.dll）
demos\files\filedemo.exe --port=8096     :: 上传/下载
demos\dbaware\dbaware.exe --port=8110    :: DB 感知控件全家桶
start-demo.bat                           :: 前台跑 dbdemo（默认 8092，Ctrl+C 停）
start-gui.bat                            :: GUI 版 dbaware_gui.exe（弹服务端面板）
```

浏览器打开 `http://127.0.0.1:8090/`。

demo 一览（可执行入口全在 `demos/`，框架本体是库不是 exe）：

| demo | 演示内容 |
|---|---|
| hello | 最小示例（一个窗体一个按钮） |
| grid | 表格 |
| multi | 菜单/多页签/同步模态往返 |
| db | SQLite 增删改查（工程名 dbdemo） |
| files | 上传下载 |
| dbaware | DB 感知全家桶（dbaware.lpi 控制台版 + dbaware_gui.lpi GUI 版） |
| dialogs | 对话框改道 |
| controls | 控件陈列 |
| login | 登录/权限框架 |
| gallery | 全功能画廊（压测基线，附 lwperf/lwdump） |
| audit | lfm 链路审计演示（auditdemo） |

## 4. 写你自己的程序

最小改造（三步）：

```pascal
// 1) 窗体基类改一行
TMainForm = class(TLWForm)          // 原来是 class(TForm)

// 2) 工程文件启动代码
Application.Initialize;
TLWApp.Register(TMainForm);         // 注册窗体（可多个，--form= 选默认）
TLWApp.Run;                         // 起 HTTP 服务

// 3) 工程编译选项加 -dLCLnogui（--ws=nogui）
```

- 对话框不用改：`ShowMessage` / `MessageDlg` / `InputQuery` / `TOpenDialog`
  由 `lwdlg.pas` 自动改道浏览器；
- 数据库控件直接绑 `TDataSource`，行为与桌面一致；SQLite 三条硬规则见
  README「数据库应用」节（VARCHAR 列、显式 Commit、编辑态不下发网格行）；
- 自定义 AJAX 端点：`TLWApp.AddAjax(name, handler)`（对应 uniGUI 的
  AddAjaxProcedure），第三方 JS 直接 fetch `/lw/ajax/<名字>`；
- 登录：`TLWApp.SetLogin(TXxxLoginForm)` 一行启用，见 `demos/login/`；
  图形验证码见下面「登录窗体的图形验证码」；
- 图表 `TLWChart`、报表 `lwreport`（HTML/CSV/XLSX）、富内容 `TLWHTMLFrame`
  /`TLWPDFFrame`、仪表 `TLWGauge`、取色器 `TLWColorPicker` 都是框架自带控件；
- 定时器用 **TFPTimer**（必须 `UseTimerThread=True`）——nogui 下 TTimer
  不可用。

现有工程一键迁移：

```
tools\lwconvert.exe <项目目录> --convert <输出目录>
tools\lwconvert_gui.exe                :: GUI 版：选目录→分析/转换→看报告
```

改写内容：`.pas` 基类与 uses、`.lpr` 启动代码、`.lpi` 重新生成为 nogui
工程，附控件支持度报告。IDE 里也有向导：设计期包 `lwdesign`（New Project
两个模板 + New Form + 组件面板）。

### 登录窗体的图形验证码（TLWCaptcha）

TLWLoginForm 的验证码是「拖一个控件就启用」，不写一行代码：

1. 组件面板 **lazarusWeb** 页把 `TLWCaptcha` 拖到登录窗体上
   （它就是可视控件，尺寸 = 图片尺寸，默认 110×34）；
2. 再放一个 `TEdit` 当输入框，名字用约定的 **`edCode`**。
   不按约定命名也行：基类先找名字里带 `code` / `captcha` / `vcode`
   的编辑框，最后退化成「除用户名、密码之外的第一个 TEdit」；
3. 完事。`TLWLoginForm.TryLogin` 会**先验码、再验账号密码**（顺序不能反：
   先查账号就等于给暴力枚举开后门），码错推一条 Toast 并自动换一张图。

细节：

- 比较忽略大小写和首尾空格；**一枚码只允许试一次**（比完即作废，
  失败自动换图），同一张图无法反复猜；
- 「点图片换一张」是纯前端动作（`src` 后追加 `&r=<时间戳>`），
  不占会话执行锁、不等一次往返；服务端见到 `r` 就重新生成答案。
  服务端主动换图（登录失败、业务代码调 `RefreshCaptcha`）走的是
  版本号 `&v=`，补丁里 `src` 变了浏览器才会重拉；
- 图片是服务端用内置 5×7 点阵字模 + FPImage 现画的 PNG：零字体、
  零 widgetset 依赖，nogui 档一样出图；
- 深色主题不重画第二张图，客户端用 `filter: invert(...)` 反相，
  所以切换主题不会多一次请求；
- 不想用：窗体上不放 `TLWCaptcha` 即可（**老工程完全不受影响**，
  验证码只在窗体上真有这个控件时才校验），或把 `RequireCaptcha`
  设成 `False`；
- 想调：`Left/Top/Width/Height` 定位置与大小，`CaptchaLength`（2..8，
  默认 4）定字符数；业务代码可调 `RefreshCaptcha` 主动换图
  （例如账号被锁定后强制换码）；
- 排障：设环境变量 `LW_CAPTCHA_DEBUG=1` 启动，服务端把
  `[lw] captcha <令牌> = <答案>` 打到 stderr —— 用来分清到底是
  「码不对」还是「图不对」（生产环境别开）。

### 登录窗体开箱即用：新建就有验证码

两种新建方式都自带验证码，不用自己摆控件、不用写校验代码：

- **IDE 文件 → 新建 → `lazarusWeb Login form`**：模板 .lfm 里已经放好
  `lblCode` / `captcha1` / `edCode`（还有两个按钮挂好基类的
  `DoLogin` / `DoReset`），改了设计期包记得在 IDE 里重编一次；
- **新建普通窗体、基类改成 `TLWLoginForm`（或 `SetLogin(TLWLoginForm)`
  直接用基类）**：窗体上一个控件都没有时，基类在 `AfterConstruction`
  里按同一套坐标自动补建 用户名 / 密码 / 验证码 / 两个按钮
  （`AutoBuildUI`，默认开）。设计期看不到这套控件，但跑起来就有；
  一旦你自己摆过任何控件（lfm 或 `FormCreate` 里建的），它就不再插手。

### 登录会话什么时候失效

sid 存在 **sessionStorage**（`lw.sid`）里，不是 localStorage，也不是 cookie：

- 刷新页面 —— 还在同一个标签页里，不会刷一下就掉登录；
- **关掉这个标签页 —— sessionStorage 随页签销毁，下次打开必须重新登录**
  （"关标签页即退出"，与桌面程序"关窗口 = 退出"同一个心智）；
- 关掉浏览器 —— 当然也退出；
- **浏览器"启动时恢复上次打开的网页"也一样退出**：恢复会话会把
  sessionStorage 连同 sid 一起还原，所以客户端在 `pagehide` 留一枚
  墓碑（`lw.bye` = 卸载时刻）。卸载到下一次加载只隔几十毫秒的算"刷新"，
  保持登录；隔了 3 秒以上才回来的（= 中间关过窗口）不认旧 sid，重新登录。
  判据用 `performance.timeOrigin`（本次导航开始的时刻）减去墓碑时刻，
  页面自己加载多久不计入，所以服务器慢也不会把刷新误判成关过窗口。
  阈值 `BYE_GRACE_MS = 3000`，写在 `lw-alpine.js` / `lw.js` 里；
- 每个标签页各自一个会话：同一浏览器开第二个标签页是**新会话**，
  不会自动共享上一页的登录身份（要共享就显式带着同一个 sid 打开，
  框架的 `/lw/api/attach` 仍然在，见 `docs/ARCHITECTURE.md` 2.3）；
- 不带端口名：sessionStorage 本来就按源（协议+主机+端口）隔离，
  同机跑多个 demo 天然互不干扰。

要「记住我」（跨页签、跨浏览器重启都保持登录），在页面里设
`localStorage['lw.persist'] = '1'`；调试时想强制开新会话，URL 加
`?fresh=1`。老版本留在浏览器里的会话 cookie（`lw_sid_<端口>`）
会在启动时被顺手清掉，不会影响新语义。

### 状态栏（TStatusBar）：分格宽度/对齐都照 LFM 画

把 `TStatusBar` 拖到窗体上（默认 `Align=alBottom`），在 IDE 里设
`Panels`（每格的 `Text` / `Width` / `Alignment` / `Bevel`），浏览器端就是
一条和桌面端同构的分格栏：

- **高度** 取 `TStatusBar.Height`，按窗体的 `DesignTimePPI / 当前 PPI`
  折算（144PPI 设计、96PPI 运行时 → 34 变 23），和子控件坐标同一把尺子；
- **分格宽度** 用 `Panels[i].Width`，**最后一格延到右边缘**（LCL 的
  `SB_SETPARTS` 规则）；格与格之间有 1px 分隔线，`Bevel=pbNone` 的格子没有；
- **对齐** `taLeftJustify / taRightJustify / taCenter` 分别映射到
  `text-align`；文本太长按格宽裁掉（`ellipsis`），不会撑开格子；
- 状态栏宽度 = 客户区宽度：窗体外框用 inset 阴影画，不占盒模型
  （否则客户区比 LFM 的 `Width` 少 2px，`Align=alNone` 的容器会溢出）；
- `SimplePanel=True` 时只显示 `SimpleText`（与 LCL 一致）；
- 文本由业务代码写：`stbMain.Panels[0].Text := '就绪';` —— 服务端改了，
  下一次补丁就把新文本送到浏览器（`demos/multi` 的第二格显示行数）。

需要自定义样式时改 CSS 变量或 `.lw-statusbar` / `.lw-status-item` 两条规则，
不影响服务端。

### 多级表头（TLWDBGrid.HeaderGroups）

LCL 的 `TDBGrid` 表头只有一行，要"多表头"用框架扩展的 `TLWDBGrid`（lfm 里
网格类名就写 `TLWDBGrid`，FPC 的 GetClass 只认精确类名）：

```pascal
uses lwdbgrid;

with grdMain.HeaderGroups do
begin
  Add('基本信息|0-2');     // 标题|起-止：起/止是"可见列"下标（0 起、含止）
  Add('价格与库存|3-5');
end;
// 没写进任何分组的列自己贯通两行（上下两行合成一格）
```

- 隐藏列（`Visible=False`）不占列号，分组按可见列从左数；
- 分组表头点击不产生 `OnTitleClick`（跨列标题没有唯一列），叶子表头照常回发；
- 两行表头整体粘在网格顶部，滚动时不会散开；
- 演示见 `demos/db` 与 `demos/gallery`（数据感知 / 大表分页两个页签）。

### Caption 里的 `&`（加速键 / 助记符）

跟 LCL 一样，`Caption := '确定(&O)'` 在网页上显示成 **确定(O)**，`O` 带下划线，
按 `Alt+O` 等于点了这个按钮——`&` 不会露出来。规则是**按控件**的：

- 解析：TLabel、TStaticText、按钮族、TCheckBox/TRadioButton、
  TRadioGroup/TCheckGroup（标题与选项）、TGroupBox、TPageControl/TTabControl
  页签、TMenuItem；
- 不解析：**TPanel.Caption**（`TCustomPanel.ShowAccelChar` 默认就是 False）、
  显式 `ShowAccelChar := False` 的任何控件、TListBox/TComboBox/TCheckListBox
  的 `Items`、`TStatusBar.Panels[].Text`、窗体标题；
- 想写字面 `&` 就写两个：`'A && B'` → `A & B`。

演示：`demos/accel`（每类控件一个，点一下回显到日志标签），
验收：`tests/cdp_accel_audit.py`（Alpine + Ext 共 114 项断言）。

## 5. 配置

命令行参数（完整表以 `src/core/lwapp.pas` 的 `--help` 为准）：

```
--config=path  --port=  --root=  --form=  --client=ext|alpine  --ext=
--extdir=  --theme=  --title=  --timeout=  --trust-proxy  --ajax-cors
--verbose  --nogui  --patch=1  --log=path  --help
```

INI 配置（模板 `lazarusWeb.ini.sample`，放 exe 旁改名 `<exe名>.ini` 或
`lazarusWeb.ini`）：`Port` / `Theme` / `ExtDir` / `Patch` / `Client`。
优先级：**内置默认 < 配置文件 < 命令行**。编码须 UTF-8 或纯 ASCII。

渲染层二选一（**默认 Alpine.js**：`--client` 不指定时自动探测——两套都
可用优先 alpine，只有一套用在那套；alpine 文件内置恒可用，所以实际默认
就是 alpine）：

- `alpine`（默认）：Alpine.js 3.14.9（内置 `src/client/alpine.min.js`），
  **不需要 ext 目录**，部署最轻；
- `ext`：Ext JS，需要 `ext-x.x.x/` 目录（约 75MB）；`--client=ext`、
  INI `Client=ext` 或 URL `?client=ext` 显式启用。协议两者完全一致。

### 5.1 Alpine 渲染层的配色（亮色 / 深色 / 跟随系统）

只有 Alpine 渲染层有这一套（Ext 层仍用 `--theme=` 选 Ext 主题）：

- 窗体标题栏右侧有 ☀/☾/◐ 按钮，点开三选一：**亮色 / 深色 / 跟随系统**；
  选择存 `localStorage['lw-theme']`，刷新、多标签页保持一致；
- "跟随系统" 监听 `prefers-color-scheme`，系统切深色时页面即时跟着变；
- 设计期可在对象检查器设窗体属性 `LWTheme`（`twAuto`/`twLight`/`twDark`，
  缺省 `twAuto`）作为**首次默认值**；用户手动选过之后以用户本地选择为准；
- 代码里想强制切换：`LW.theme.set('dark')` / `$lwTheme.set('light')`
  （`LW.theme.get()` 读偏好，`LW.theme.current()` 读实际生效值）；
  不想显示标题栏按钮：`LW.theme.button(false)`；
- 配色全在 `src/client/lw-alpine.css` 顶部两块 CSS 变量（`:root` 与
  `html[data-lw-theme="dark"]`），改主题只改颜色值，不用动组件规则。

## 6. 部署

最小目录（自包含，**默认 Alpine.js 渲染层，不需要 ext 目录**）：

```
yourapp.exe
src\client\alpine.min.js    Alpine.js 本体（44KB，defer 加载，不走 CDN）
src\client\lw-alpine.js     渲染/协调器（177KB）
src\client\lw-alpine.css    样式，含亮/暗主题 CSS 变量（41KB）
favicon.ico                 （可选：浏览器标签图标）
```

三个 alpine 文件**缺一不可**：少 `alpine.min.js`（或 `lw-alpine.js`）会被
自动探测判为 alpine 不可用而回退 ext；少 `lw-alpine.css` 页面能跑但没有任何
样式。文件可平铺放（与 exe 同目录或 `lw\` 子目录均兼容，查找顺序见 README
「部署」节的扁平/半扁平布局表）。

Ext JS 渲染层为**可选**（默认不部署）：需要时把 `ext-x.x.x\` 放到 exe 旁
（完整约 75MB；精简版约 23MB，见 `tools\make_ext_min.bat`），并用
`--client=ext` 显式切换，前端文件换成 `lw.js` + `lw.css`。

### 站点图标（favicon）

浏览器标签上的小图标不靠框架画，**放一个 `favicon.ico` 文件即可**：

- 查找顺序：`--root` 指定目录 → exe 同目录 → 都没有时 `/favicon.ico` 回 204
  （浏览器显示默认图标，不报错）；
- 命中时返回 200 + `image/x-icon` + `Cache-Control: public, max-age=86400`
  （文件级缓存即可，改图标后用户侧最多一天内生效；**Ctrl+F5 立即刷新**）；
- Ext 版与 Alpine 版两套外壳的 HTML head 都已带
  `<link rel="icon" href="/favicon.ico" type="image/x-icon">`，无需改前端；
- 图标建议做多尺寸 ico（16/32/48px），SVG 不经转换在部分浏览器不生效；
- 排障：如果之前部署期间访问过（当时回 204），浏览器可能把空响应缓存了——
  强刷一次或关掉标签重开即可；
- 反向代理无需为 favicon 配置任何转发规则（由应用自身直答，不经 worker）。

**注意**：升级自旧版本时用户浏览器很可能缓存了旧 204 空响应，发布说明里
提醒一次 Ctrl+F5。

- 应用进程只说 HTTP（无 TLS）；HTTPS 由 nginx/Caddy 反代终结，完整示例
  在 `deploy/nginx.conf`、`deploy/Caddyfile`（含 `/lw/ws` Upgrade、
  `/lw/api/poll` 不缓冲、100MB 上传上限、`/ext/` 缓存）；
- 反代后面加 `--trust-proxy`（日志里的 IP 才是真实客户端）；
- 健康探针 `GET /lw/healthz`；
- 单机多 worker：用自带负载器 `tools\lwhyper.exe`（对标 uniGUI Hyper
  Server：worker 守护 + 反代 + sid 粘性 + WS 透传 + 崩溃重启），完整用法
  见 `docs/WHYPER.md`；强烈建议 worker 参数加 `--patch=1`；
- nginx 集群必须粘性会话（`ip_hash`）——会话在进程内存，Redis 外置未做；
- Linux：`build.sh` 编译，工程 uses 里加 `cthreads`，装 libsqlite3，
  systemd 示例见 `deploy/README.md`。

## 7. 容量与性能

- 单事件（全量输出）约 6.3ms → 开增量补丁后 4.3~6.3ms；
- 单进程吞吐：全量约 57.9 事件/秒，`--patch=1` 后 150~163 事件/秒；
- 舒适区 10~20 个活跃用户，40 为上限；空闲会话可挂 200+（约 1MB/会话）；
- 横向扩展：lwhyper N worker ≈ N×150 事件/秒（workers 建议核数/2）；
- 实测方法与数据见 `docs/BENCH.md`，优化路线见 `docs/SCALE.md`。

## 8. 常见问题（排障速查）

| 现象 | 原因/解法 |
|---|---|
| 改了窗体没生效 | 重编译没带 `-B`；或 exe 还在跑导致链接失败（先关 exe） |
| lfm 读流失败 Unknown property | LW 控件没有 TabOrder 等 published 属性，lfm 里删掉；TBufDataset FieldDefs 别进 lfm |
| TDBNavigator 建崩 | lfm 写真实类名 `TLWDBNavigator` 并 `RegisterClass(TLWDBNavigator)`（坑 29/41） |
| DBGrid 显示 (MEMO) | SQLite 字符串列改 `VARCHAR(n)`（坑 9） |
| 保存"成功"重启丢数据 | `sqoAutoApplyUpdates` 不提交事务，Post/Delete 后显式 `SQLTransaction.Commit` |
| 控件显示灰框 | 该控件是 placeholder，查 `docs/CONTROL_MATRIX.md`；服务端逻辑照常跑 |
| 程序秒退（无输出） | 终端工具在 Job Object 里拉起又被回收；GUI 版看面板日志；坑 108 |
| worker 无限重启 | 命令行 DelimitedText 替换语义踩坑，已修（坑 106） |
| FPImageException | 多半是替身，真凶常是 sqlite 锁（坑 107） |
| SQLite database is locked | WAL + busy_timeout=10000 + 写前 CommitRetaining（坑 9） |
| 公网日志 IP 全是反代地址 | 加 `--trust-proxy` |
| 端口被强杀残留孤儿 socket | `LISTENING PID 0`，换端口最省事 |
| 浏览器标签没图标（还是默认地球） | exe 同目录或 `--root` 没有 favicon.ico → 放一个；或浏览器缓存了旧 204 空响应 → Ctrl+F5 强刷（坑 144） |
| 从 AI 终端/脚本启动的服务跑一会儿就消失、无日志 | 命令跑在 kill-on-job-close 的 Job Object 里被回收；后台任务方式也可能在轮次结束后被收走 → 用 `Start-Process`（脱离 Job）或真实用户终端启动（坑 108/145） |

更多案例与调试方法论：`docs/DEBUGGING.md`；146 个坑按编号检索
`docs/NOTES.md`（坑 23/66/108 等旧结论已被后续坑修订，以标注为准）。

## 9. 已知限制

- 模态超时 180 秒；同一会话同时只能有一个对话框；
- `TOpenDialog` 不能浏览服务端磁盘（只能上传文件）；
- `TSplitter` 不可拖动；`Anchors` 不做前端吸附计算；
- 高 DPI 按 96 处理（125%/150% 设计的 lfm 自动缩回）；
- PDF 直出暂以浏览器"另存为 PDF"代替；会话外置 Redis 未实现；
- 未适配控件浏览器端灰框占位（服务端照常活着），不影响其他控件。

---

# 第二篇 开发篇

## 10. 源码结构

```
src/
├── lwcore.lpk / lwserver.lpk      运行时包（IDE 自动生成，聚合单元）
├── design/lwdesign.lpk            设计期包（IDE 向导/组件面板）
├── client/                        前端运行时：lw.js lw.css lw-alpine.js lw-alpine.css alpine.min.js
├── lib/                           包编译产物（入库忽略）
└── core/                          全部核心单元（约 30 个）
```

`core/` 关键单元（职责即文件头注释）：

| 单元 | 职责 |
|---|---|
| lwbase.pas | 基础类型/JSON 工具；`LW_VERSION`；事件白名单 `IsLWClickEvent` |
| lwws.pas | nogui widgetset 补丁：虚拟显示器 1920×1080@96DPI + GDI 补齐 |
| lwform.pas | `TLWForm` 基类（覆盖 ShowModal/DoClose 实现同步模态） |
| lwwriter.pas | LCL 树 → JSON（KindOf 映射、白名单属性、内部件过滤） |
| lwsession.pas | 会话 = 一个页签 + 一棵 LCL 树；推送队列；增量补丁快照 |
| lwdispatch.pas | 浏览器事件 → RTTI 调真实控件事件；vals 回填 LWApplyValue |
| lwhttp.pas | fphttpserver 路由（/lw/api/*、/ext/、/lw/download、/lw/view…） |
| lwapp.pas | 门面：Register/SetLogin/Run；命令行与 INI 解析 |
| lwdlg.pas | 对话框改道（LWInstallDialogs） |
| lwdiff.pas | 增量补丁 diff（两次 payload → ops） |
| lwws/lwwebsocket.pas | WS 只传事件请求/响应；推送走长轮询游标 |
| lwdbgrid.pas / lwdbnav.pas | TLWDBGrid / TLWDBNavigator（lfm 写真实类名） |
| lwchart/lwui/lwweb/lwreport/lwlogin/lwcaptcha/lwpanel/lwrlog | 图表/仪表取色遮罩/富内容/报表/登录/图形验证码/面板/日志 |
| lwhyper.pas | 负载均衡核心（tools 的控制台/GUI 版共用） |
| lwnewproject.pas | 工程骨架模板（IDE 向导与 tools\lwnew 共用） |
| lwproxyws.pas | 自动生成（gen_proxyws.py），GUI 构建专用代理 widgetset，勿手改 |

## 11. 工作原理（一分钟版）

1. `TLWApp.Register(TMainForm)` 只记窗体类；`Run` 起 HTTP 服务；
2. 浏览器 `GET /` → `POST /lw/api/session` → 服务端创建真实 `TMainForm`
   实例并跑 `OnCreate`，`lwwriter` 把整棵 LCL 树序列化成 JSON 下发；
3. 点击 → `POST /lw/api/event {sid,id,ev,val,vals}` → `lwdispatch` 用
   RTTI 找到控件，先 `LWApplyValue` 回填值再触发真实事件（按钮走原生
   Click 保 ModalResult 语义）→ 重新序列化返回新树；
4. `ShowModal` 用 `TEvent.WaitFor` 200ms 切片真阻塞事件线程，浏览器端
   长轮询把模态指令推给页签；点 OK 经 `/lw/api/dlg` 带回模态结果；
5. 推送一律走长轮询游标（`poll?after=N`，队列 64 条），WS 只传事件；
6. 浏览器 `lw.js` 按 id reconcile 增量更新；`--patch=1` 时服务端先 diff
   （lwdiff）只发 ops，客户端 `tver` 不匹配自动退回全量自愈。

深读：`docs/HOW_IT_WORKS.md`（含关键源码行号）；
为什么不能全量 RTTI dump、KindOf 顺序敏感性等设计约束也在那里。

## 12. 线程模型（改动前必读）

- fphttpserver 每请求一线程；事件线程处理 `/lw/api/event`；
- 长轮询线程阻塞 20s；Sweep 线程清会话（默认 20 分钟超时）；
- GUI 版另有 accept 后台线程 + 面板 TTimer；
- **并发建窗会踩坏 LCL 全局字形缓存**：建窗/销毁/序列化必须进
  `LWLCLEnter/Leave` 闸门（坑 100），事件处理故意不进；
- 会话级可重入执行锁 `FExec`（坑 71）：模态期间同会话其他请求排队；
- 会话数据全部在进程内存 → 集群必须粘性，worker 重启即丢会话。

## 13. 调试

- `--verbose` 打印每个请求与异常栈；`--log=path` 落盘；
- GUI 版面板：菜单 File/Admin + 实时日志（限 4000 行）+ 状态栏三格；
- lwhyper 自带 `/lw/hyper/status` worker 明细端点；
- 压测：`tools/bench_concurrency.py`（阶梯加压）、`tools/pipe_bench.py`
  （管道基准）；性能剖析开关 `LW_PROF`；
- 四个真实 bug 的定位过程 + 九条调试方法论：`docs/DEBUGGING.md`。

## 14. 测试

统一入口（自动起停服务）：

```
python tests/run_with_server.py <exe路径> <测试脚本> [端口] [exe额外参数]
```

- **HTTP 级回归** `tests/t_*.py`（约 25 个：controls/db/dbaware/dialog/
  files/login/multitab/ws/hyper_ws/writeback_audit…），数百项断言；
- **CDP 浏览器探针** `tests/cdp_*.py`（走 Chrome DevTools 协议连无头
  Edge，9237 端口，需 websocket-python）：首屏渲染/截图/控制台错误；
- **离线单测**：`tests/lwdiff_case.lpr` + `t_lwdiff_fuzz.py`（diff fuzz，
  纯 fpjson 不用 lazbuild）；
- **支持度审计**（改动 lwwriter/lw.js 后重跑）：

  ```
  tools\build_audit.bat     → docs\CONTROL_MATRIX.md
  tools\build_dbcheck.bat   → docs\DB_AWARE_MATRIX.md
  ```

## 15. 扩展开发

加一个新控件的渲染支持（标准路径）：

1. `lwwriter.KindOf` 加 kind（注意分支顺序，KindOf 顺序敏感）；
2. `lwbase` 事件白名单按需加事件；
3. `lw.js`（及 lw-alpine.js，如需双端一致）加渲染分支与回写分支；
4. `demos/audit` 或 `demos/controls` 摆一个实例；
5. 重跑 `lwaudit` 更新矩阵 + `tests/t_controls.py` 回归；
6. 映射写进 `docs/MAPPING.md`。

前端协议字段（payload/ops/tver/seq 游标）见 `docs/SCALE.md` §2 与
`docs/HOW_IT_WORKS.md`；改 lwproxyws 相关内容必须走 `gen_proxyws.py`
重新生成。

## 16. 仓库注意

- 根目录 `src - 副本 (N)`、`src稳定版20261111`、`src高吞吐量` 等是历史
  快照，**唯一权威源码是 `src/`**；`demos/gallery - 副本` 同理；
- `demos/gallery/lw/` 等扁平部署副本会导致"改了 src/client 不生效"（坑 93）；
- `CrossSocket/` 目前无工程引用；`patches/` 是 FPC MIPS64 补丁（龙芯场景）；
- `packagefiles.xml` 是 IDE 用户包链接清单（含本机第三方包路径），不是构建脚本；
- `src/core/backup/`、`*.ppu/*.o`、`tmp/` 为本地产物，`.gitignore` 已覆盖。
