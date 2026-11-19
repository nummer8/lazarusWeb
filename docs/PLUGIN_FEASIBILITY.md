# 插件化可行性分析：动态加载 DLL/SO 扩充页面

> 结论先行：**"页面扩充"可以用插件做，但不要选"裸 DLL 导出窗体类"这条路。**
> FPC 下 DLL 与 EXE 各带一份 RTL，类身份（class identity）必然断裂——实测
> 宿主侧连 `o is TObject` 都是 `FALSE`。而 lazarusWeb 的渲染与事件派发里有
> **182 行含 `is T...` 判断**（`lwdispatch.pas` 72 行 + `lwwriter.pas` 110 行），
> 一旦断裂，控件能显示但不会派发、不会序列化，是"静默失效"而不是报错。
>
> 推荐顺序：**源码插件目录（已落地）→ 进程级插件（独立发布时）→
> Lazarus Runtime Package（必须同页面混用对象树时）**。
> 阶段 0 已实现并通过 nogui/GUI 两档回归（`plugins/` + `tools/lwplugins.py` +
> `demos/plugindemo` + `tests/t_plugin.py`），见 §5。

## 1. 先把"页面扩充"拆成三种粒度

不同粒度对"类身份一致"的要求完全不同，这是选型的分水岭。

| 粒度 | 典型需求 | 是否要求跨模块共享类身份 |
|---|---|---|
| A. 新增独立页面 | 加一个"订单管理"窗体，独立 URL 进入 | **不要求**（只要能注册窗体名） |
| B. 页面内嵌新控件 | 新 LCL 控件类，要参与事件派发与 HTML 序列化 | **强制要求** |
| C. 扩展现有页面行为 | 加 `/lw/ajax/xxx` 端点、定时任务、导出 | **不要求**（纯函数即可） |

现状里 A 和 C 占了绝大多数需求，B 很少——这一点直接决定不必冒险上裸 DLL。

## 2. 现状事实（源码核对）

| 项目 | 事实 | 位置 |
|---|---|---|
| 窗体注册表 | `TStringList` 存 `TFormClass`，进程内全局，编译期登记 | `lwapp.pas:164-170` |
| 窗体创建 | `cls.Create(nil)`，随后按名字挂进会话组件树 | `lwapp.pas:139-145` |
| 注册写法 | 一行：`TLWApp.Register(TAwareForm)` | `demos/dbaware/dbaware.lpr:16` |
| 链接方式 | demo 直接引用源码 `OtherUnitFiles=../../src/core`，静态编译 | `demos/dbaware/dbaware.lpi` |
| 包 | `src/lwcore.lpk`、`src/lwserver.lpk` 已存在（RunAndDesignTime） | `src/*.lpk` |
| 路由 | 单进程单应用：`/` 渲默认窗体，`/lw/api/*` 框架 API，`/lw/ajax/*` 业务端点 | `lwhttp.pas:2146-2319` |
| 多进程 | `lwhyper` 已有 worker 拉起/健康巡检/滚动热更新/WS 透传，但**只多开同一个 exe**，无按路径分流 | `lwhyper.pas:8-26` |
| 会话 | 纯进程内 `TStringList`，sid = GUID 前 8 位 + 计数器 | `lwsession.pas:1247-1253` |

关键含义：注册动作本身极轻（一行），所以"插件化"的门槛不在注册，而在
**插件里的窗体对象能不能被主框架正确识别**。

## 3. 实测：FPC 跨 DLL 边界到底发生了什么

实验代码：`tmp/lwpoc/`（`lwpoclib.pas` 编译为 DLL，`pocmain.pas` 为宿主），
FPC 3.3.1 / Win64，两侧均静态链接 RTL。

### 3.1 类身份 —— 断裂（致命）

```
DLL 返回对象地址        : 22410592
EXE: o is TObject        = FALSE      <-- 连 TObject 都不认
EXE: o is TPocExeObj     = FALSE
DLL: o is TObject        = TRUE
DLL: o is TPocObj        = TRUE
EXE: o.ClassName         = TPocObj    <-- 表面完全正常
DLL: o.ClassName         = TPocObj
EXE: o.ClassType = TObject? FALSE
DLL: Kind (虚方法跨模块)  = 42         <-- 方法调用正常
```

原因：`is` 比较的是"类引用"这个模块内地址常量。EXE 的 `TObject` 与 DLL 的
`TObject` 是两个不同地址，DLL 对象的 VMT 继承链里永远找不到 EXE 的类引用，
所以遍历到顶也匹配不上。

**危险之处**：`ClassName`、字段访问、虚方法调用全部正常，只有 `is` 静默返回
`FALSE`。框架遇到这种控件不会崩，而是"当它不存在"——不渲染、不派发事件。

### 3.2 内存管理器 —— 两份实现，但底层同堆

```
EXE GetMem 实现地址      : 4295009552
DLL GetMem 实现地址      : 4563427952
同一份堆实现?            : FALSE
DLL 分配的块，EXE 释放…  释放返回（未崩）
```

两个模块各有自己的 `MemoryManager` 记录，但 Windows 下底层都走进程堆，
所以"跨模块分配、跨模块释放"**恰好不崩**。这是运气，不是契约：Linux 下若一侧
用 `cmem`、一侧不用，或任一侧装了自定义内存管理器，立刻变成堆破坏。

### 3.3 托管字符串 —— 同样"侥幸"

```
EXE 收到                : hello-from-dll-heap
长度                    : 19
EXE 拼接后              : hello-from-dll-heap!
```

引用计数与长度头在 DLL 堆上，EXE 侧改写引用计数时用的是自己的堆管理代码，
只因底层同堆才没炸。**不能作为设计依据**。

### 3.4 实测结论

| 边界 | 结果 | 能否依赖 |
|---|---|---|
| 对象/类引用 | `is` 全 False | **绝对不能** |
| 虚方法调用 | 正常 | 可以（但没意义，因为认不出类型） |
| 裸内存分配/释放 | Windows 下不崩 | 不可移植，不可依赖 |
| 托管 string/动态数组 | Windows 下不崩 | 不可依赖，须换 PChar |
| PChar / Integer / 记录 | 正常 | **安全边界** |

## 4. 四种方案的对比

| 维度 | ① 裸 DLL/SO 导出窗体类 | ② 进程级插件（多 exe + 路由） | ③ Lazarus Runtime Package | ④ 源码插件 + 热更新 |
|---|---|---|---|---|
| 页面粒度 A（新页面） | 表面可行，实际渲染失效 | **可行** | **可行** | **可行** |
| 页面粒度 B（页面内新控件） | 不可行 | 不可行（跨进程无对象树） | **可行** | **可行** |
| 页面粒度 C（AJAX/后台） | 可行（C ABI） | 可行 | 可行 | 可行 |
| 类身份风险 | **断裂** | 无（进程隔离） | 无（共享 RTL） | 无（同一模块） |
| 故障隔离 | 差（同进程） | **最好**（崩一个不影响其他） | 差（同进程） | 差（同进程） |
| 独立发布/升级 | 好（换 DLL） | **好**（换 exe，已有滚动热更新） | 中（bpl 需与工具链同版本） | 差（要重编主 exe） |
| 部署复杂度 | 低 | 中（多进程 + 端口 + 路由） | **高**（bpl 随包分发，nogui/win32 各一套） | 低 |
| 现有代码改动 | 小 | 中（新增路由 + 会话共享） | **大**（所有工程改包模式） | **极小**（加目录 + 一行注册） |
| 工具链绑定 | 弱 | 弱 | **强（FPC/LCL 版本一变全重编）** | 弱 |

### 方案①为什么不行

即使把 `TFormClass` 以 `Pointer` 塞进注册表、`cls.Create(nil)` 能在 DLL 里成功
建出窗体，后续每一步都失效：

- `lwwriter` 序列化：110 行 `is T...` 判断全 False → 控件被跳过，页面空白；
- `lwdispatch` 派发：72 行 `is T...` 判断全 False → 点了没反应；
- 插件 DLL 若 `uses lwserver` 来调 `TLWApp.Register`，会带进**第二份框架全局状态**
  （`GRegistry`、`GCfg`、`IsMultiThread`、widgetset），问题从"类型不认识"升级为
  "两个框架各跑各的"。

### 方案③的真实成本

Runtime Package 是唯一能让两个模块共享同一份 RTL/LCL 的机制（IDE 本身就是一堆
bpl），因此粒度 B 只有它能做。代价是：

- 所有 demo/用户工程要改为引用包而非源码路径；
- Windows 需分发 `.bpl`，Linux 需分发 `.so`，且 **nogui 与 win32 两套 widgetset
  各编一份**；
- bpl 与编译器版本强绑定，FPC 升级必须全量重编（对外分发 SDK 时尤其痛）。

## 5. 推荐路线

### 阶段 0：源码插件目录（已落地）

> 操作步骤（跑 demo、新增页面 5 步、在自己的工程接入、`.lfm` 注意点、常见问题）
> 见 `PLUGIN_GUIDE.md`；本节只讲结构与原理。

主程序不含任何业务窗体，页面与 AJAX 全部来自 `plugins/`：

```
plugins/
  umod_dashboard.pas   仪表盘页面 + /lw/ajax/dashboard_stats（纯代码建窗示例）
  umod_notes.pas       便签页面   + /lw/ajax/notes_export（.lfm 设计窗体示例）
  umod_notes.lfm       上面那个单元的界面，IDE 里可直接拖控件
  template/            新插件模板（子目录不被生成器扫描）
  lwmodules.pas        自动生成，勿手改
src/core/lwpluginutil.pas   JSON 转义（JsonEscape）；「按名字开页面」是框架 API
                            TLWApp.OpenForm，不需要辅助单元
```

模块契约只有一条——单元 interface 段声明 `procedure RegisterModule;`：

```pascal
procedure RegisterModule;
begin
  TLWApp.RegisterForm('Dashboard', TDashboardForm);      { 页面 }
  TLWApp.AddAjax('dashboard_stats', @GAjax.Stats);        { 可选：端点 }
end;
```

#### 界面怎么写：`.lfm`（推荐）或纯代码，两条路都通

插件窗体和普通 LCL 窗体没有区别——**推荐用 `.lfm` 拖界面**，这是 Lazarus
用户的习惯做法：

```pascal
type
  TNotesForm = class(TLWForm)
    edTitle: TEdit;                  { 字段与 .lfm 里的组件同名 }
    btnSave: TButton;
    procedure btnSaveClick(Sender: TObject);   { 事件方法也在这里 }
  end;

implementation
{$R *.lfm}                           { 把同目录的 .lfm 嵌进 exe 资源段 }
```

三点说明：

- **不需要往 `.lpi` 里登记资源**。`.lpi` 只登记 `.pas` 单元；`.lfm` 由单元里的
  `{$R *.lfm}` 编进可执行文件的资源段，`TForm.Create` 按**类名**去查这份资源。
  插件单元只要被 `lwmodules.pas` uses 进来（即在链接范围内），界面就能装载。
- **字段和事件方法要放在类声明的默认可见性段**（`class(TLWForm)` 之后、
  `private` 之前，等价于 published）。LCL 的 `TReader` 靠 RTTI 把 `.lfm` 里的
  组件和 `OnClick = btnSaveClick` 接到这些成员上；放进 `private` 就接不上。
- **多会话并存是安全的**。LCL 在进程里遇到同名窗体会给实例名加 `_1/_2` 后缀，
  框架的 `TLWForm.Loaded` 已把它还原成设计期名字，`lwapp.TLWFormProvider.CreateForm`
  另有空名字兜底。实测三个会话同时打开，窗体名都是 `Notes`。

在 IDE 里改界面：打开 `demos/plugindemo/plugindemo.lpi`（它的
`OtherUnitFiles` 含 `../../plugins`），在项目检查器里打开 `umod_notes.pas`
按 **F12** 就进设计器。改完 `.lfm` 必须带 **`-B`** 重编——`lazbuild` 不把
`.lfm` 记进依赖表（这也是本项目所有 demo 的通用注意事项）。

不想用 `.lfm` 也可以纯代码建窗（`umod_dashboard.pas` 就是范例），适合界面
按数据动态生成、或不想引入设计期文件的场景。两种写法可以在同一个工程里混用。

主程序（`demos/plugindemo/plugindemo.lpr`）只剩两行：

```pascal
RegisterAllModules;
TLWApp.Run;
```

新增功能：加 `plugins/umod_xxx.pas` → `python tools/lwplugins.py` → 重编。
生成器扫描目录、识别 `RegisterModule`、跳过辅助单元、内容未变化时不写盘
（避免无谓重编）；主程序与 `.lpi` 都不需要改。上线复用 `lwhyper` 的滚动热更新
（改名换壳 + 逐 worker 重启），零停机。

#### 已实测：nogui 与 GUI 两档各 16 项通过

```bash
python tools/lwplugins.py --lpi demos/plugindemo/plugindemo.lpi --lpi demos/plugindemo/plugindemo_gui.lpi
lazbuild --ws=nogui demos/plugindemo/plugindemo.lpi     # -> plugindemo.exe
lazbuild demos/plugindemo/plugindemo_gui.lpi            # -> plugindemo_gui.exe

./plugindemo.exe --port=8877 --form=Dashboard
python tests/t_plugin.py                                 # 16 项

LW_BASE=http://127.0.0.1:8878 python tests/t_plugin.py \
    --expect-cls TNotesForm --expect-form Notes           # 第二个模块
```

断言覆盖：插件窗体被实例化并出现在节点树（`TDashboardForm` 16 个节点、
`TNotesForm` 13 个）、按钮点击经框架派发并回写服务端状态（含表单值回传、
并比较点击前后文本确有增长，避免初始文案造成的假阳性）、
`TLWApp.OpenForm` 的页面切换往返（仪表盘 -> 便签 -> 返回，目标页出现且
来源页从树上撤下）、两个插件的 AJAX 端点各自响应、`--form=` 与注册名一致。裸 DLL 方案在同样位置
会全部静默失效，因此这组断言同时是"插件实现是否退化"的守门测试。

### 阶段 1：进程级插件（独立 exe + 路由）—— 已落地（2026-11-18）

`lwroute.pas`：主框架把 `/p/<插件名>/...` 反向代理到独立 exe 上游。
每个插件是一个完整的 lazarusWeb 服务（自己监听自己的端口），宿主 ini 里
`plugin.<名>=host:port` 登记。演示见 `demos/procdemo/`（宿主 + 便签/仪表盘/
报表三个插件 exe，插件模块源码集中在 `demos/procdemo/modules/`），回归
`tests/t_route.py`。

实现要点：

- 调用插件**不经过 lwhyper**：`lwroute.pas` 自带独立反向代理（直接用
  `fphttpclient`，头/体透传、hop-by-hop 剥离、原始字节上传），只在写法上与
  `lwhyper.ProxyHTTP` 同源；插件 exe 也不链接 lwhyper，就是普通
  `TLWApp.Run` 服务；
- 转发注入 `X-Forwarded-Prefix: /p/<名>/`，插件外壳 HTML 据此把 `/lw/...`
  资源 URL 生成到代理前缀下；客户端 JS 按页面路径推导 BASE，API 调用
  自动落回代理 —— 整条会话（建会话/事件/长轮询/上传/AJAX）都经代理回插件；
  **代理必须把原始 query string 拼回上游 URL**（`ProxyTo` 取 `ARequest.URL`
  的 `?...`）：`Route` 为匹配路径会先去掉 query，而 poll/tree/ajax 全靠
  query 传 `sid/t/after/form` —— 一旦丢失，上游 `Find('')=nil` 回 `gone`，
  前端 `forgetSid+boot` 反复重建，表现为"会话已过期"无限闪（`t_route.py`
  有专门断言守住这条）；
- **非业务功能由主程序处理，插件只负责业务**：框架静态资源（`lw.js`/
  `lw.css`/`lw-alpine.js`/`lw-alpine.css`/`alpine.min.js`、`favicon.ico`、
  `/ext/` 资源）经代理时由**宿主直出**（`lwroute.LWRouteStaticLocal` 白名单
  改写本地路径），不转发给插件 —— 升级客户端运行时只换宿主一处，插件部署
  不用带这些文件；  会话绑定类端点（`/lw/api/*`、`/lw/ajax/*`、验证码、
  `/lw/tpl/` 模板）状态在插件会话里，仍代理回插件。当前模板为桌面
  `<运行根>\tpl\<窗体名>.html` + 移动 `<窗体名>.m.html` 两份，文件头
  `lw-tpl-mode:window|flat`
  （flat 优先；背景装饰层，不重排控件），用法见 `PLUGIN_GUIDE.md`。
  插件直连自己端口时行为不变（`LWFindClientFile` 照常自出），代理层
  截流不影响直连调试；
- 无尾斜杠 `/p/<名>` 301 补斜杠；未登记插件名 404 带提示；
- 推送走长轮询（`/lw/api/poll` 是唯一推送通道）；**WebSocket 经代理暂不
  透传**，前端 WS 连不上自动回退 POST 事件 + 长轮询（每 2 秒重试，无功能
  损失），WS 隧道列入后续增强；
- 插件 exe 部署可以只带 exe（框架静态资源由宿主直出，见上）；

新增框架 API：`TLWForm.RunJS(ajs)`（服务端推 JS，对标 uniGUI 的
UniSession.AddJS），宿主导航页用它本标签跳转 `location.href='/p/<名>/'`（
需要新页签时才 `window.open(..., '_blank')`）。

插件页之间的 `OpenForm` 导航按形态分流（模块源码不变）：编译期两窗体同进程
直接切页；独立 exe 下各进程只有自己的窗体，目标窗体在本进程找不到时，
`OpenForm` 查 ini 的 `page.<注册名>=<URL>` 映射，命中则推 JS 跳到对方插件页
（同标签整页跳转，非并存）。`t_route.py` 有双向断言（dash↔notes）守住这条。

必须先解决的改造点：**会话共享**。当前 sid 只存在于各自进程内存里，用户从
`/p/notes/` 跳到 `/p/dash/` 是各自独立会话（不掉登录，因为登录本来就没打通；
启用了登录的宿主与插件之间会掉）。两条路：

- 短期：每个模块独立会话（已按此落地，改造为零）；
- 中期：sid 改成 HMAC 签名的自包含令牌（携带用户身份 + 过期时间），各模块
  验签后本地建会话。工作量集中在 `lwsession`。

### 阶段 2：Runtime Package（仅当必须同页面混用对象树）

只有当需求真的变成"插件提供新控件、嵌进主框架已有页面里"，才值得付方案③的
成本。此时把 `lwcore/lwserver` 设为运行时包，插件写自己的 `.lpk` 依赖它们。

### 不建议：裸 DLL 导出窗体类

见 §3、§4。技术上能加载、能建对象，但渲染与事件会静默失效，且失效点分散在
182 行判断里，排查成本极高。

## 6. 如果确实要用裸 DLL：唯一安全的边界

把插件限制为"**无 UI 的功能扩展**"，走 C ABI：

```pascal
{ 插件导出，只用 PChar / Integer / 记录，不传对象、不传 string }
function LwPluginInit(const AHost: PLWHostApi): Integer; cdecl;
function LwPluginCall(const AAction, APayloadJson: PChar;
                      AOut: PChar; AOutLen: Integer): Integer; cdecl;
```

宿主侧把返回值转成自己的 `string`，再用 `TLWApp.AddAjax` 暴露成
`/lw/ajax/<name>`。适用场景：对接硬件 SDK、特定协议适配、加密/算法、文件转换。
**不能**用来提供窗体或控件。

## 7. 阶段 1/2 落地前需补的验证（不影响本轮结论）

阶段 0 不依赖下表任何一项；阶段 1（进程级）与阶段 2（Runtime Package）动工前必须补齐。

| 项 | 为什么必须验 |
|---|---|
| Lazarus Runtime Package 双模块类身份 | 决定方案③是否真的成立（本文只做了裸 DLL 实测） |
| 包内窗体 `.lfm` 资源定位 | 多模块下 `HInstance`/`FindResource` 可能找不到资源 |
| nogui 与 win32 两套 bpl 并存 | 同一插件需两份产物，验证加载不串 |
| Linux `.so` 边界 | 若一侧用 `cmem`，堆不同，§3.2 的"侥幸"立即失效 |
| ~~进程级路由下的静态资源~~ | **已验证并升级**：框架静态资源改由宿主直出（`lwroute.LWRouteStaticLocal` 白名单），插件部署可以只带 exe；插件直连自己端口时 `LWFindClientFile` 照常自出 |

（阶段 1 已落地，剩余项只影响阶段 2。）

## 8. 验收标准（按阶段）

- 阶段 0：新增一个 `plugins/umod_x.pas` 后只需重编 + 发布，页面可访问、
  事件可派发、AJAX 可调用；主框架源码零改动。
- 阶段 1：`/order/` 与 `/report/` 分别落到不同进程；杀掉其中一个，另一个
  正常服务；单模块升级不中断其它模块。
- 阶段 2：插件包提供的新控件能出现在主框架页面并正常回写。

## 9. 附：实验复现

```bash
cd tmp/lwpoc
C:/111/fpc/bin/x86_64-win64/fpc.exe -O- lwpoclib.pas   # -> lwpoclib.dll
C:/111/fpc/bin/x86_64-win64/fpc.exe -O- pocmain.pas    # -> pocmain.exe
./pocmain.exe class    # 类身份
./pocmain.exe mem      # 堆
./pocmain.exe str      # 托管字符串
```
