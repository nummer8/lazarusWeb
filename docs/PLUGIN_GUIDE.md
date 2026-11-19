# 插件使用说明（手把手）

> 目标：**主框架不动，加功能只是加文件**。
> 这份文档只讲怎么用；为什么要这么做（跨 DLL 类身份实测、四方案对比）见
> `PLUGIN_FEASIBILITY.md`。

---

## 0. 30 秒理解

一个「插件」就是一个普通单元，满足两条约定：

```pascal
unit umod_xxx;                       { ① 一个 .pas 文件 }

interface
procedure RegisterModule;            { ② interface 段声明这个名字 }

implementation
procedure RegisterModule;
begin
  TLWApp.RegisterForm('Xxx', TXxxForm);   { 页面：注册名 -> 窗体类 }
  TLWApp.AddAjax('xxx_data', @GXxx.Data); { 可选：AJAX 端点 }
end;
end.
```

主程序只调一次 `RegisterAllModules`（这个单元由脚本扫描目录生成），
所以**新增插件不用改主程序**。

界面两种写法都支持，按习惯选：

| 写法 | 适用 | 示例 |
|---|---|---|
| `.lfm` 设计窗体 + `{$R *.lfm}` | Lazarus 常规做法，IDE 里拖控件 | `plugins/umod_notes.pas` |
| 纯代码建窗 | 界面随数据动态生成，或不想带设计文件 | `plugins/umod_dashboard.pas` |

---

## 1. 先把现成 demo 跑起来

```bat
cd C:\lazarusWeb

rem 生成注册汇总（新增/改名插件后都要跑；同时把插件单元登记进 lpi，IDE 里能设计）
python tools\lwplugins.py --lpi demos\plugindemo\plugindemo.lpi --lpi demos\plugindemo\plugindemo_gui.lpi

rem 编译 nogui 档（控制台服务）
lazbuild --ws=nogui demos\plugindemo\plugindemo.lpi

rem 启动（端口读 demos\plugindemo\plugindemo.ini，默认 8877）
demos\plugindemo\plugindemo.exe
```

浏览器打开 <http://127.0.0.1:8877/>，应看到「模块仪表盘」：三张指标卡、
进度条、两个按钮、一个日志框。

**看第二页**：点页面上的 **「打开便签页」** —— 浏览器切到便签页（仪表盘窗口
被撤下，服务端实例保留），点里面的 **「返回仪表盘」** 再切回来。这就是
`TLWApp.OpenForm('注册名')` 的页面切换语义。

也可以启动时指定默认页：

```bat
demos\plugindemo\plugindemo.exe --form=Notes
```

预期结果：页面标题「便签（插件）」，有标题输入框、内容框、保存/清空/返回按钮、
已保存列表。

GUI 档（弹服务端面板，或用 `--nogui` 不弹）：

```bat
lazbuild demos\plugindemo\plugindemo_gui.lpi
demos\plugindemo\plugindemo_gui.exe --nogui
```

端口见 `demos\plugindemo\plugindemo_gui.ini`（8890）。

---

## 2. 加一个新页面（5 步）

以新增「订单页」为例。

**第 1 步：复制模板**

```
plugins\template\umod_template.pas   ->  plugins\umod_order.pas
plugins\template\umod_template.lfm   ->  plugins\umod_order.lfm
```

**第 2 步：改三处**

| 改什么 | 从 | 到 |
|---|---|---|
| `unit` 名（与文件名一致） | `umod_template` | `umod_order` |
| 类名（`.lfm` 根对象类型同步改） | `TTplForm` | `TOrderForm` |
| 注册名 | `'Tpl'` | `'Order'` |

`.lfm` 第一行也要跟着改：

```
object Order: TOrderForm
```

**第 3 步：生成注册汇总**

```bat
python tools\lwplugins.py --lpi demos\plugindemo\plugindemo.lpi --lpi demos\plugindemo\plugindemo_gui.lpi
```

输出里应出现：

```
  模块  umod_dashboard.RegisterModule
  模块  umod_notes.RegisterModule
  模块  umod_order.RegisterModule
  lpi  ...plugindemo.lpi：已登记 4 个单元
```

**第 4 步：重编（带 `-B`）**

```bat
lazbuild --ws=nogui -B demos\plugindemo\plugindemo.lpi
```

> 改了 `.lfm` 必须带 `-B`：`lazbuild` 不把 `.lfm` 记进依赖表，不加会静默用旧界面。

**第 5 步：打开**

```bat
demos\plugindemo\plugindemo.exe --form=Order
```

或在别的页面按钮里 `TLWApp.OpenForm('Order')`。

---

## 3. 在自己的工程里接入

前提：工程是 lazarusWeb 工程（窗体基类 `TLWForm`，能 `TLWApp.Run`）。

**3.1 建插件目录**（放在工程目录下，例如 `C:\MyApp\plugins\`），
把模板 `umod_template.pas/.lfm` 复制进去、改名，再写第一个模块。

**3.2 主程序加两行**

```pascal
uses
  Interfaces, Forms, lwapp, umain, lwmodules;   { 加 lwmodules }

begin
  Application.Initialize;
  Application.Title := 'MyApp';
  TLWApp.Register(TMainForm);    { 原有窗体保留，不影响 }
  RegisterAllModules;            { 加这一行：注册所有插件 }
  TLWApp.Run;
end.
```

**3.3 工程加单元搜索路径**

Lazarus IDE：`Project → Project Options → Compiler Options → Other unit files`，
加上你的插件目录：

```
..\plugins
```

框架单元不用再加：

- IDE 向导生成的工程**依赖 `lwserver` 包**（`lwform`/`lwapp`/`lwajax`/`lwpluginutil`
  都在包里），只需要加插件目录；
- 用 `tools\lwnew` 命令行生成的工程走源码路径，`src\core` 已经在
  `Other unit files` 里，同样只需要再加插件目录。

> 两个 build mode（Default / GUI）都检查一遍：如果某个 mode 里也有一份
> `Other unit files`，它会覆盖 Default 的那份，需要同样加。

**3.4 生成注册汇总**

```bat
python C:\lazarusWeb\tools\lwplugins.py --dir C:\MyApp\plugins --lpi C:\MyApp\MyApp.lpi
```

`--dir` 是你的插件目录；`lwmodules.pas` 会写到 `<dir>\lwmodules.pas`；
`--lpi` 让 IDE 的项目检查器能看到插件单元（可重复传多个 lpi）。

**3.5 编译运行**

```bat
lazbuild --ws=nogui -B C:\MyApp\MyApp.lpi
```

以后加插件只重复 3.1/3.4/3.5，主程序和 `.lpi` 不用再改。

---

## 4. 界面：`.lfm` 的三个注意点

```pascal
type
  TOrderForm = class(TLWForm)
    edNo: TEdit;                       { 1) 字段名 = .lfm 组件名 }
    btnSave: TButton;
    procedure btnSaveClick(Sender: TObject);   { 2) 事件方法也在这一段 }
  end;

implementation
{$R *.lfm}                             { 3) 把 .lfm 编进 exe 资源段 }
```

1. **字段与组件同名**。IDE 改控件名会自动同步字段，手改 `.lfm` 时要自己对齐；
   不同名 → 字段是 `nil`，运行时访问会 AV。
2. **字段和事件方法必须在类声明的默认可见性段**（`class(TLWForm)` 之后、
   `private` 之前，等价 published）。LCL 的 `TReader` 靠 RTTI 接组件和
   `OnClick = btnSaveClick`；放进 `private` 就接不上，点了没反应。
3. **不需要往 `.lpi` 登记资源**。`.lfm` 由 `{$R *.lfm}` 编进 exe 资源段，
   `TForm.Create` 按类名查；`.lpi` 只登记 `.pas`。

**在 IDE 里设计界面**：打开 `demos\plugindemo\plugindemo.lpi`，
项目检查器里双击 `umod_notes.pas`，按 **F12** 进设计器。
改完保存 → 跑生成器（可选）→ `-B` 重编。

**多会话**：同一页面被多个浏览器打开时，LCL 会给实例名加 `_1/_2`；
`TLWForm.Loaded` 已把它还原成设计期名字，不用处理。

---

## 5. 页面之间跳转

```pascal
if not TLWApp.OpenForm('Notes') then
  ShowMessage('没有注册名为 Notes 的窗体');
```

- 同一会话里重复调用**不会**建第二个实例（先查会话已有窗体）；
- 语义是**页面切换**：浏览器上其它可见页会被撤下（`SessionHideOthers`），
  只留目标页。服务端窗体对象都还在会话里，切回来是同一个实例，
  控件状态、已填内容不会丢；
- 目标页本来就是唯一可见页时（在当前页又点了一次导航）不重复推送，
  避免前端重复开窗；
- 想真的多窗并存，不要用 `OpenForm`，直接 `Form.Show`（走 `SessionShowForm`）。
- 模态窗体不参与切换：`ShowModal` 期间打开别的页，模态窗不会被撤下。

---

## 6. AJAX 端点

服务端：

```pascal
type
  TOrderAjax = class
  public
    procedure List(A: TLWAjaxContext);
  end;

procedure TOrderAjax.List(A: TLWAjaxContext);
begin
  A.Json('{"ok":true,"items":["A-1","A-2"]}');
end;

// RegisterModule 里：
TLWApp.AddAjax('order_list', @GOrderAjax.List);
```

浏览器：

```js
const r = await fetch('/lw/ajax/order_list');
const data = await r.json();
```

需要第三方站点直接调（跨域）时，启动加 `--ajax-cors`。

要手工拼 JSON 字符串时，用框架单元里的转义函数（`src/core/lwpluginutil.pas`）：

```pascal
uses lwpluginutil;
A.Json('{"ok":true,"name":"' + JsonEscape(edName.Text) + '"}');
```

---

## 7. 编译、配置、参数

| 目标 | 命令 | 产物 |
|---|---|---|
| nogui | `lazbuild --ws=nogui -B demos\plugindemo\plugindemo.lpi` | 控制台服务，无窗口 |
| GUI | `lazbuild -B demos\plugindemo\plugindemo_gui.lpi` | 有服务端面板，`--nogui` 可关 |

`ini`（exe 同名自动加载）支持的键：`client`、`port`、`theme`、`ssl`、`sslhost`、
`sslcert`、`sslkey`、`extdir`、`patch`。
`--form`、`--title`、`--log`、`--root`、`--timeout` **只能写命令行**（优先级更高）。

---

## 8. 部署

运行期按 `<root>\lw\<文件>` → `<exe 目录>\lw\<文件>` → 向上找 `src\client` 的顺序
找前端资源。**拷到仓库外单独部署时**，把 `src\client` 整个拷成 exe 同目录的 `lw\`，
并把 `favicon.ico` 放 exe 同目录：

```
MyApp\
  MyApp.exe
  MyApp.ini
  favicon.ico
  lw\  (lw.js / lw.css / alpine.min.js / ...)
```

多进程/零停机发布用 `lwhyper`（滚动换壳，逐 worker 重启），不在这份文档范围内。

---

## 8.5 插件的另一种形态：独立 exe（进程级插件）

插件单元不链入宿主，而是装进**独立的 lazarusWeb 服务 exe**（自己监听自己的
端口），宿主用 `lwroute` 把 `/p/<名>/...` 反向代理过去。完整演示与原理见
`demos/procdemo/README.md`；与编译期形态的取舍对比见
`PLUGIN_FEASIBILITY.md` §4/§5。

```ini
; 宿主 ini 里登记（键名固定 plugin.<名>=host:port）
plugin.notes=127.0.0.1:8871
plugin.dash=127.0.0.1:8872
plugin.reports=127.0.0.1:8873
```

演示工程 `demos/procdemo/` 自带一份插件模块源码（`modules/`），不与编译期
形态的 `plugins/` 共用文件；两边是独立副本，改一边不影响另一边。

插件 exe 就是个普通 lazarusWeb 应用，模块单元与编译期形态**一字不改**：

```pascal
program notesplug;
uses Interfaces, Forms, lwapp, umod_notes;
begin
  Application.Initialize;
  RegisterModule;          { 与 plugindemo 相同的模块契约 }
  TLWApp.Run;
end.
```

宿主页面里打开插件页：

```pascal
procedure THostForm.OpenNotes(Sender: TObject);
begin
  RunJS('location.href=''/p/notes/''');   { TLWForm.RunJS：本标签跳转 }
end;
```

同标签跳转后，按浏览器「后退」即可回宿主；要新页签才用
`window.open('/p/notes/', '_blank')`。两种方式插件端代码相同 —— 插件不
知道自己被谁打开，API 按页面路径推导 BASE 自动落回代理前缀。

**插件页之间的导航**（模块里调 `TLWApp.OpenForm('注册名')`）：模块源码两种
形态一字不改，由框架按登记情况决定走哪条路——

| 形态 | `OpenForm('Notes')` 的行为 | 需要配置 |
|---|---|---|
| 编译期（plugindemo） | 两窗体同进程，直接建/切窗体 | 无 |
| 独立 exe（procdemo） | 本进程只有自己的窗体，找不到目标 → 推 JS 跳到映射的 URL | 各插件 ini 配 `page.<注册名>=<URL>` |

独立 exe 形态下，dash 进程里没有 Notes 窗体（它在 notesplug 进程里），
所以在 dashplug.ini 配一行把注册名指到对方的页面 URL：

```ini
; dashplug.ini —— 点「打开便签页」调 OpenForm('Notes') 时跳这里
page.Notes=/p/notes/

; notesplug.ini —— 点「返回仪表盘」调 OpenForm('Dashboard') 时跳这里
page.Dashboard=/p/dash/

; reportsplug.ini —— 两个按钮分别调 OpenForm('Dashboard') / OpenForm('Notes')
page.Dashboard=/p/dash/
page.Notes=/p/notes/
```

URL 用绝对路径 `/p/<名>/`，浏览器执行 `location.href` 后由宿主 `lwroute`
代理到目标插件进程。框架实现在 `lwapp.OpenForm`：先找本地窗体，找不到再查
`page.*` 映射，命中就推 `{"type":"js","code":"location.href='…'"}`；两处都
没有才返回 False（与旧行为一致）。注意：**只配了映射不代表能同屏并存**——
`OpenForm` 在独立 exe 形态是整页跳转（同标签），不是多窗口并存。

边界：会话独立（插件有自己的 sid/登录）；WebSocket 经代理暂不透传（前端
自动回退长轮询）；往宿主已有页面里加控件做不到（那是编译期形态的事）。

职责划分（默认行为）：**插件只负责业务，非业务功能由主程序处理** ——
框架静态资源（`lw.js`/`lw.css`/`lw-alpine.js`/`lw-alpine.css`/
`alpine.min.js`、`favicon.ico`、`/ext/`）经代理时由宿主直出，不转发给
插件（`lwroute.LWRouteStaticLocal` 白名单）。所以：

- 升级客户端运行时只换宿主一处，所有插件页面立即生效；
- 插件部署可以只带 exe（直连自己端口调试时 `LWFindClientFile` 照常自出，
  不受影响）；
- 会话绑定类端点（`/lw/api/*`、`/lw/ajax/*`、验证码、`/lw/tpl/` 模板）
  状态在插件会话里，仍代理回插件，宿主不截流。

### 插件页面的窗体模板

插件窗体与普通窗体使用完全相同的模板机制，不需要写 Pascal 代码：

- 文件名：桌面 `<窗体运行根目录>\tpl\<窗体名>.html`（窗口/平面两模式共用
  这一个文件）、移动 `<窗体名>.m.html`（移动端只读，无模板用 LCL 布局），
  文件头必须写 `<!-- lw-tpl-mode:window -->` 或 `<!-- lw-tpl-mode:flat -->`；
  两者同时出现时 **flat 优先**。模板只作背景/装饰层，控件始终按
  `.lfm` 的 `Left/Top` 绝对定位，不再支持旧的 `{%控件名%}` 流式占位符；
- 一键生成：在 IDE 里打开插件窗体的 `.pas`/`.lfm`，用 **Tools →
  生成 lazarusWeb 窗体模板（当前单元 LFM）**，弹窗选窗口/平面模式，
  生成到工程目录 `tpl\`（桌面 `.html` + 移动 `.m.html` 两份）。若改过
  `lwdesign` 包源码，必须先在 IDE 里 Compile → Install 并重启，否则
  菜单仍是旧逻辑；
- 部署：把生成的 `.html` 与 `.m.html` 放到**插件 exe 的运行根目录** `tpl\`。
  经宿主 `/p/<插件名>/` 代理访问时，`/lw/tpl/<窗体名>.html` 带着
  插件会话 `sid` 代理回插件，因此模板状态在插件侧；静态客户端资源
  （`lw.js`/`lw.css` 与 `lw-alpine.js`/`lw-alpine.css`、`alpine.min.js`）
  由宿主白名单直出，不需要每个插件各带一份。
  插件直连自己端口调试时，插件 exe 目录也要有更新过的 `lw\` 资源；
- 若目录里残留旧 `<窗体名>.flat.html`，按兼容规则它仍会触发平面模式，
  想切回窗口模式请删除它；改完模板 `Ctrl+F5` 强刷（客户端脚本有缓存）。

---

## 9. 回归测试

```bat
rem 终端 1
demos\plugindemo\plugindemo.exe --port=8877 --form=Dashboard

rem 终端 2
python tests\t_plugin.py
```

覆盖：会话建立、插件窗体实例化（节点树）、按钮点击派发、跨插件导航、
两个 AJAX 端点、默认窗体名。

> 脚本里事件名必须写 `OnClick`（published 事件名）。传 `"click"` 会被框架
> 静默忽略——看起来就是"点了没反应"。另外 memoLog 初始就有一行"刷新：…"，
> 断言必须比较点击前后的文本差异，只查关键字会假阳性。

---

## 10. 常见问题

| 症状 | 原因 | 解决 |
|---|---|---|
| 浏览器里没有新页面 | 没跑生成器 / 没重编 / `--form=` 名字写错 | 跑生成器 → `-B` 重编 → 名字用 `RegisterModule` 里的注册名 |
| 页面空白、样式全丢 | 部署目录缺 `lw\`（直连调试时） | 把 `src\client` 拷成 exe 同目录 `lw\`；经宿主代理时由宿主直出，不用插件自带 |
| 插件模板没生效 | 文件不在插件运行根 `tpl\<窗体名>.html`，或缺 `lw-tpl-mode` 标记；或残留旧 `.flat.html` 强制平面模式；或客户端脚本缓存 | 放到插件 exe 根 `tpl\`，文件头写 `lw-tpl-mode:window\|flat`，删旧 `.flat.html`，`Ctrl+F5` 强刷 |
| 改了 `.lfm` 界面没变 | 没带 `-B` | `lazbuild -B ...` |
| 点按钮没反应 | 字段/事件方法放进了 `private`；或组件名与字段不同名 | 移到默认可见性段、名字对齐 |
| 运行时 AV，字段是 nil | `.lfm` 里没有这个组件，或名字不一致 | 核对 `.lfm` 与类声明 |
| IDE 项目检查器看不到插件单元 | 没传 `--lpi` | `python tools\lwplugins.py --lpi <你的.lpi>` |
| 双击 `.lfm` 进不了设计器 | 该单元不在任何工程的搜索路径里 | 打开工程 → Other unit files 加插件目录 → 从 `.pas` 按 F12 |
| `Identifier not found "TPanel"` | 少 `ExtCtrls` | `uses ... ExtCtrls` |
| `Can't create object file ... .exe` | exe 正在运行，文件被占用 | 先关掉服务再编 |
| 两个插件注册了同一个名字 | 后注册的覆盖前面的 | 注册名保持唯一（`FormNames` 可查） |
| 中文乱码 | 源文件不是 UTF-8 | `.pas`/`.lfm` 都存 UTF-8（Lazarus 默认） |

---

## 11. 新增插件后的检查清单

- [ ] 文件名、`unit` 名、类名、`.lfm` 根对象类型、注册名五者一致
- [ ] `interface` 段有 `procedure RegisterModule;`
- [ ] `.lfm` 存在且单元里有 `{$R *.lfm}`
- [ ] 字段与事件方法在默认可见性段
- [ ] 跑过 `python tools/lwplugins.py --lpi <工程.lpi>`
- [ ] `lazbuild -B` 重编通过
- [ ] `--form=<注册名>` 能打开；`tests/t_plugin.py` 通过
- [ ] 若插件窗体带模板：`<运行根>\tpl\<窗体名>.html` 存在且文件头有
      `lw-tpl-mode:window|flat`，目录里无残留 `.flat.html`；模板只作背景，
      控件位置由 `.lfm` 决定
