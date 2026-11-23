## 中文README 
# lazarusWeb

可快速将Lazarus桌面程序转换为能在浏览器运行的web应用，用**真实的 LCL 控件树**直接序列化成界面；**默认渲染层是 Alpine.js**（内置依赖，零额外部署），Ext JS 是可选渲染层（需自行提供 ext 目录并用 `--client=ext` 显式启用）。业务程序只需要把窗体基类从 `TForm` 改成 `TLWForm`，其余代码（事件、属性、`.lfm`）原样保留，就能以服务程序的形式跑在浏览器里。

浏览器 (Alpine.js 默认 / Ext JS 可选) 服务端 (Lazarus, nogui widgetset)
| 浏览器端（默认 Alpine.js，可选 Ext JS） | 通信 | 服务端 (Lazarus, nogui widgetset) |
| :--- | :---: | :--- |
| `lw-alpine.js` + `alpine.min.js` 渲染/协调器<br>（可选：`lw.js` + `ext-<版本>/`）<br><br>原生 DOM/CSS（可选：Ext.window/panel/grid/...）<br><br>`WS传事件/长轮询游标收推送` | <br>**HTTP←→JSON**<br><br> | `lwhttp` fcl-web 多线程服务器<br>`lwsession` 每标签页一棵 LCL 控件树<br>`lwwriter` LCL 树→JSON<br>`lwdispatch` 事件→RTTI 调业务代码<br>`lwws` nogui 补丁(虚拟显示器/画布) |

## 环境要求

- FPC 3.3.1/3.2.2 + Lazarus
- Alpine.js（内置依赖）
- Ext JS 7.0.0（GPLv3 版，**可选**：发布包不包含，需自行从 Sencha 官方渠道获取后放入 `ext-7.0.0\`；不放置时默认使用内置的 Alpine.js 渲染层）  
- **Ext 支持为可选功能，ext-js 文件由用户自行获取，其授权合规由使用者自行负责。**  

## 控件安装（Lazarus IDE 设计期包）

要在 IDE 设计器里打开带 lazarusWeb 控件的窗体、用「新建工程向导」和
「生成 lazarusWeb 窗体模板」Tools 菜单，必须先按**固定顺序**处理四个包。
顺序不能颠倒：`lwserver` / `lwvst` 都依赖 `lwcore`，`lwdesign`（设计期包）
又依赖前三者，跳步会在 Install 时报 `Can't find unit lwcore / lwserver / lwvst`。

| 顺序 | 包 | 类型 | 依赖 | 在 IDE 里做什么 |
|---|---|---|---|---|
| 1 | `src\lwcore.lpk` | RunAndDesignTime | LCL / FCL / fcl-image | **只编译**（Compile），不 Install |
| 2 | `src\lwserver.lpk` | RunAndDesignTime | LCL / FCL / **lwcore** | **只编译**（Compile），不 Install |
| 3 | `src\lwvst.lpk` | RunAndDesignTime | LCL / **lwcore** / lclextensions_package / laz.virtualtreeview_package | **只编译**（Compile），不 Install |
| 4 | `src\design\lwdesign.lpk` | DesignTime | LCL / IDEIntf / **lwcore** / **lwserver** / **lwvst** | **Compile → Install**（会重建 `lazarus.exe`，然后重启 IDE） |

三层依赖的用意——**两条构建链互不污染**：

- 无头链：`lwcore` + `lwserver`。两者都不引用 VirtualTreeView，`--ws=nogui`
  可以编译，用于 Linux/无 X 的部署目标。
- GUI 链：`lwvst`（`TLWDBVirtualTreeView`，需要真 GDI）+ `lwdesign`。
  这两个包**只能用目标 IDE 的 widgetset（本机 win32）编译**，不要加
  `--ws=nogui`：`lclextensions_package` / `laz.virtualtreeview_package` 只有
  `include/<widgetset>`、`include/intf/<widgetset>`，没有 nogui 版本，会报
  `Cannot open include file "uses.inc"`。
- 需要多列/虚拟节点树的无头工程请改用 `lwcore` 里的 `TLWDBTreeView`
  （示例见 `demos\treedemo_nogui`，nogui 构建下已验证可跑）。

具体步骤：

1. 命令行先注册四个包（让 IDE 认识它们，否则新建工程报「找不到包」）：

   ```
   tools\install_design.bat
   ```
   等价手工命令（把 `C:/111/lazarus` 换成你的 Lazarus 目录）：
   ```
   lazbuild --add-package-link src\lwcore.lpk
   lazbuild --add-package-link src\lwserver.lpk
   lazbuild --add-package-link src\lwvst.lpk
   lazbuild --add-package-link src\design\lwdesign.lpk
   ```
   注意 `--add-package-link` 后面是**一个空格 + 路径**，写成
   `--add-package-link=...` 会被当前 lazbuild 拒绝（`does not allow an
   argument`）且什么也没登记。
   `--add-package-link` 只是「登记/最近打开」，**不等于安装**。

2. 打开 Lazarus，按上表顺序逐包 `Package → Open Package File → <包>.lpk`，
   前三个点 **Compile**（只编译出 ppu，不 Install）；第四个 `lwdesign.lpk`
   点 **Compile → Use → Install**，弹窗问是否重建 IDE 时选「是」，等重建完
   **重启 Lazarus**。

3. 重启后验证：`文件 → 新建 → 项目` 里出现两个 lazarusWeb 模板、
   组件面板出现 **lazarusWeb** 页、Tools 菜单出现「生成 lazarusWeb 窗体模板」。

> 换新版框架或改过设计期包源码后，必须重做第 2 步里 `lwdesign.lpk` 的
> Compile → Install → 重启 IDE，否则设计器与 Tools 菜单仍跑旧代码。
> 不要在 IDE 里编译 `lwserver.lpk`（nogui widgetset 单元不在 IDE 搜索路径，
> 会报 `Can't find unit noguiint`），该包交给命令行 `lazbuild` 或新建工程即可。
> 完整踩坑记录见 `docs/NOTES.md` 坑 15 / 坑 16。

## 跨平台构建矩阵（宿主 → 目标）

全部源码（`src/`、`tools/`、`demos/`）均为跨平台代码：核心单元的平台差异
（时间戳精度 / 临界区可重入 / 路径风格等）用 `$IFDEF MSWINDOWS/LCLGTK2/LCLQT5`
隔离且都有非 Windows 分支，不引用任何 Windows 专属单元；所有 `.lpi`/`.lpk`
的路径一律正斜杠、不固化目标 CPU/OS（产物名用 `$(TargetCPU)-$(TargetOS)` 变量）。

**FPC 版本**：同一份源码同时支持 **FPC 3.2.2 与 3.3.1**。3.3.1 新增的
`fphttpserver` 能力（`RegisterUpdateHandler` / `ThreadMode` / `ConnectionHandler`）
与 `SetTextAutoFlush`、`GetHTTPStatusText` 等，用 `{$IF FPC_FULLVERSION >= 30301}`
双分支包着；3.2.2 下走等价垫片（OnRequest 手工接管升级、`select` 自实现
`LWCanRead`、自带状态码表、1 字节文本缓冲），3.3.1 下走原生路径，行为一致。

已实测的交叉编译组合（Windows 宿主，nogui widgetset）：

| 目标 | 命令要点 | 产物 |
|---|---|---|
| x86_64-linux | `--os=linux --cpu=x86_64 --ws=nogui --compiler=...ppcrossx64.exe` | `gallery_nogui-x86_64-linux`（ELF x86-64） |
| mips64el-linux | `--os=linux --cpu=mips64el --ws=nogui --compiler=...ppcrossmips64el.exe` | `gallery_nogui-mips64el-linux`（ELF MIPS，龙芯 3A 实测可跑） |

```
lazbuild --os=linux --cpu=mips64el --ws=nogui \
         --compiler=/c/111/fpc/bin/x86_64-win64/ppcrossmips64el.exe \
         demos/gallery/gallery.lpi
# → gallery_nogui-mips64el-linux（ELF，约 6.5MB 代码段；ld 的 abicalls
#   混链警告可忽略）
```

Linux 宿主上直接 `lazbuild` 各 demo 的 `.lpi` 即可；`build.sh` 与
`build.bat` 功能等价。目录/文件名在 Unix 下区分大小写，详见下一节。

## 目录结构

| 路径 | 内容 |
|---|---|
| `src/core/lwbase.pas` | 公共类型、工具、threadvar 会话指针 |
| `src/core/lwws.pas` | nogui widgetset 补丁（**必须**，见下） |
| `src/core/lwform.pas` | `TLWForm` 业务窗体基类（含 `SendFile` / `SendText`） |
| `src/core/lwwriter.pas` | LCL 控件树 → JSON |
| `src/core/lwsession.pas` | 会话、窗体清单、同步模态 |
| `src/core/lwdispatch.pas` | 浏览器事件 → 真实 LCL 控件事件 |
| `src/core/lwhttp.pas` | HTTP 服务、静态资源、API 路由、上传/下载 |
| `src/core/lwapp.pas` | 应用门面（注册/命令行/启动） |
| `src/core/lwconfig.pas` | 服务端配置文件（INI：Port / Theme / ExtDir） |
| `src/core/lwfileupload.pas` | `TLWFileUpload` 上传按钮控件 |
| `src/core/lwcamera.pas` | `TLWCamera` 拍照控件（手机唤起系统相机 / 桌面页面内取景） |
| `src/core/lwdlg.pas` | **LCL 对话框改道浏览器**（ShowMessage / MessageDlg / InputQuery / TOpenDialog …） |
| `src/core/lwupload.pas` | multipart 解析与落盘 |
| `src/core/lwdownload.pas` | 下载令牌表（URL 里不暴露路径） |
| `src/core/lwnewproject.pas` | 工程骨架模板（向导与 `lwnew` 共用） |
| `src/client/lw.js` | 浏览器端渲染与增量协调 |
| `src/client/lw.css` | 基础样式 |
| `src/lwcore.lpk` | 运行时包（不依赖 widgetset，设计期包要用） |
| `src/lwserver.lpk` | 运行时包（服务端；nogui 下自动打 widgetset 补丁） |
| `src/design/lwdesign.lpk` | **设计期包**：新建工程向导 / New Form / 组件面板 |
| `demos/hello` | 最小示例 |
| `demos/grid` | 表格示例（加载/过滤/编辑/状态栏） |
| `demos/multi` | 综合示例（菜单/多标签/工具栏/**同步模态**） |
| `demos/db` | **SQLite 数据库示例**（TDBGrid/TDBEdit/TDBMemo 增删改查、排序、过滤、分类统计） |
| `demos/files` | **文件上传/下载示例**（TLWFileUpload、SendFile、SendText 导出 CSV） |
| `demos/dbaware` | **DB 感知控件全家桶**（TDBText/TDBListBox/TDBRadioGroup/TDBLookup*/TDBImage 数据感知实测；主窗体 87 个对象，`uAwareMain.lfm` 866 行） |
| `demos/dialogs` | **对话框示例**（ShowMessage/MessageDlg/InputQuery/QuestionDlg/MessageBox/OpenDialog/SaveDialog） |
| `demos/gallery` | **全功能画廊**（对标 uniGUI 全功能 Demo：12 页 60+ 控件 —— 标准控件/按钮/扩展输入/容器/网格/工具条/图表/HTML·PDF·上传/对话框/定时器/DB 感知/大表分页，`tests/t_gallery.py` 50 项回归） |
| `docs/MAPPING.md` | 控件/属性映射表 |
| `docs/CONTROL_MATRIX.md` | **66 个可视控件的实测支持度矩阵**（自动生成） |
| `docs/DB_AWARE_MATRIX.md` | **12 个 DB 感知控件的实测矩阵**（绑定/显示/同步/回写，自动生成） |
| `docs/SECURITY.md` | **安全说明**：SQL 注入与信任边界（框架无 SQL 通道、demo 参数化范例、业务代码自检清单） |
| `docs/NOTES.md` | nogui 移植踩坑记录，坑 1–108 按时间累积（重点；坑 23/66 等旧结论已被后续坑修订，以标注为准） |
| `docs/HOW_IT_WORKS.md` | **工作原理详解**（给第一次读代码的人：一次点击的完整回路、为什么不能全量 RTTI dump） |
| `docs/MANUAL.md` | **使用手册**（使用篇 + 开发篇） |
| `docs/FEATURES.md` | **特点与亮点**（一页看懂强在哪、边界在哪：十一个能力 / 七个做对了的决定 / 数字速览 / 与 uniGUI 对照） |
| `docs/INDEX.md` | 文档导航索引（按场景找文档） |

## 快速开始

```
cd c:\LazarusWeb
build.bat                 :: 编译全部演示（lazbuild -B --ws=nogui）
build.bat grid            :: 只编译 demos\grid（工程名自动识别，db→dbdemo、files→filedemo）
demos\multi\multi.exe --port=8090
demos\db\dbdemo.exe --port=8095      :: SQLite 增删改查示例（需 demos\db\sqlite3.dll）
demos\files\filedemo.exe --port=8096 :: 上传/下载示例
demos\dbaware\dbaware.exe --port=8110 :: DB 感知控件全家桶
start-gui.bat           :: 双击启动 GUI 版（dbaware_gui.exe，见下节）
                           Linux/macOS: ./start-gui.sh
```

浏览器打开 `http://127.0.0.1:8090/`。命令行选项：

```
--config=path         指定配置文件（缺省自动找 <exe名>.ini / lazarusWeb.ini，见下节）
--port=8090           监听端口
--root=C:\LazarusWeb  项目根目录（含 src/client；ext-<版本> 仅在可选 Ext 层需要）；缺省取当前目录
--form=Name           默认窗体名
--client=ext          浏览器渲染层：ext | alpine；不指定时自动探测（都在优先 alpine）
                      内置默认是 ext；部署带 alpine 资源时会自动切到 alpine，显式指定优先
--ext=7.0.0           默认 Ext 版本（URL 也可 ?ext=<版本> 临时切换）
--extdir=目录         ext-js 目录（配置项 ExtDir 的等价物）
--theme=crisp         默认主题（Ext 渲染层：classic/crisp/gray/material/neptune/graphite；
                      Alpine 层的配色不在这里，见下）
--title=标题          浏览器标签页标题（缺省取 Application.Title）
--timeout=20          会话空闲超时（分钟）
--trust-proxy         放到 nginx/Caddy 后面时加：日志里的客户端 IP 取 X-Forwarded-For
--ssl                 开 HTTPS（FPC 自带；不给证书则自动生成自签证书）
--ssl-host=名         证书主机名/SAN 域名或 IP，不是监听地址
--ssl-cert=文件       指定 PEM 证书（与 --ssl-key 成对；相对路径按 exe 目录解析）
                      给了证书/私钥即自动开 HTTPS，不必再写 --ssl
--ssl-key=文件        指定 PEM 私钥（与 --ssl-cert 成对）
--tls-cert= / --tls-key=  上面两个的别名（给了同样自动开 HTTPS）
--ajax-cors           /lw/ajax/* 允许跨域调用（给第三方页面集成用）
--verbose             打印每个请求与异常栈
--nogui               GUI 构建下也不弹服务端面板（服务化部署）
--patch=1             增量补丁（事件只回变化的 ops，默认关；老前端自动退回全量）
--log=path            把服务端日志追加写入文件
--help                帮助
```

参数表按源码 `src/core/lwapp.pas` 的 `--help` 输出对齐；细节（如 `--client` 的自动探测）以源码为准。

### 配置文件（INI）

不想每次敲一长串参数，就在 exe 旁边放一个 INI（模板见
[`lazarusWeb.ini.sample`](lazarusWeb.ini.sample)）：

```ini
[lazarusWeb]
Port=8090
Theme=crisp
ExtDir=ext-7.0.0
;Patch=0
;Client=ext
```

| 项 | 含义 | 留空/非法时 |
|---|---|---|
| `Port` | 监听端口 | 用默认 **8090**（超范围会给警告） |
| `Theme` | 默认主题（仅 Ext 渲染层，`?theme=` 仍可临时覆盖）；Alpine 层的配色在标题栏按钮里选，见 `docs/MANUAL.md` §5.1 | 用 `crisp` |
| `ExtDir` | ext-js 目录，绝对/相对路径都行 | 自动查找 `<root>\ext-<版本>` |
| `Patch` | 增量补丁开关，`1` = 事件只回变化的 ops | 默认 `0`（关） |
| `Client` | 浏览器渲染层：`ext` / `alpine`（不写则自动探测） | 自动探测 |
| `SSL` | 开 HTTPS：`1` / `true` / `yes` | 默认 `0`（HTTP） |
| `SSLHost` | 证书主机名/SAN 域名或 IP；不是监听地址 | 留空时用自签证书 |
| `SSLCert` | PEM 证书路径（与 `SSLKey` 成对，相对路径按 exe 目录） | 留空时用自签证书 |
| `SSLKey` | PEM 私钥路径（与 `SSLCert` 成对） | 留空时用自签证书 |

细节（都是踩过之后定的）：

- **优先级**：内置默认值 < 配置文件 < 命令行。`--port=9000` 永远赢过 `Port=8090`，
  所以"一份 exe 拷十份、每份一个 ini"和"临时换个端口调试"可以并存；
- **放在哪里**：`--config=<路径>` 显式指定；否则依次找
  `<exe目录>\<exe名>.ini` → `<exe目录>\lazarusWeb.ini` →
  `<当前目录>\<exe名>.ini` → `<当前目录>\lazarusWeb.ini`；
  相对路径的 `--config=` 也允许相对 exe 目录（服务方式启动时 cwd 往往是 System32）；
- **格式很宽容**：节名可写可不写（`[lazarusWeb]` / `[server]` / 不写都认），
  键名不区分大小写且忽略 `-`/`_`（`ext-dir` = `ExtDir`），值可以用引号包住，
  `;` 和 `#` 开头是注释。文件请存 UTF-8 或纯 ASCII（ANSI 写中文路径会乱码）；
- **`ExtDir` 是"目录"不是"版本号"**：给了它，`/ext/<任意版本>/...` 都从这个目录取
  （一个部署一般只带一个 ext 版本）；指向不存在或空目录时打警告并自动回退到
  `<root>\ext-<版本>`，不会让服务起不来；
- 启动横幅会打印实际用的配置文件路径和 ext 目录，排障时先看这两行。

写一个自己的 Web 程序（服务端总共就这么多代码）：

```pascal
program myapp;
uses Interfaces, Forms, lwapp, uMain;
begin
  Application.Initialize;
  TLWApp.Register(TMainForm);   // 类名去掉 T 即浏览器里的窗体名
  TLWApp.Run;                   // 自动调用 LWInstallWidgetSet
end.
```

窗体单元里唯一要改的一行：

```pascal
uses ..., lwform;
TMainForm = class(TLWForm)   // 原来是 class(TForm)
```

> **重要**：编译必须带 `-B`（`lazbuild` 不把 `.lfm` 记进依赖表，
> 只改界面不改 `.pas` 时旧 `.o` 会被继续使用）。
> `build.bat` 已经加好。

## 部署（独立目录运行）

框架**支持**把 `ext-<版本>` 目录拷到应用自己的目录，做成自包含部署。未传
`--root=` 时，根目录（Root）按以下顺序确定：

1. **当前工作目录** —— 只要该目录下有 `ext-<版本>` 目录就认定
   为根。在哪个目录启动就用哪个目录，最符合直觉。
2. **可执行文件目录向上最多 5 层** —— 找「`ext-<版本>` + `src/client/lw.js`
   都在」的目录（双击运行、或从别处启动时的兜底）。
3. 都找不到 → `C://LazarusWeb`。
4. 显式 `--root=<路径>` 优先级最高，压过以上三条。

`/lw/lw.js`、`/lw/lw.css`（以及 alpine 的 `/lw/lw-alpine.js`、`/lw/lw-alpine.css`、
`/lw/alpine.min.js`）的查找都做了多路回退，下面几种布局都能跑：

| 布局 | 需要的文件（按渲染层取其中一套） |
|---|---|
| 标准仓库布局（推荐） | `<root>/src/client/lw.js`、`lw.css`；或 `lw-alpine.js`、`lw-alpine.css`、`alpine.min.js` |
| 扁平部署 | 上述文件与 exe 同目录 |
| 半扁平 | `<exe目录>/lw/` 或 `<root>/lw/` 下放上述文件（旧部署的 `<root>/client/` 仍兼容） |
| 兜底 | 从 root 逐级向上找 `src/client/` 下的同名文件 |

最小自包含部署目录（**默认 Alpine.js 渲染层，不需要 ext 目录**）：

```
MyApp/
  MyApp.exe
  src/client/alpine.min.js   44 KB   Alpine.js 本体（defer 加载，不走 CDN）
  src/client/lw-alpine.js    205 KB  渲染/协调器（自适应仅本层；模板两层共用）
  src/client/lw-alpine.css    59 KB  样式：7 套配色（亮色/米黄/护眼绿/高对比/深色/深蓝/墨绿）的 CSS 变量都在这里
  tpl/                              可选：窗体模板；Alpine/Ext 两层都读取，缺失时静默回退设计期布局
  favicon.ico                       可选：浏览器标签图标（放 exe 同目录或 --root 目录皆可）
  ext-<版本>/                       可选：Ext JS 渲染层（约 75MB，需 --client=ext 显式切换）
  cert/                             可选：开 SSL 且使用自有 PEM 时放 server.crt/server.key/ca.crt
  libssl-3-x64.dll + libcrypto-3-x64.dll  可选：开 SSL 时必须放 exe 同目录
```

（走 Ext 渲染层时对应换成 `src/client/lw.js` + `lw.css` + `ext-<版本>/`；
三个 alpine 文件缺一不可——少了 `alpine.min.js` 自动探测会判 alpine 不可用并
回退 ext，少了 css 页面能跑但完全没样式。）

验证：启动后看横幅的 `Root :` 与 `Client :` 行（默认应为 alpine），或
`curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8090/lw/lw-alpine.js`（应为 200）。

### 启动演示

```bat
start-demo.bat            :: 默认 8092，双击即可
start-demo.bat 8095       :: 指定端口
```

```bash
./start-demo.sh           # Linux / macOS，默认 8092
./start-demo.sh 8095
```

服务在前台运行，浏览器打开提示的地址即可，`Ctrl+C` 或关闭窗口即停止。
（端口被占时换一个：进程被强杀后可能残留 `LISTENING PID 0` 的孤儿 socket，
`netstat` 看得到但杀不掉，换端口最省事。）

## 跨平台（Linux / macOS）

核心单元只用 FPC/LCL 的通用设施：`fphttpserver`、`SysUtils` 的
`DirectoryExists`/`FileExists`/`ExtractFileDir`、以及 `PathDelim` /
`IncludeTrailingPathDelimiter` 拼路径 —— **没有** `Windows`、`winsock`、
`ShellExecute` 之类的平台单元（`grep -rn "Windows" src/core/*.pas` 只会在
注释里命中）。`lwws.pas` 在非 nogui widgetset 下退化为空实现，所以在
win32/gtk2/qt5/carbon 下也能编译（运行仍建议 `--ws=nogui`）。

构建：

```bash
./build.sh                        # 全部 demo
./build.sh dbaware                # 单个
LAZBUILD=/opt/lazarus/lazbuild ./build.sh

tools/build.sh                    # 全部工具（convert/hyper/audit/dbcheck/hyper_gui/convert_gui）
tools/build.sh convert            # 单个工具（fpc 直编，无 LCL）
tools/build.sh hyper_gui          # GUI 工具用宿主 widgetset 编
```

`.lpi` 未固定 `TargetOS`/`TargetCPU`，按宿主平台构建；Unix 下产物没有
`.exe` 后缀（`build.sh` 会同时删掉两种名字）。Windows 用 `build.bat`，
`LAZBUILD` 环境变量同样可覆盖。

运行时依赖差异：

| 依赖 | Windows | Linux | macOS |
|---|---|---|---|
| SQLite（demo 用） | `sqlite3.dll`（demo 目录已带） | `libsqlite3.so`（`apt install libsqlite3-0`） | 系统自带 |
| Alpine.js / lw-alpine.js（默认）；Ext JS / lw.js（可选） | 同左 | 同左（路径按 `PathDelim` 拼） | 同左 |
| 命令行参数 | `--port=` `--root=` `--theme=` `--config=` | 同左 | 同左 |

注意 Unix 文件名区分大小写（Windows 不区分），`src/client`
等目录/文件名请保持原样（ext 目录名可任意，服务端会自动识别根下唯一的
`ext-*` 目录）。

## 在 IDE 里用向导建工程（设计期包 `lwdesign`）

`src/design/lwdesign.lpk` 装上以后，Lazarus 里会多出三样东西：

| 位置 | 内容 |
|---|---|
| File → New → Project | **lazarusWeb** 一个模板，选中后连弹三框：① 应用模式（普通 / **服务(daemon)**，服务模式额外生成 `uDaemon.pas`/`uMapper.pas`/`lazarusWeb.ini`，详见 `docs/SERVICE_NAMING.md`）；② 工程类型（`lazarusWeb project` GUI 调试档 / `lazarusWeb project(nogui)` 部署档）；③ 工程模板（常规 / 插件）。落盘时机与 Lazarus 自带模板一致：选完三框不写盘（工程是"虚拟"的），按保存（Ctrl+S）时才弹"保存项目"对话框，目录默认取 IDE 选项里的"项目构建测试的目录"，这一步生成 `.lpr/.lpi/umain.pas/.lfm/build.bat/build.sh/favicon.ico`，并把框架的 `src/client` 拷到工程目录下的 `lw/`（运行期按 `exe/lw/<文件>` 找静态资源；站点图标 `favicon.ico` 则放工程根目录，服务端按 `<root>` → `<exe 目录>` 顺序找）。nogui 档的 `.lpi` 宏在**保存事务真正结束之后**才补写（`.lpi` 与所有单元都落盘、连续两轮稳定才动手；保存过程中绝不弹框、不重载工程，见 NOTES 坑 172），所以**保存后约 1 秒**才补齐，补完弹一句「nogui 档：重新加载工程后生效」——点"是"重开工程，F9 就是无窗口控制台服务 |
| File → New → File | **lazarusWeb Form** —— 一个 `TLWForm` 窗体单元，直接进设计器 |
| 组件面板 | **lazarusWeb** 页：`TLWFileUpload` / `TLWCamera` 等 |

安装（只需一次）：

```
tools\install_design.bat        :: 先注册三个包
```

然后按它的提示在 IDE 里 `Package → Open Package File → lwdesign.lpk → Use → Install`，
让 IDE 重建一次（设计期包是静态链接进 `lazarus.exe` 的，必须重建才能生效）。

第一次用，五步：

1. **装包**：上面一行命令 + `Install` 重建 IDE（换新版包也要重装一次，否则跑的还是旧代码）；
2. **新建**：`文件 → 新建 → 项目` 选模板（GUI 档调试 / nogui 档部署），选完**不写盘**；
3. **保存**：`Ctrl+S` 弹标准"保存项目"对话框才落盘。工程名别叫 `LWApp`（与 `lwapp.pas` 撞名，编译报 `Duplicate identifier "LWAPP"`），默认的 `LWApp1` 就安全；
4. **nogui 档多一步**：保存后约 1 秒弹「nogui 档：重新加载工程后生效」，点 **"是"**；
5. **F9**。

> **注意：保存后 1 秒内按 F9，用的还是 win32 widgetset** —— 宏刚写进 `.lpi`
> 文件，IDE 内存里的工程选项还没重读，编出来照样弹服务端面板窗口。等第 4 步
> 那个询问框出现、点"是"之后再 F9 就对了；不想重开工程就用工程目录里的
> `build.bat` 编。

落盘文件清单、每一步的界面细节和排障（`%TEMP%\lazarusweb-wizard.log`）见
`docs/MANUAL.md`「用 IDE 向导新建工程（从头建一个）」。

> TLWForm 是**真正的 TForm 后代**，不是 uniGUI 那种影子类，所以不需要任何
> 设计期代理：拖上去的 TButton/TEdit 就是 LCL 自己的控件，属性面板、事件页、
> 对齐工具、锚点全部照常可用，窗体设计器里看到的布局就是浏览器里的布局。

不想开 IDE 也可以直接用命令行生成工程骨架（此处生成的是 Lazarus 工程，不是窗体模板；模板骨架请用上面的 IDE Tools 菜单）：

```
tools\lwnew.exe --name=DemoApp --dir=C:\work\DemoApp --units=C:\LazarusWeb\src\core
```

`--units` 指定源码目录时不依赖已安装的包；省略它则要求 `lwserver` 包已注册。

**编译方式**：LCL 用哪个 widgetset 由 `.lpi` 里的 `LCLWidgetType` 宏决定。
仓库里的 demo 和手工改造的老工程都没有这个宏，IDE 里按 F9 会用 IDE 自己的
widgetset（win32），链接不到 LCL 的 nogui 单元，只能靠 lazbuild 指定；向导
生成的 nogui 工程已经把这个宏写进 `.lpi`，重新加载工程后 IDE 里 F9 直接就是
nogui（保存后 1 秒内按 F9 仍会是 win32，见上一节）。`build.bat` 两种都写好：

```
lazbuild -B --ws=nogui <工程>.lpi
```

> 注意区分：**包**（`lwserver.lpk`）在 IDE 里可以直接编译/安装 —— `lwws.pas`
> 的 nogui 补丁用 `{$IFDEF LCLnogui}` 包着，非 nogui 下退化成空实现；
> 但**没带 `LCLWidgetType` 宏的工程**（demo、手工改造的老工程）必须
> `--ws=nogui`，见 `docs/NOTES.md` 坑 15。

## 文件上传 / 下载

上传用 `TLWFileUpload`（`TButton` 的后代，可设计期摆放）：

```pascal
procedure TFileForm.btnUploadUpload(Sender: TObject; const AFileName: string);
begin
  // AFileName 是服务端上的完整路径，直接 TFileStream 打开即可
  lstFiles.Items.Add(ExtractFileName(AFileName));
end;
```

- 浏览器端弹系统文件对话框，XHR 带进度上传，按钮文字实时显示百分比；

## 拍照（TLWCamera）

`TLWCamera`（`TLWFileUpload` 的专用后代）拖到窗体上即可：

```pascal
procedure TMainForm.camPhotoCapture(Sender: TObject; const AFileName: string);
begin
  // 照片已在服务端落盘（%TEMP%\lw_uploads\<会话>\camPhoto\xxx.jpg）
end;
```

- 手机/平板：点按钮直接唤起**系统相机**（`Facing` 换前后置），拍完经既有
  上传通道传回并触发 `OnCapture`；**局域网 http 就能用**；
- 桌面：HTTPS 或 localhost 下弹**页面内取景框**（getUserMedia，实时画面 +
  拍摄/取消/选择图片），拍下的帧压到长边 1600px 转 JPEG 走同一通道；
  局域网 http 的桌面页面浏览器禁止调摄像头，自动退化为「选择图片文件」；
- 预览：`PreviewImage := 'imgPhoto'` —— 浏览器拍完立刻本地显示到指定
  TImage，照片数据不走组件树补丁；服务端只拿文件路径；
- 完整说明见 `docs/MANUAL.md` 使用篇「拍照」，范例
  `demos/mobile_demo`，回归 `tests/cdp_camera.py`。
- 服务端解析 `multipart/form-data`，落到
  `%TEMP%\lw_uploads\<会话号>\<控件名>\`（或用 `TargetFolder` 指定）；
- 文件名会做安全化处理（去路径、去 `..`、去非法字符），多选时逐个触发 `OnUpload`；
- `Filter`（`'文本|*.txt;*.csv|所有|*.*'`）、`Multiple`、`MaxSizeKB` 都参与校验。

下载在业务代码里一行：

```pascal
SendFile('C:\data\报表.xlsx');              // 推服务端已有文件
SendText(csv.Text, '清单.csv', True);       // 现算文本直接下载（True = 带 BOM，Excel 认中文）
```

URL 里 **不会**出现服务端路径：`SendFile` 把文件登记成一次性令牌，
浏览器拿到的只是 `/lw/download?t=<令牌>`，令牌 30 分钟或首次取用后失效。

| 路由 | 说明 |
|---|---|
| `POST /lw/api/upload?sid=&id=` | `multipart/form-data`，返回新组件树 |
| `GET /lw/download?t=<令牌>` | 带 `Content-Disposition`（含 `filename*=UTF-8''`） |

**完整业务示例**：`demos\db` 给每个商品挂附件（上传 → 落
`attachments\item<id>\` + 写 `attachments` 表 → 下载/删除），
用独立数据库连接做附件写库，不打断正在编辑的主记录 —— 详见
`demos\db\README.md` 的"附件是怎么接的"。

## 对话框（ShowMessage / MessageDlg / TOpenDialog …）

**业务代码一行都不用改**。LCL 的这些函数在服务端被改道成"浏览器里弹模态框"，
服务端线程挂在那儿等用户点，点完再继续往下走：

```pascal
procedure TMainForm.Button1Click(Sender: TObject);
begin
  if OpenDialog1.Execute then              // 浏览器弹出选文件框
    mmoLog.Lines.Add(OpenDialog1.FileName); // 返回的是服务端临时路径
  ShowMessage('lazarus Web测试');            // 浏览器弹出提示框
end;
```

直接可用（无需任何代码、无需 replace）：

| LCL 入口 | 浏览器里看到 |
|---|---|
| `ShowMessage` / `ShowMessagePos` | 无图标提示框 + 确定 |
| `MessageDlg` / `MessageDlgPos` | 按 `TMsgDlgType` 出 信息/警告/错误/问号 图标 |
| `InputQuery` / `InputBox` / `PasswordBox` | 带输入框（`PasswordBox` 是密码框） |
| `QuestionDlg` | 自定义按钮文字，`ModalResult` 原样返回 |
| `Application.MessageBox` / `LCLIntf.MessageBox` | `MB_YESNO` 等标志位按 Windows 语义解析 |
| `TOpenDialog.Execute` | 选文件（**先上传到服务端**），`FileName` = 服务端路径 |
| `TSaveDialog.Execute` | 输入文件名，`FileName` = 会话临时目录下的路径 |

几点必须知道的：

- **文件对话框拿到的是服务端路径**。浏览器不可能把本地路径交给服务端，
  所以选的文件会以 `multipart` 上传到 `%TEMP%\lw_uploads\<会话号>\pick\`，
  `FileName` 就是那个路径，`TFileStream` 直接打开就能读。存盘同理：
  `TSaveDialog.FileName` 落在 `...\<会话号>\save\`，你写完文件再 `SendFile` 推给用户下载。
- **线程会真的阻塞**。事件请求一直挂到用户答复（或 180 秒超时）才返回，
  这和桌面上的模态框行为一致；期间其它会话照常跑，同一会话里再弹第二个框会被拒绝并提示。
- **没有浏览器会话时**（比如在 IDE 里直接 F9 调试、或命令行跑单元测试）自动退回 LCL 原实现。
- 这些都是**运行时替换**，`lwdlg.pas` 挂在 `lwcore` 包里，业务工程 `uses lwapp` 即生效
  （`LWInstallDialogs` 在 `TLWApp.Run` 之前装好，接的是 `InterfaceBase` 的
  `PromptDialogFunction` / `InputDialogFunction` / `QuestionDialogFunction` /
  `Forms.MessageBoxFunction` 与 `RegisterWSComponent(TOpenDialog, …)`）。

**完整示例与 HTTP 级测试**：`demos\dialogs`（7 个按钮各演示一种），
`tests\t_dialog.py`（36 项，含"推送 → 答复 → 唤醒 → 返回值"全链路）。

## 运行时行为（与 uniGUI 的对应关系）

| uniGUI | lazarusWeb |
|---|---|
| TUniSession | TLWSession（每个浏览器标签页一个） |
| 组件 → JS 映射 | lwwriter + lw.js 增量协调（reconcile） |
| 同步模态（嵌套消息循环） | `ShowModal` 推送指令后挂起请求线程，`TEvent.WaitFor` 等浏览器关闭 |
| Ajax 事件 | `POST /lw/api/event`，值先写回控件再 RTTI 触发事件 |

业务代码完全感知不到 Web 的存在：

```pascal
procedure TMainForm.miAboutClick(Sender: TObject);
var f: TAboutForm;
begin
  f := TAboutForm.Create(nil);
  try
    if f.ShowModal = mrOk then          // Web 下这行会等用户点确定
      lblState.Caption := '已查看关于';
  finally
    f.Free;
  end;
end;
```

## HTTP API

| 路由 | 说明 |
|---|---|
| `GET /` | 界面外壳（`?ext=7.0.0&form=MainForm` 可覆盖默认值；`?fresh=1` 强制新会话） |
| `POST /lw/api/session` | 新建会话 `{form:"MainForm"}` → 返回树 + `sid` + `seq` |
| `GET /lw/api/attach?sid=` | **跨页签共享**：把本标签页挂到已有会话上（不存在回 410 + `gone`） |
| `GET /lw/api/tree?sid=` | 当前组件树 |
| `POST /lw/api/event` | `{sid,id,ev,val,row,col,vals,tab}` → 新组件树 |
| `GET /lw/api/poll?sid=&t=&after=` | 长轮询。带 `after` 按游标取推送（多页签各取各的）；不带则是老的销毁式队列。**推送的唯一通道** |
| `GET /lw/ws?sid=` | WebSocket 升级（RFC6455）：**只传事件请求/响应**（连着 WS 时事件走 WS 帧）；推送不走 WS，一律由上面的长轮询游标下发，断线自动退回 HTTP |
| `GET /lw/api/log?sid=` | 会话日志（Show/ShowModal/EndModal 全记录） |
| `POST /lw/api/close` | 结束会话 |
| `POST /lw/api/dlg` / `POST /lw/api/dlgfile` | 浏览器模态框（ShowMessage/MessageDlg/InputQuery/TOpenDialog…）的答复端点（见 `docs/MAPPING.md` 对话框节） |
| `POST /lw/api/upload?sid=&id=` | 文件上传（`multipart/form-data`，字段名任意，可多文件） |
| `GET /lw/download?t=` | 下载（`t` 由 `lwdownload` 登记的一次性令牌，用后即废） |
| `GET /lw/ajax/<名字>` | **自定义 AJAX 端点**：`TLWApp.AddAjax(name, handler)` 注册，第三方 JS 直接 fetch |
| `GET /lw/healthz` | 健康检查（LB/k8s 探针）：`{"ok":true,"sessions":..,"uptime":..}` |
| `GET /ext/<版本>/<路径>` | Ext JS 静态资源（两版本并存） |
| `GET /favicon.ico` | 站点图标：`--root` 目录 → exe 同目录 → 都没有回 204；命中时 200 + `Cache-Control: public, max-age=86400`。两套外壳 HTML head 均带 `<link rel="icon">` |


## 控件支持度（实测）

`docs/CONTROL_MATRIX.md` 由 `tools\lwaudit` 自动生成（快照：2026-11-09，
晚于该日期的修复见 `docs/NOTES.md` 坑 97/107）：把 66 个常用 LCL
可视控件逐个在 nogui 下**真的创建出来 + 挂到窗体 + 序列化一次**，再对照 `lw.js`
是否真有渲染分支，分成五类：

| 状态 | 含义 | 当前数量 |
|---|---|---:|
| ok | 浏览器渲染成真实控件，双向事件可用 | 49（74.2%） |
| placeholder | 服务端可用，浏览器只画一个带类名的框 | 14 |
| kind-only | 已映射 kind 但缺渲染分支 | 1 |
| create-failed | nogui 下构造就抛异常（如原生 `TDBNavigator` 依赖按钮图元，改用 `TLWDBNavigator` 即可，见坑 29/41） | 1 |
| render-failed | 构造成功但序列化/渲染崩溃（如 `TDateEdit` NullDate，坑 107 已加兜底） | 1 |

最新分类以 `docs/CONTROL_MATRIX.md` 为准，本表只作概览。

另有 16 个非可视组件（`TTimer`/`TOpenDialog`/`TDataSource`/`TMainMenu`…）
服务端可直接使用，不参与渲染统计。

## 移动端（手机 / 窄窗口）

Alpine 渲染层内置移动端自适应，**业务代码零改动**：视口 ≤834px 自动进入
移动布局（≥1100px 退出，中间回滞防抖动），手机/平板/桌面窄窗口都会自动适配：

- **不配模板**：窗体按设计尺寸渲染（字号不缩小），超出屏幕的部分滚动
  平移查看——能用，但不是小屏优化的排布；
- **配模板**：为窗体写一份 HTML 模板（`{%控件名%}` 占位符引用控件 Name，
  浏览器把既有控件 DOM 搬进模板流式排布），事件与增量补丁照旧，跨断点
  两端自动切换、不丢状态；改模板刷新即生效，无需重编：
  - 移动 `<root>\tpl\<窗体名>.m.html` —— 手机单列排布，窗体贴满视口；
  - 桌面 `<root>\tpl\<窗体名>.html` —— 自定义桌面排布（居中卡片、
    双栏等），**窗体位置尺寸保持设计期**，只有客户区内容变流式；
- 手动切换：URL `?layout=mobile|desktop` 或 `LW.layout.set()`；
- **一键生成模板骨架**：装了设计期包 `lwdesign` 后，IDE 的 **Tools 菜单**
  多一项「生成 lazarusWeb 窗体模板（当前单元 LFM）」——按当前打开窗体的
  .lfm 一次生成**桌面 + 移动**两份模板骨架到 `<工程目录>\tpl\`（含
  `{%控件名%}` 占位符、按设计期逐控件定高的基础 CSS，铺满窗体的主区域
  按**容器**高度伸缩 `calc(100% - 其它控件)`（桌面按行累计，移动单列直加；
  不是 `100vh` —— 窗体开进浮窗时客户区比视口小），已存在逐份询问覆盖），
  生成时附自检报告（跳过的非可视控件、重复/非法占位符名、嵌套容器、主区域
  改动）；生成完拷到运行根目录（或工程目录即运行根目录时直接生效），刷新即见；
  详见 `MANUAL.md` 16.0；现成范例 `demos\mobile_demo\tpl\`（手工调过比例），
  生成器本身拿 `demos\gallery` 与 `demos\dbaware` 的真实窗体做解析与尺寸
  回归（后者覆盖浮窗里的主窗体、无主区域的登录页、顶部工具行 + PDF 主区域）；
- **拍照上传**：`TLWCamera` 控件（组件面板拖上即用）——手机点按钮唤起
  系统相机，拍完自动传回服务端（`OnCapture`），浏览器本地即时预览；
  局域网 http 可用（不需要 HTTPS），见 README「拍照（TLWCamera）」节；
- 使用说明见 `docs/MANUAL.md` 使用篇「移动端」节，模板开发指南见
  `MANUAL.md` 第二篇「16. 窗体模板开发指南（桌面 + 移动）」，机制与
  实测见 `docs/MOBILE.md` §8，可跑范例 `demos/mobile_demo`
  （同一窗体配了桌面 + 移动两份模板）。

## 已知限制

- 单窗体应用默认端口一条线程一个会话请求；模态期间该会话的其他请求会在事件队列上排队（与桌面程序模态语义一致）；
- 模态超时 `LW_MODAL_TIMEOUT_MS = 180000`（3 分钟）；
- 对话框一次只能有一个：同一会话里嵌套弹第二个会被忽略（浏览器端不能同时盖两层模态）；
- `TOpenDialog` 不读服务端目录列表 —— 浏览器选框只能"上传文件"，不能浏览服务器磁盘；
  想在服务端选文件请自己用 `TListView`/`TShellListView` 之类拼一个界面；
- 未适配的控件浏览器端是灰框占位（服务端照常活着），不影响别的控件；
  具体清单见 `docs/CONTROL_MATRIX.md`；
- `TSplitter` 只画分隔条，**不支持拖动**；`TProgressBar` / `TTrackBar` /
  `TUpDown` 浏览器端的调整都会回写服务端（`TUpDown` 上下箭头还会联动
  Associate 编辑框，见 `docs/NOTES.md` 坑 152）；
- 高 DPI 只按虚拟显示器 96 DPI 处理（`lwws.pas` 常量可改）；
  在 125%/150% 缩放的 Windows 上设计的窗体（lfm 里 `DesignTimePPI=120/144`）
  会在创建时自动缩放回 96 DPI（几何 + 字体一起，由 `Application.Scaled` 驱动，
  见 `docs/NOTES.md` 坑 18）。

## 数据库应用（TDBGrid / TDBEdit + SQLite）

`demos/db` 是完整的增删改查示例，`demos/dbaware` 是 **DB 感知控件全家桶**
（12 种 data-aware 控件一页摆开，支持度见 `docs/DB_AWARE_MATRIX.md`）。
DB 控件直接绑 `TDataSource`，浏览器上的行为与桌面程序一致：点行定位、
编辑字段、Post / Cancel / Delete / Locate。

| DB 控件 | 支持 |
|---|---|
| TDBGrid / TDBEdit / TDBMemo / TDBComboBox | 完全（浏览 + 回写） |
| TDBCheckBox | 完全（绑 0/1 字段必须设 `ValueChecked`/`ValueUnchecked`） |
| TDBListBox / TDBRadioGroup / TDBLookupComboBox / TDBLookupListBox | 完全（回传选中项/键值并写回字段） |
| TDBText / TDBImage | 只读（文本 / PNG 图片实时跟随字段） |
| TDBNavigator | 完全。lfm 里必须写真实类名 `TLWDBNavigator` 并 `RegisterClass(TLWDBNavigator)`——`RegisterClassAlias` 顶替不了已注册的 `TDBNavigator`（坑 29/41 已推翻旧方案）；代码侧也可用 `LWNewNavigator` 工厂 |

三条硬性规则（详见 `docs/NOTES.md`）：

1. **SQLite 字符串列一律用 `VARCHAR(n)`** —— `sqlite3conn` 把 `TEXT`/`CHAR`
   映射成 `ftMemo`，DBGrid 只会显示 `(MEMO)`；
2. **`sqoAutoApplyUpdates` 只发 SQL、不提交事务** —— 浏览器上点"保存"看着
   成功，其实挂在未提交事务里：程序一退全回滚，别的会话一写就
   `database is locked`。Post/Delete 后必须显式 `SQLTransaction.Commit`；
   连接再加 `Params.Add('journal_mode=WAL')` + `PRAGMA busy_timeout=10000`，
   写之前 `CommitRetaining` 丢掉旧读快照（WAL 的 `SQLITE_BUSY_SNAPSHOT`
   不受 busy_timeout 管辖）。完整做法见 `docs/NOTES.md` 坑 9.2；
3. **数据集处于编辑态时框架不下发网格行**（移动游标会触发自动 Post），
   浏览器沿用上一次的数据，保存/取消后自动刷新。

## 报表（打印 / 导出）

`src/core/lwreport.pas` 是服务端报表引擎：一份报表定义（标题 + 列 + 汇总 +
纸张），三种出口共用：

| 出口 | 说明 |
|---|---|
| 可打印 HTML | A4 `@page`、`@media print`、`thead` 逐页重复、斑马纹、合计行；预览页自带"打印 / 另存为 PDF"按钮 |
| CSV | UTF-8 BOM + CRLF，Excel / WPS 双击不乱码 |
| XLSX | 真 OOXML（`zipper` 打包，不依赖第三方库）：表头样式、冻结窗格、列宽、合计行 |

`demos/dbaware` 的"报表中心"窗体是完整示例：数据源切换、预览（iframe +
查看令牌）、点"打印…"带 `#print` 自动弹打印对话框、guest 账号禁用导出。

```pascal
rpt := TLWReport.Create(nil);
rpt.DataSet := FQry;
rpt.Title := '库存大表明细';
rpt.Columns.AddCol('编码', 'code', 30);
rpt.Columns.AddCol('金额', 'amount', 34, taRightJustify, rsSum);
rpt.SaveHTML(fn);   // 或 SaveCSV / SaveXLSX
```

## 自定义 AJAX 端点（第三方 JS 集成逃生舱）

页面里想嵌自己的 JS / 第三方组件库、绕开组件树协议直接要数据时，用
`TLWApp.AddAjax` 注册任意名字的端点（名字大小写不敏感、允许带 `/`）：

```pascal
TLWApp.AddAjax('items/price',
  function (Ctx: TLWAjaxContext): Boolean
  begin
    Ctx.Json('{"price":299.00}');    // 或 Ctx.Text(...) / Ctx.Error(...)
    Result := True;
  end);
```

浏览器端直接 `fetch('/lw/ajax/items?limit=3')`，跨页面集成加
`--ajax-cors` 启动参数。上下文对象提供 `Param()/Header()/JSONBody()/
FormField()` 与 `Session`（`?sid=` 或 `X-LW-Sid` 头，可读会话级数据）。
完整示例：`demos/dbaware/uAjax.pas`（items / items/price / whoami / echo 四个端点，
主窗体"图表/其它"页签里有一个直接 fetch 它们的原生 HTML 帧）。
未注册的名字回 404 并列出全部可用端点，便于自省。

## 跨页签会话共享

同一个浏览器的第二个标签页不再"另起一个会话重新登录"：sid 存在
`localStorage`，新标签页启动时先 `GET /lw/api/attach?sid=…` 挂到已有会话上
—— 登录身份、打开的窗体、服务端数据全都在，直接看到主窗体。

- 推送（模态 / 消息框 / 遮罩 / 下载指令…）统一进会话队列带序号，各页签用
  `/lw/api/poll?after=N` 各取各的，互不消费；
- 对话框指令带 `to=<页签标识>`，只有发起事件的页签弹窗，别的页签不重弹；
- 任一页签的操作（开窗体 / 关窗体 / 遮罩）实时同步到其它页签；
- 会话过期 / 服务重启时回 410，浏览器自动丢掉旧 sid 新建会话回登录页；
- `?fresh=1` 强制开新会话（多人共用一台浏览器、调试时用）。

回归：`tests/t_multitab.py`（22 项）+ `tests/cdp_multitab.py`（CDP 双真实标签页 6 项）。

## GUI 服务端面板  

每个 demo 有两种构建（以 dbaware 为例）：

| 构建方式 | 产物 | 形态 |
|---|---|---|
| `dbaware.lpi`（默认，`--ws=nogui`） | `dbaware.exe` | 控制台子系统：大黑终端实时打日志，tests/CI 用 |
| `dbaware_gui.lpi`（win32 + `-WG`） | `dbaware_gui.exe` | **GUI 子系统**：双击运行，只有一个小面板窗口 |

GUI 版启动后是一个服务端面板（对标 uniGUI 独立服务器的那个窗口）：

- 标题 `lazarusWeb 0.9.6 独立服务器 - 端口 <N>`；
- 菜单「文件」：打开浏览器（F5）/ 复制访问地址 / 退出；
- 菜单「管理」：清空日志 / 切换详细日志（verbose）/ 关于；
- 中间是滚动日志区（启动横幅 + 会话创建 + 请求日志，限 4000 行）；
- 状态栏三格：监听地址 / 在线会话数（每秒刷新）/ 运行时长；
- **系统托盘**：托盘常驻图标（蓝底 "LW"），点 X 只是隐藏到托盘（第一次弹
  气泡提醒），左键点图标恢复面板，右键菜单：打开面板 / 打开浏览器 / 退出；
- **只有菜单「退出」才真正停止服务**（优雅停止 ~0.3s：叫醒挂起的长轮询、
  断开 keep-alive 连接、accept 循环 250ms 内退出，见 NOTES 坑 44）。

命令行参数对两种构建都生效：`--nogui`（GUI 构建下退回无窗口模式，
服务化部署用）、`--log=path`（日志落盘）。日志统一走 `lwrlog` 单元：
console 构建写控制台、GUI 构建写面板、两者都可同时写文件。

自己的程序要做成 GUI 版，照抄 `demos/dbaware/dbaware_gui.lpi` 即可：
它与普通 `.lpi` 唯一的差别是 `LCLWidgetType=win32` 宏 +
`-WG` 编译选项 + 目标名加 `_gui` 后缀。注意 `.lpr` 里不要写
`{$APPTYPE CONSOLE}`（它会压过命令行的 `-WG`）。

## 部署（HTTPS / 反向代理 / 集群）

HTTPS 有两条路，都是零改代码：

1. **直接用 FPC 自带的 TLS（推荐，无需任何代理）**：给业务 exe 或
   `lwhyper` 加 `--ssl`，同一端口即从 HTTP 变 HTTPS；证书不给就自动生成
   自签证书。需随包带 `libssl-3-x64.dll` + `libcrypto-3-x64.dll`。
   集群场景在 lwhyper 外层开即可，worker 之间仍走明文。
2. **前置反向代理**：nginx / Caddy 终结 TLS，exe 保持 HTTP。完整指南与
   现成配置见 **`deploy/README.md`**、[`deploy/nginx.conf`](deploy/nginx.conf)、
   [`deploy/Caddyfile`](deploy/Caddyfile)。

`--ssl-host` 填的是**证书主机名**（浏览器地址里的域名/IP，须与证书 SAN
一致），不是监听地址。正式 CA 或私有 CA 的非自签证书命令行范例、内网
CA 生成步骤见 `deploy/README.md` §1.1；两参数留空时才是自动生成自签证书。

要点：

- 代理后面启动 exe 加 `--trust-proxy`（日志里的 IP 才是真实客户端 IP）；
- nginx 的 `/lw/ws` location 必须带 `Upgrade`/`Connection` 头（WebSocket），
  否则静默退化成长轮询；
- 集群 = 同一份 exe 多开端口 + **粘性会话**（nginx `ip_hash` /
  Caddy `lb_policy ip_hash`）：会话在进程内存里，不粘就"丢会话"；
- 健康检查统一打 `/lw/healthz`（纯内存读，返回在线会话数与运行时长）；
- 实例宕机切换后，浏览器收到 410 会自动新建会话回登录页（兜底链路已实现）。

## 专用负载均衡器 lwhyper（对标 uniGUI Hyper Server）

不想装 nginx 时，用 `tools/lwhyper.exe` 一个进程搞定集群（uniGUI Hyper Server
的对应物）：拉起 N 个 worker（同一个业务 exe 多开）、崩溃自动重启、对外单端口
反向代理、按 sid 会话粘性、WebSocket TCP 级透传、自带健康监控。

```
:: 编译（一次）
lazbuild -B --ws=nogui tools\lwhyper.lpi

:: 启动：2 个 worker（dbaware.exe 多开），对外监听 8080
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\dbaware\dbaware.exe
```

不想记参数的话用 GUI 版 `tools\lwhyper_gui.exe`（Windows 用
`tools\build_hyper_gui.bat` 编译，Linux/macOS 用 `tools/build.sh hyper_gui`）：
窗口里填业务 exe / 端口 / worker 数，点「启动」即可，面板带 worker
明细表（端口/PID/会话/重启）、实时日志和托盘常驻（点 X 隐藏，右键退出）。
GUI 版与控制台版共用 `src/core/lwhyper.pas`，代理行为完全一致。

浏览器直接打开 `http://127.0.0.1:8080/`，与直连单实例无差别。参数：

```
--port=8080          监听端口（worker 缺省 port+1 顺次）
--workers=N          worker 进程数（缺省 2）
--exe=路径           业务 exe（必填）
--base-port=N        第一个 worker 端口
--root= / --theme=   转发给 worker
--worker-args="..."  原样追加到 worker 命令行（如 --trust-proxy）
--logdir=目录        worker 日志目录（缺省 <TEMP>\lwhyper）
--ssl                外层开 HTTPS；worker 之间仍走 HTTP
--ssl-host=名        证书主机名/SAN 域名或 IP；留空用自签证书
--ssl-cert=文件      指定 PEM 证书（与 --ssl-key 成对）；给了即自动开 HTTPS
--ssl-key=文件       指定 PEM 私钥（与 --ssl-cert 成对）
--tls-cert= / --tls-key=  上面两个的别名（给了同样自动开 HTTPS）
--hot-update         热更新（缺省开）：监听新版本 exe，换壳后逐个滚动重启 worker
--no-hot-update      关热更新
--update-dir=目录    新版本投放目录（放与业务 exe 同名的文件；缺省看 <exe>.new）
--verbose            打印每个代理请求与探针
```

**热更新（零停机换版）**：编译好后把新 exe 拷成 `<业务exe>.new`（或扔进
`--update-dir`），lwhyper 会在约 4 秒落定判定后换壳，并**逐个**重启 worker
（任一时刻至少 N-1 个在服务）；新版本起不来会自动回滚并留存 `.bad-<时间>`。
停 worker 走的是优雅退出（worker 侧 `POST /lw/shutdown` + 令牌），不是强杀。
机制与用法见 `docs/WHYPER.md` §5.1（用法）/ §5.2（实现）。

自身端点：`/lw/healthz`（汇总探针）、`/lw/hyper/status`（worker 明细：
端口/pid/存活/会话数/重启次数/粘性会话数）。

工作方式与边界：

- **粘性**：sid 在每个 API 调用上（`?sid=` / `X-LW-Sid`），新会话轮询分配、
  之后查表粘住同一 worker；lwhyper 重启丢表后带未知 sid 的请求轮询转发，
  worker 回 410 → 浏览器自动重建会话（兜底链路既有）；
- **worker 崩溃**：2 秒探针周期内自动重启（`restarts` 计数可见），
  该 worker 上的会话随进程丢失（会话在进程内存里，会话外置 Redis 未做）；
- **HTTP 场景不再需要 nginx**；HTTPS 直接在 lwhyper 加 `--ssl` 即可
  （纯 FPC 自带，worker 仍明文；自签证书零配置）。前置反代也支持，
  但反代配置不再需要 `ip_hash` / worker 清单（粘性由 lwhyper 管）；
- 回归：`tests/t_hyper.py`（20 项，需先手动起 lwhyper）+
  `tests/t_hyper_ws.py`（6 项 WS 隧道，run_with_server 全自动）。

分发机制（为什么必须应用层粘性、sid 表怎么维护、探针/热身闸门/重试语义、
WebSocket 为什么 TCP 级透传、单点故障边界）见 **`docs/LOADBALANCE.md`**。

## 路线图

- ~~打印与导出~~ ✅ 已实现：`lwreport` 报表引擎（HTML 打印预览 / CSV / XLSX，
  见 `demos/dbaware` 的报表中心）。FastReport 商业库本机没有、LazReport
  与 LCL 预览窗/打印机强绑定（nogui 用不了），所以走浏览器打印引擎。
- ~~WebSocket 替代长轮询~~ ✅ 已实现（`lwwebsocket`，`tests/t_ws.py`）
- ~~服务端 PDF 直出~~ 暂以浏览器"另存为 PDF"代替（fcl-pdf 已验证可嵌入中文
  TrueType 子集，但该版本 ToUnicode/页面输出尚不稳）
- ~~会话跨页签共享~~ ✅ 已实现（localStorage 复用 sid + `/lw/api/attach` +
  游标式推送队列，见上）
- ~~集群/负载均衡~~ ✅ 双方案落地：**lwhyper 专用负载器**（见「专用负载均衡器」节，
  对标 uniGUI Hyper Server）与 nginx/Caddy 粘性会话（`deploy/nginx.conf` 的
  `ip_hash`、`/lw/healthz` 探针、`--trust-proxy`；会话外置到 Redis 未实现）
- ~~`lwconvert` 深化~~ ✅ 已完成（v2：基类改写、启动代码改写、`.lpi` 重新生成、支持度报告、`tests/t_convert.py` 端到端回归）
- ~~把 placeholder 里的高频控件补上渲染器~~ ✅ 已实现：`TRadioGroup`/`TCheckGroup`/`TCheckListBox`/`TValueListEditor`（坑 25/42/97）、`TDateEdit`/`TTimeEdit`（坑 55/70）均已 ok，见 `docs/CONTROL_MATRIX.md`
- Alpine.js 轻量客户端 ✅ 已实现：**默认渲染层** `lw-alpine.js`，无需 ext 目录；Ext JS 为可选层，需 `--client=ext` 显式启用（坑 89–97）

## 开源协议

本项目以 [MIT License](LICENSE) 协议开源：

```
MIT License

Copyright (c) 2026 szlbz(秋风) QQ:315795176
```

可自由使用、修改、分发（含商业用途），唯需保留上述版权声明。

### Ext JS（可选依赖）与授权声明

- 本项目**不随附、不打包、不分发**任何 Sencha / Ext JS 文件（`ext-all.js`、
  主题 CSS、charts 包等一律不含）。如需 Ext 渲染层，请自行从 Sencha 官方
  渠道获取 `ext-<版本>` 放入部署目录，其授权合规由使用 Ext JS 的部署者
  自行承担；
- Ext JS 由 Sencha 以 GPLv3 / 商业双授权发布，官方 GPL 版本仅到 7.0.x，
  之后的新版本走商业授权渠道 —— 使用 GPLv3 版时请遵守其开源条款
  （开放应用源码等），商业闭源分发请购买商业授权；
- Ext 渲染层脚本 `lw.js` / `lw.css` 为本项目原创代码，随本项目以 MIT 分发，
  不包含、不衍生自任何 Sencha 代码；
- 框架默认渲染层为 Alpine.js（MIT），**部署中不放置任何 ext 目录时功能
  完整可用**（启动自动探测优先 alpine，`?client=` 可按请求切换）；
- 其他第三方依赖：Lazarus/FPC 为修改版 GPL（运行时链接例外），
  请随分发目标一并向下游说明。

### Alpine.js（内置依赖）与授权声明

- `src/client/alpine.min.js`（3.14.9 官方 CDN 构建，未做任何修改）**随本项目
  分发**，是发布包中唯一内置的第三方运行时文件；
- Alpine.js 以 MIT 协议发布（Copyright (c) Caleb Porzio and Alpine.js
  contributors）。为满足 MIT 的"保留版权与许可声明"要求，分发文件头部已
  附许可声明（含官方 LICENSE 链接），请勿在再分发时移除；
- 项目自有的 `lw-alpine.js` / `lw-alpine.css` 为原创代码，以 MIT 分发
  （文件头部含 SPDX 声明）；
- Alpine 渲染层是框架默认渲染层，部署无需任何外部下载。


## English README

# lazarusWeb

Quickly convert Lazarus desktop programs into web applications that run in the browser, using the **real LCL control tree** directly serialized into the UI; **the default rendering layer is Alpine.js** (built-in dependency, zero extra deployment), Ext JS is an optional rendering layer (you need to provide the ext directory yourself and explicitly enable it with `--client=ext`). Business programs only need to change the form base class from `TForm` to `TLWForm`; all other code (events, properties, `.lfm`) stays as-is, and the program can run in the browser as a service program.

Browser (Alpine.js default / Ext JS optional) Server (Lazarus, nogui widgetset)
| Browser side (Alpine.js default, Ext JS optional) | Communication | Server side (Lazarus, nogui widgetset) |
| :--- | :---: | :--- |
| `lw-alpine.js` + `alpine.min.js` renderer/coordinator<br>(optional: `lw.js` + `ext-<version>/`)<br><br>Native DOM/CSS (optional: Ext.window/panel/grid/...)<br><br>`WS sends events / long-poll cursor receives pushes` | <br>**HTTP←→JSON**<br><br> | `lwhttp` fcl-web multithreaded server<br>`lwsession` one LCL control tree per tab<br>`lwwriter` LCL tree→JSON<br>`lwdispatch` events→RTTI calls business code<br>`lwws` nogui patch (virtual display/canvas) |

## Requirements

- FPC 3.3.1/3.2.2 + Lazarus
- Alpine.js (built-in dependency)
- Ext JS 7.0.0 (GPLv3 version, **optional**: not included in the release package; you need to obtain it from Sencha's official channels and place it in `ext-7.0.0\`; if not placed, the built-in Alpine.js rendering layer is used by default)
- **Ext support is an optional feature; ext-js files must be obtained by the user, and licensing compliance is the user's responsibility.**

## Control Installation (Lazarus IDE design-time packages)

To open forms containing lazarusWeb controls in the IDE designer, and to use the "New Project Wizard" and the "Generate lazarusWeb Form Template" Tools menu, you must process the four packages in a **fixed order**. The order cannot be reversed: `lwserver` / `lwvst` both depend on `lwcore`, and `lwdesign` (the design-time package) depends on the first three. Skipping steps will cause `Can't find unit lwcore / lwserver / lwvst` errors during Install.

| Order | Package | Type | Dependencies | What to do in the IDE |
|---|---|---|---|---|
| 1 | `src\lwcore.lpk` | RunAndDesignTime | LCL / FCL / fcl-image | **Compile only** (Compile), do not Install |
| 2 | `src\lwserver.lpk` | RunAndDesignTime | LCL / FCL / **lwcore** | **Compile only** (Compile), do not Install |
| 3 | `src\lwvst.lpk` | RunAndDesignTime | LCL / **lwcore** / lclextensions_package / laz.virtualtreeview_package | **Compile only** (Compile), do not Install |
| 4 | `src\design\lwdesign.lpk` | DesignTime | LCL / IDEIntf / **lwcore** / **lwserver** / **lwvst** | **Compile → Install** (will rebuild `lazarus.exe`, then restart the IDE) |

The purpose of the three-layer dependency—**the two build chains do not pollute each other**:

- Headless chain: `lwcore` + `lwserver`. Neither references VirtualTreeView, so `--ws=nogui` can compile, used for Linux/no-X deployment targets.
- GUI chain: `lwvst` (`TLWDBVirtualTreeView`, requires real GDI) + `lwdesign`. These two packages **can only be compiled with the target IDE's widgetset (native win32)**, do not add `--ws=nogui`: `lclextensions_package` / `laz.virtualtreeview_package` only have `include/<widgetset>` and `include/intf/<widgetset>`, no nogui version, and will report `Cannot open include file "uses.inc"`.
- For headless projects requiring multi-column/virtual node trees, use `TLWDBTreeView` in `lwcore` instead (see example `demos\treedemo_nogui`, verified to run under nogui build).

Specific steps:

1. Register the four packages from the command line first (so the IDE recognizes them; otherwise new projects report "package not found"):

   ```
   tools\install_design.bat
   ```
   Equivalent manual commands (replace `C:/111/lazarus` with your Lazarus directory):
   ```
   lazbuild --add-package-link src\lwcore.lpk
   lazbuild --add-package-link src\lwserver.lpk
   lazbuild --add-package-link src\lwvst.lpk
   lazbuild --add-package-link src\design\lwdesign.lpk
   ```
   Note that `--add-package-link` is followed by **a space + path**; writing it as
   `--add-package-link=...` will be rejected by the current lazbuild (`does not allow an
   argument`) and nothing will be registered.
   `--add-package-link` only "registers/recently opened", **it is not equal to installation**.

2. Open Lazarus, and in the order of the table above, open each package via `Package → Open Package File → <package>.lpk`.
   For the first three, click **Compile** (only compile ppu, do not Install); for the fourth `lwdesign.lpk`,
   click **Compile → Use → Install**, choose "Yes" when asked whether to rebuild the IDE, wait for the rebuild to finish,
   and **restart Lazarus**.

3. After restart, verify: `File → New → Project` shows two lazarusWeb templates,
   the component palette shows the **lazarusWeb** page, and the Tools menu shows "Generate lazarusWeb Form Template".

> After upgrading to a new framework version or modifying design-time package source, you must redo the
> Compile → Install → restart IDE step for `lwdesign.lpk` in step 2, otherwise the designer and Tools menu still run old code.
> Do not compile `lwserver.lpk` in the IDE (nogui widgetset units are not in the IDE search path,
> will report `Can't find unit noguiint`); let the command line `lazbuild` or new project handle that package.
> See `docs/NOTES.md` pitfalls 15 / 16 for the complete pitfall record.

## Cross-Platform Build Matrix (Host → Target)

All source code (`src/`, `tools/`, `demos/`) is cross-platform: platform differences in core units
(timestamp precision / critical section reentrancy / path style, etc.) are isolated with `$IFDEF MSWINDOWS/LCLGTK2/LCLQT5`
and all have non-Windows branches; no Windows-specific units are referenced; all `.lpi`/`.lpk`
paths use forward slashes and do not hardcode target CPU/OS (artifact names use `$(TargetCPU)-$(TargetOS)` variables).

**FPC version**: The same source supports both **FPC 3.2.2 and 3.3.1**. The new capabilities of 3.3.1
(`fphttpserver` `RegisterUpdateHandler` / `ThreadMode` / `ConnectionHandler`)
and `SetTextAutoFlush`, `GetHTTPStatusText`, etc., are wrapped with `{$IF FPC_FULLVERSION >= 30301}`
dual branches; under 3.2.2, equivalent shims are used (OnRequest manually takes over upgrade, `select` self-implements
`LWCanRead`, built-in status code table, 1-byte text buffer), under 3.3.1 the native path is used, with consistent behavior.

Tested cross-compilation combinations (Windows host, nogui widgetset):

| Target | Command key points | Artifact |
|---|---|---|
| x86_64-linux | `--os=linux --cpu=x86_64 --ws=nogui --compiler=...ppcrossx64.exe` | `gallery_nogui-x86_64-linux` (ELF x86-64) |
| mips64el-linux | `--os=linux --cpu=mips64el --ws=nogui --compiler=...ppcrossmips64el.exe` | `gallery_nogui-mips64el-linux` (ELF MIPS, verified on Loongson 3A) |

```
lazbuild --os=linux --cpu=mips64el --ws=nogui \
         --compiler=/c/111/fpc/bin/x86_64-win64/ppcrossmips64el.exe \
         demos/gallery/gallery.lpi
# → gallery_nogui-mips64el-linux (ELF, ~6.5MB code segment; ld's abicalls
#   mixed-link warning can be ignored)
```

On a Linux host, just run `lazbuild` on each demo's `.lpi`; `build.sh` and
`build.bat` are functionally equivalent. Directory/file names are case-sensitive on Unix; see the next section for details.

## Directory Structure

| Path | Content |
|---|---|
| `src/core/lwbase.pas` | Common types, utilities, threadvar session pointer |
| `src/core/lwws.pas` | nogui widgetset patch (**required**, see below) |
| `src/core/lwform.pas` | `TLWForm` business form base class (includes `SendFile` / `SendText`) |
| `src/core/lwwriter.pas` | LCL control tree → JSON |
| `src/core/lwsession.pas` | Sessions, form list, synchronous modal |
| `src/core/lwdispatch.pas` | Browser events → real LCL control events |
| `src/core/lwhttp.pas` | HTTP service, static resources, API routing, upload/download |
| `src/core/lwapp.pas` | Application facade (register/command line/startup) |
| `src/core/lwconfig.pas` | Server configuration file (INI: Port / Theme / ExtDir) |
| `src/core/lwfileupload.pas` | `TLWFileUpload` upload button control |
| `src/core/lwcamera.pas` | `TLWCamera` capture control (mobile invokes system camera / desktop in-page viewfinder) |
| `src/core/lwdlg.pas` | **LCL dialogs redirected to browser** (ShowMessage / MessageDlg / InputQuery / TOpenDialog …) |
| `src/core/lwupload.pas` | multipart parsing and writing to disk |
| `src/core/lwdownload.pas` | Download token table (paths not exposed in URL) |
| `src/core/lwnewproject.pas` | Project skeleton template (shared by wizard and `lwnew`) |
| `src/client/lw.js` | Browser-side rendering and incremental reconciliation |
| `src/client/lw.css` | Base styles |
| `src/lwcore.lpk` | Runtime package (does not depend on widgetset, needed by design-time package) |
| `src/lwserver.lpk` | Runtime package (server side; automatically applies widgetset patch under nogui) |
| `src/design/lwdesign.lpk` | **Design-time package**: New Project Wizard / New Form / component palette |
| `demos/hello` | Minimal example |
| `demos/grid` | Table example (load/filter/edit/status bar) |
| `demos/multi` | Comprehensive example (menu/multi-tab/toolbar/**synchronous modal**) |
| `demos/db` | **SQLite database example** (TDBGrid/TDBEdit/TDBMemo CRUD, sorting, filtering, category statistics) |
| `demos/files` | **File upload/download example** (TLWFileUpload, SendFile, SendText export CSV) |
| `demos/dbaware` | **DB-aware control full set** (TDBText/TDBListBox/TDBRadioGroup/TDBLookup*/TDBImage data-aware testing; main form has 87 objects, `uAwareMain.lfm` 866 lines) |
| `demos/dialogs` | **Dialog example** (ShowMessage/MessageDlg/InputQuery/QuestionDlg/MessageBox/OpenDialog/SaveDialog) |
| `demos/gallery` | **Full-featured gallery** (benchmarked against uniGUI full-featured Demo: 12 pages, 60+ controls — standard controls/buttons/extended input/containers/grids/toolbars/charts/HTML·PDF·upload/dialogs/timers/DB-aware/large table pagination, `tests/t_gallery.py` 50-item regression) |
| `docs/MAPPING.md` | Control/property mapping table |
| `docs/CONTROL_MATRIX.md` | **Tested support matrix for 66 visual controls** (auto-generated) |
| `docs/DB_AWARE_MATRIX.md` | **Tested matrix for 12 DB-aware controls** (binding/display/sync/write-back, auto-generated) |
| `docs/SECURITY.md` | **Security notes**: SQL injection and trust boundaries (framework has no SQL channel, demo parameterized examples, business code self-check list) |
| `docs/NOTES.md` | nogui porting pitfall record, pitfalls 1–108 accumulated over time (important; old conclusions like pitfalls 23/66 have been revised by later pitfalls, refer to annotations) |
| `docs/HOW_IT_WORKS.md` | **Working principles in detail** (for first-time code readers: the complete round trip of one click, why full RTTI dump is not possible) |
| `docs/MANUAL.md` | **User manual** (usage + development) |
| `docs/FEATURES.md` | **Features and highlights** (one page to understand strengths and boundaries: eleven capabilities / seven decisions done right / number snapshot / comparison with uniGUI) |
| `docs/INDEX.md` | Documentation navigation index (find docs by scenario) |

## Quick Start

```
cd c:\LazarusWeb
build.bat                 :: Build all demos (lazbuild -B --ws=nogui)
build.bat grid            :: Build only demos\grid (project name auto-detected, db→dbdemo, files→filedemo)
demos\multi\multi.exe --port=8090
demos\db\dbdemo.exe --port=8095      :: SQLite CRUD example (requires demos\db\sqlite3.dll)
demos\files\filedemo.exe --port=8096 :: Upload/download example
demos\dbaware\dbaware.exe --port=8110 :: DB-aware control full set
start-gui.bat           :: Double-click to start GUI version (dbaware_gui.exe, see next section)
                           Linux/macOS: ./start-gui.sh
```

Open `http://127.0.0.1:8090/` in your browser. Command-line options:

```
--config=path         Specify configuration file (default auto-finds <exe-name>.ini / lazarusWeb.ini, see next section)
--port=8090           Listening port
--root=C:\LazarusWeb  Project root directory (contains src/client; ext-<version> only needed for optional Ext layer); defaults to current directory
--form=Name           Default form name
--client=ext          Browser rendering layer: ext | alpine; auto-detected if not specified (both prefer alpine)
                      Built-in default is ext; when deployed with alpine resources it auto-switches to alpine, explicit specification takes priority
--ext=7.0.0           Default Ext version (URL can also use ?ext=<version> to temporarily switch)
--extdir=directory    ext-js directory (equivalent of ExtDir config item)
--theme=crisp         Default theme (Ext rendering layer: classic/crisp/gray/material/neptune/graphite;
                      Alpine layer colors are not here, see below)
--title=title         Browser tab title (defaults to Application.Title)
--timeout=20          Session idle timeout (minutes)
--trust-proxy         Add when behind nginx/Caddy: client IP in logs takes X-Forwarded-For
--ssl                 Enable HTTPS (built into FPC; auto-generates self-signed cert if none given)
--ssl-host=name       Certificate hostname/SAN domain or IP, not listen address
--ssl-cert=file       Specify PEM certificate (paired with --ssl-key; relative path resolved from exe directory)
                      Providing cert/key automatically enables HTTPS, no need to write --ssl
--ssl-key=file        Specify PEM private key (paired with --ssl-cert)
--tls-cert= / --tls-key=  Aliases for the above two (providing them also auto-enables HTTPS)
--ajax-cors           Allow cross-origin calls to /lw/ajax/* (for third-party page integration)
--verbose             Print each request and exception stack
--nogui               Do not show server panel even in GUI build (service deployment)
--patch=1             Incremental patch (events return only changed ops, default off; old frontend auto-falls back to full)
--log=path            Append server logs to file
--help                Help
```

The parameter table is aligned with the `--help` output of `src/core/lwapp.pas`; details (such as `--client` auto-detection) are subject to source code.

### Configuration File (INI)

If you don't want to type a long string of parameters every time, place an INI next to the exe (template at
[`lazarusWeb.ini.sample`](lazarusWeb.ini.sample)):

```ini
[lazarusWeb]
Port=8090
Theme=crisp
ExtDir=ext-7.0.0
;Patch=0
;Client=ext
```

| Item | Meaning | When empty/invalid |
|---|---|---|
| `Port` | Listening port | Uses default **8090** (warns if out of range) |
| `Theme` | Default theme (Ext rendering layer only, `?theme=` can still temporarily override); Alpine layer colors are selected in the title bar buttons, see `docs/MANUAL.md` §5.1 | Uses `crisp` |
| `ExtDir` | ext-js directory, absolute/relative paths both work | Auto-finds `<root>\ext-<version>` |
| `Patch` | Incremental patch switch, `1` = events return only changed ops | Default `0` (off) |
| `Client` | Browser rendering layer: `ext` / `alpine` (auto-detected if not written) | Auto-detect |
| `SSL` | Enable HTTPS: `1` / `true` / `yes` | Default `0` (HTTP) |
| `SSLHost` | Certificate hostname/SAN domain or IP; not listen address | Uses self-signed cert when empty |
| `SSLCert` | PEM certificate path (paired with `SSLKey`, relative path from exe directory) | Uses self-signed cert when empty |
| `SSLKey` | PEM private key path (paired with `SSLCert`) | Uses self-signed cert when empty |

Details (all decided after pitfalls):

- **Priority**: built-in defaults < configuration file < command line. `--port=9000` always wins over `Port=8090`,
  so "one exe copied ten times, each with an ini" and "temporarily change port for debugging" can coexist;
- **Where to place**: `--config=<path>` explicit; otherwise search in order
  `<exe directory>\<exe-name>.ini` → `<exe directory>\lazarusWeb.ini` →
  `<current directory>\<exe-name>.ini` → `<current directory>\lazarusWeb.ini`;
  relative path `--config=` is also allowed relative to exe directory (cwd is often System32 when started as service);
- **Format is very tolerant**: section name can be written or not (`[lazarusWeb]` / `[server]` / omitted all recognized),
  key names are case-insensitive and ignore `-`/`_` (`ext-dir` = `ExtDir`), values can be quoted,
  `;` and `#` at start are comments. Save file as UTF-8 or pure ASCII (ANSI Chinese paths will be garbled);
- **`ExtDir` is a "directory" not a "version number"**: given it, `/ext/<any version>/...` all served from this directory
  (one deployment usually carries one ext version); pointing to a non-existent or empty directory warns and auto-falls back to
  `<root>\ext-<version>`, will not prevent service from starting;
- Startup banner prints the actual configuration file path and ext directory; check these two lines first when troubleshooting.

Write your own Web program (the server side is only this much code):

```pascal
program myapp;
uses Interfaces, Forms, lwapp, uMain;
begin
  Application.Initialize;
  TLWApp.Register(TMainForm);   // Class name minus T is the form name in browser
  TLWApp.Run;                   // Automatically calls LWInstallWidgetSet
end.
```

The only line to change in the form unit:

```pascal
uses ..., lwform;
TMainForm = class(TLWForm)   // Originally class(TForm)
```

> **Important**: Compilation must include `-B` (`lazbuild` does not record `.lfm` in the dependency table,
> old `.o` will continue to be used when only changing UI without changing `.pas`).
> `build.bat` already has this added.

## Deployment (Running in Standalone Directory)

The framework **supports** copying the `ext-<version>` directory to the application's own directory for self-contained deployment. When `--root=` is not passed, the root directory is determined in the following order:

1. **Current working directory** — as long as there is an `ext-<version>` directory in that directory, it is considered
   the root. Use whichever directory it is started from, most intuitive.
2. **Up to 5 levels up from the executable directory** — find a directory where both "`ext-<version>` + `src/client/lw.js`
   exist" (fallback for double-click run or starting from elsewhere).
3. Neither found → `C://LazarusWeb`.
4. Explicit `--root=<path>` has highest priority, overriding the above three.

`/lw/lw.js`, `/lw/lw.css` (and alpine's `/lw/lw-alpine.js`, `/lw/lw-alpine.css`,
`/lw/alpine.min.js`) lookups all have multi-path fallback; the following layouts all work:

| Layout | Required files (take one set per rendering layer) |
|---|---|
| Standard repository layout (recommended) | `<root>/src/client/lw.js`, `lw.css`; or `lw-alpine.js`, `lw-alpine.css`, `alpine.min.js` |
| Flat deployment | Above files in same directory as exe |
| Semi-flat | Place above files under `<exe directory>/lw/` or `<root>/lw/` (old deployment's `<root>/client/` still compatible) |
| Fallback | Search upward from root for same-named files under `src/client/` |

Minimal self-contained deployment directory (**default Alpine.js rendering layer, no ext directory needed**):

```
MyApp/
  MyApp.exe
  src/client/alpine.min.js   44 KB   Alpine.js itself (defer loaded, not from CDN)
  src/client/lw-alpine.js    205 KB  Renderer/coordinator (adaptive for this layer only; templates shared by both layers)
  src/client/lw-alpine.css    59 KB  Styles: CSS variables for 7 color schemes (light/beige/eye-care green/high contrast/dark/dark blue/ink green) all here
  tpl/                              Optional: form templates; read by both Alpine/Ext layers, silently falls back to design-time layout when missing
  favicon.ico                       Optional: browser tab icon (can be placed in exe directory or --root directory)
  ext-<version>/                    Optional: Ext JS rendering layer (~75MB, requires explicit --client=ext switch)
  cert/                             Optional: place server.crt/server.key/ca.crt when SSL is on and using own PEM
  libssl-3-x64.dll + libcrypto-3-x64.dll  Optional: must be placed in exe directory when SSL is on
```

(When using Ext rendering layer, replace with `src/client/lw.js` + `lw.css` + `ext-<version>/`;
all three alpine files are required—missing `alpine.min.js` makes auto-detection judge alpine unavailable and
fall back to ext; missing css makes the page run but with no styles at all.)

Verify: after startup, check the `Root :` and `Client :` lines in the banner (default should be alpine), or
`curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8090/lw/lw-alpine.js` (should be 200).

### Starting Demos

```bat
start-demo.bat            :: Default 8092, double-click to run
start-demo.bat 8095       :: Specify port
```

```bash
./start-demo.sh           # Linux / macOS, default 8092
./start-demo.sh 8095
```

The service runs in the foreground; open the address shown in the browser, `Ctrl+C` or close the window to stop.
(If the port is occupied, change to another: after a process is forcibly killed, an orphan socket with `LISTENING PID 0` may remain,
visible in `netstat` but cannot be killed; changing port is easiest.)

## Cross-Platform (Linux / macOS)

Core units only use FPC/LCL general facilities: `fphttpserver`, `SysUtils`'
`DirectoryExists`/`FileExists`/`ExtractFileDir`, and `PathDelim` /
`IncludeTrailingPathDelimiter` for path concatenation — **no** `Windows`, `winsock`,
`ShellExecute` or similar platform units (`grep -rn "Windows" src/core/*.pas` only hits in
comments). `lwws.pas` degrades to empty implementation under non-nogui widgetsets, so it can also compile
under win32/gtk2/qt5/carbon (running still recommends `--ws=nogui`).

Build:

```bash
./build.sh                        # All demos
./build.sh dbaware                # Single
LAZBUILD=/opt/lazarus/lazbuild ./build.sh

tools/build.sh                    # All tools (convert/hyper/audit/dbcheck/hyper_gui/convert_gui)
tools/build.sh convert            # Single tool (fpc direct compile, no LCL)
tools/build.sh hyper_gui          # GUI tools compiled with host widgetset
```

`.lpi` does not fix `TargetOS`/`TargetCPU`, builds according to host platform; on Unix artifacts have no
`.exe` suffix (`build.sh` will delete both names). Windows uses `build.bat`,
`LAZBUILD` environment variable can also override.

Runtime dependency differences:

| Dependency | Windows | Linux | macOS |
|---|---|---|---|
| SQLite (demo use) | `sqlite3.dll` (demo directory already has) | `libsqlite3.so` (`apt install libsqlite3-0`) | System built-in |
| Alpine.js / lw-alpine.js (default); Ext JS / lw.js (optional) | Same as left | Same as left (paths concatenated by `PathDelim`) | Same as left |
| Command-line parameters | `--port=` `--root=` `--theme=` `--config=` | Same as left | Same as left |

Note that Unix filenames are case-sensitive (Windows is not); keep directory/file names like `src/client`
as-is (ext directory name can be arbitrary; server will auto-identify the unique `ext-*` directory under root).

## Creating Projects in the IDE with the Wizard (Design-Time Package `lwdesign`)

After `src/design/lwdesign.lpk` is installed, three additional things appear in Lazarus:

| Location | Content |
|---|---|
| File → New → Project | **lazarusWeb** template; after selecting, three dialogs pop up in sequence: ① application mode (normal / **service (daemon)**; service mode additionally generates `uDaemon.pas`/`uMapper.pas`/`lazarusWeb.ini`, see `docs/SERVICE_NAMING.md`); ② project type (`lazarusWeb project` GUI debug build / `lazarusWeb project(nogui)` deployment build); ③ project template (regular / plugin). Disk write timing matches Lazarus built-in templates: after selecting the three dialogs nothing is written (project is "virtual"); the "Save Project" dialog only pops up when saving (Ctrl+S). Directory defaults to the IDE option's "project build test directory". This step generates `.lpr/.lpi/umain.pas/.lfm/build.bat/build.sh/favicon.ico`, and copies the framework's `src/client` to the project directory's `lw/` (runtime finds static resources as `exe/lw/<file>`; site icon `favicon.ico` goes in project root, server finds it in order of `<root>` → `<exe directory>`). The nogui build's `.lpi` macros are only written **after the save transaction truly ends** (`.lpi` and all units on disk, two consecutive stable rounds before acting; never pop up dialogs or reload project during save, see NOTES pitfall 172), so **about 1 second after saving** they are completed, and a message "nogui build: effective after reloading project" pops up—click "Yes" to reopen the project, F9 gives a windowless console service |
| File → New → File | **lazarusWeb Form** — a `TLWForm` form unit, directly into designer |
| Component palette | **lazarusWeb** page: `TLWFileUpload` / `TLWCamera`, etc. |

Install (only once):

```
tools\install_design.bat        :: Register the three packages first
```

Then follow its prompts in the IDE: `Package → Open Package File → lwdesign.lpk → Use → Install`,
let the IDE rebuild once (design-time package is statically linked into `lazarus.exe`, must rebuild to take effect).

First time use, five steps:

1. **Install packages**: the one-line command above + `Install` to rebuild the IDE (reinstall when upgrading packages, otherwise it runs old code);
2. **New**: `File → New → Project` select template (GUI build debug / nogui build deployment), after selecting **nothing written**;
3. **Save**: `Ctrl+S` pops up standard "Save Project" dialog to write. Do not name the project `LWApp` (conflicts with `lwapp.pas`, compile reports `Duplicate identifier "LWAPP"`); default `LWApp1` is safe;
4. **nogui build extra step**: about 1 second after saving, "nogui build: effective after reloading project" pops up, click **"Yes"**;
5. **F9**.

> **Note: Pressing F9 within 1 second after saving still uses win32 widgetset** — macros have just been written into the `.lpi`
> file, IDE memory's project options have not been re-read, so it will still pop up the server panel window. Wait for the
> prompt in step 4 and click "Yes" before F9; if you don't want to reopen the project, use the
> `build.bat` in the project directory to compile.

Disk file list, UI details of each step, and troubleshooting (`%TEMP%\lazarusweb-wizard.log`) are in
`docs/MANUAL.md` "Creating Projects with the IDE Wizard (Building from Scratch)".

> TLWForm is a **real TForm descendant**, not a shadow class like uniGUI, so no design-time proxy is needed:
> TButton/TEdit dragged on are LCL's own controls; property panel, event page, alignment tools, anchors all work as usual,
> the layout seen in the form designer is the layout in the browser.

If you don't want to open the IDE, you can also directly generate project skeleton from the command line (this generates a Lazarus project, not a form template; use the IDE Tools menu above for template skeleton):

```
tools\lwnew.exe --name=DemoApp --dir=C:\work\DemoApp --units=C:\LazarusWeb\src\core
```

`--units` specifies source directory without depending on installed packages; omitting it requires the `lwserver` package to be registered.

**Compilation method**: Which widgetset LCL uses is determined by the `LCLWidgetType` macro in `.lpi`.
Demos in the repo and manually converted old projects do not have this macro; in the IDE, F9 will use the IDE's own
widgetset (win32), cannot link to LCL's nogui units, only can specify via lazbuild; the wizard-generated
nogui project already writes this macro into `.lpi`, so after reloading the project, F9 in the IDE is directly
nogui (within 1 second after saving, F9 will still be win32, see previous section). `build.bat` writes both:

```
lazbuild -B --ws=nogui <project>.lpi
```

> Note the distinction: **packages** (`lwserver.lpk`) can be compiled/installed directly in the IDE — `lwws.pas`'s
> nogui patch is wrapped with `{$IFDEF LCLnogui}`, degrading to empty implementation under non-nogui;
> but **projects without the `LCLWidgetType` macro** (demo, manually converted old projects) must
> `--ws=nogui`, see `docs/NOTES.md` pitfall 15.

## File Upload / Download

Upload uses `TLWFileUpload` (a `TButton` descendant, can be placed at design time):

```pascal
procedure TFileForm.btnUploadUpload(Sender: TObject; const AFileName: string);
begin
  // AFileName is the full path on the server, directly open with TFileStream
  lstFiles.Items.Add(ExtractFileName(AFileName));
end;
```

- Browser pops up system file dialog, XHR upload with progress, button text shows percentage in real time;

## Capture (TLWCamera)

`TLWCamera` (a dedicated descendant of `TLWFileUpload`) can be dragged onto the form:

```pascal
procedure TMainForm.camPhotoCapture(Sender: TObject; const AFileName: string);
begin
  // Photo already on server disk (%TEMP%\lw_uploads\<session>\camPhoto\xxx.jpg)
end;
```

- Mobile/tablet: Clicking the button directly invokes the **system camera** (`Facing` switches front/rear), after shooting goes through existing
  upload channel and triggers `OnCapture`; **works over LAN http**;
- Desktop: Under HTTPS or localhost, pops up **in-page viewfinder** (getUserMedia, live view +
  capture/cancel/select image), captured frame compressed to long edge 1600px, converted to JPEG, goes through same channel;
  Desktop pages over LAN http are prohibited by browser from accessing camera, automatically degrades to "Select image file";
- Preview: `PreviewImage := 'imgPhoto'` — after browser captures, immediately displays locally to specified
  TImage; photo data does not go through component tree patch; server only gets file path;
- Full description in `docs/MANUAL.md` usage section "Capture", example
  `demos/mobile_demo`, regression `tests/cdp_camera.py`.
- Server parses `multipart/form-data`, writes to
  `%TEMP%\lw_uploads\<session number>\<control name>\` (or specify with `TargetFolder`);
- Filenames are sanitized (remove path, remove `..`, remove illegal characters), multiple selection triggers `OnUpload` one by one;
- `Filter` (`'Text|*.txt;*.csv|All|*.*'`), `Multiple`, `MaxSizeKB` all participate in validation.

Download is one line in business code:

```pascal
SendFile('C:\data\report.xlsx');              // Push existing server file
SendText(csv.Text, 'list.csv', True);       // Direct download of computed text (True = with BOM, Excel recognizes Chinese)
```

The URL **will not** contain server paths: `SendFile` registers the file as a one-time token,
browser only gets `/lw/download?t=<token>`, token expires after 30 minutes or first use.

| Route | Description |
|---|---|
| `POST /lw/api/upload?sid=&id=` | `multipart/form-data`, returns new component tree |
| `GET /lw/download?t=<token>` | With `Content-Disposition` (including `filename*=UTF-8''`) |

**Complete business example**: `demos\db` attaches attachments to each product (upload → write to
`attachments\item<id>\` + write `attachments` table → download/delete),
uses separate database connection for attachment writes, does not interrupt the main record being edited — see
`demos\db\README.md` "How attachments are wired".

## Dialogs (ShowMessage / MessageDlg / TOpenDialog …)

**Not a single line of business code needs to change**. LCL's functions are redirected on the server to "pop up modal in browser",
the server thread hangs there waiting for the user to click, then continues:

```pascal
procedure TMainForm.Button1Click(Sender: TObject);
begin
  if OpenDialog1.Execute then              // Browser pops up file selection
    mmoLog.Lines.Add(OpenDialog1.FileName); // Returns server temporary path
  ShowMessage('lazarus Web test');            // Browser pops up message box
end;
```

Directly usable (no code, no replace):

| LCL entry | What you see in browser |
|---|---|
| `ShowMessage` / `ShowMessagePos` | Iconless message box + OK |
| `MessageDlg` / `MessageDlgPos` | Icon per `TMsgDlgType`: info/warning/error/question |
| `InputQuery` / `InputBox` / `PasswordBox` | With input box (`PasswordBox` is password box) |
| `QuestionDlg` | Custom button text, `ModalResult` returned as-is |
| `Application.MessageBox` / `LCLIntf.MessageBox` | `MB_YESNO` etc. flags parsed per Windows semantics |
| `TOpenDialog.Execute` | Select file (**first upload to server**), `FileName` = server path |
| `TSaveDialog.Execute` | Enter filename, `FileName` = path in session temp directory |

Things you must know:

- **File dialogs get server paths**. Browser cannot give local paths to server,
  so selected files are uploaded via `multipart` to `%TEMP%\lw_uploads\<session number>\pick\`,
  `FileName` is that path, `TFileStream` can open and read directly. Saving is the same:
  `TSaveDialog.FileName` falls in `...\<session number>\save\`, after writing file you `SendFile` to push to user for download.
- **Thread will really block**. Event request hangs until user replies (or 180-second timeout), then returns,
  consistent with desktop modal behavior; other sessions continue running, popping a second dialog in same session is rejected with a message.
- **When no browser session** (e.g., F9 debug directly in IDE, or running unit tests from command line) automatically falls back to LCL original implementation.
- These are **runtime replacements**, `lwdlg.pas` is in `lwcore` package, effective when business project `uses lwapp`
  (`LWInstallDialogs` installed before `TLWApp.Run`, hooks `InterfaceBase`'s
  `PromptDialogFunction` / `InputDialogFunction` / `QuestionDialogFunction` /
  `Forms.MessageBoxFunction` and `RegisterWSComponent(TOpenDialog, …)`).

**Complete example and HTTP-level tests**: `demos\dialogs` (7 buttons each demonstrate one),
`tests\t_dialog.py` (36 items, including "push → reply → wake → return value" full chain).

## Runtime Behavior (Correspondence with uniGUI)

| uniGUI | lazarusWeb |
|---|---|
| TUniSession | TLWSession (one per browser tab) |
| Component → JS mapping | lwwriter + lw.js incremental reconciliation |
| Synchronous modal (nested message loop) | `ShowModal` pushes instruction then suspends request thread, `TEvent.WaitFor` waits for browser close |
| Ajax event | `POST /lw/api/event`, value first written back to control then RTTI triggers event |

Business code is completely unaware of the Web:

```pascal
procedure TMainForm.miAboutClick(Sender: TObject);
var f: TAboutForm;
begin
  f := TAboutForm.Create(nil);
  try
    if f.ShowModal = mrOk then          // Under Web this line waits for user to click OK
      lblState.Caption := 'Viewed About';
  finally
    f.Free;
  end;
end;
```

## HTTP API

| Route | Description |
|---|---|
| `GET /` | UI shell (`?ext=7.0.0&form=MainForm` can override defaults; `?fresh=1` forces new session) |
| `POST /lw/api/session` | Create session `{form:"MainForm"}` → returns tree + `sid` + `seq` |
| `GET /lw/api/attach?sid=` | **Cross-tab sharing**: attach this tab to existing session (returns 410 + `gone` if not exists) |
| `GET /lw/api/tree?sid=` | Current component tree |
| `POST /lw/api/event` | `{sid,id,ev,val,row,col,vals,tab}` → new component tree |
| `GET /lw/api/poll?sid=&t=&after=` | Long polling. With `after` fetches pushes by cursor (each tab fetches its own); without is old destroy-style queue. **The only push channel** |
| `GET /lw/ws?sid=` | WebSocket upgrade (RFC6455): **only carries event requests/responses** (events go through WS frames when WS connected); pushes do not go through WS, always delivered by long-poll cursor above, auto-falls back to HTTP on disconnect |
| `GET /lw/api/log?sid=` | Session log (Show/ShowModal/EndModal all recorded) |
| `POST /lw/api/close` | End session |
| `POST /lw/api/dlg` / `POST /lw/api/dlgfile` | Browser modal (ShowMessage/MessageDlg/InputQuery/TOpenDialog…) reply endpoints (see `docs/MAPPING.md` dialog section) |
| `POST /lw/api/upload?sid=&id=` | File upload (`multipart/form-data`, any field name, multiple files allowed) |
| `GET /lw/download?t=` | Download (`t` is one-time token registered by `lwdownload`, discarded after use) |
| `GET /lw/ajax/<name>` | **Custom AJAX endpoint**: registered by `TLWApp.AddAjax(name, handler)`, third-party JS can fetch directly |
| `GET /lw/healthz` | Health check (LB/k8s probe): `{"ok":true,"sessions":..,"uptime":..}` |
| `GET /ext/<version>/<path>` | Ext JS static resources (two versions coexist) |
| `GET /favicon.ico` | Site icon: `--root` directory → exe directory → 204 if neither; 200 + `Cache-Control: public, max-age=86400` on hit. Both shell HTML heads have `<link rel="icon">` |

## Control Support (Tested)

`docs/CONTROL_MATRIX.md` is auto-generated by `tools\lwaudit` (snapshot: 2026-11-09,
fixes after that date see `docs/NOTES.md` pitfalls 97/107): 66 commonly used LCL
visual controls are **really created + attached to form + serialized once** under nogui, then cross-checked against `lw.js`
to see if there is a real rendering branch, divided into five categories:

| Status | Meaning | Current count |
|---|---|---:|
| ok | Browser renders as real control, bidirectional events work | 49 (74.2%) |
| placeholder | Server side usable, browser draws a box with class name | 14 |
| kind-only | kind mapped but missing rendering branch | 1 |
| create-failed | Throws exception on construction under nogui (e.g., native `TDBNavigator` depends on button glyphs, use `TLWDBNavigator` instead, see pitfalls 29/41) | 1 |
| render-failed | Construction succeeds but serialization/rendering crashes (e.g., `TDateEdit` NullDate, pitfall 107 already has fallback) | 1 |

Latest classification is subject to `docs/CONTROL_MATRIX.md`; this table is overview only.

There are also 16 non-visual components (`TTimer`/`TOpenDialog`/`TDataSource`/`TMainMenu`…)
directly usable on server side, not participating in rendering statistics.

## Mobile (Phone / Narrow Window)

Alpine rendering layer has built-in mobile adaptation, **zero business code changes**: viewport ≤834px automatically enters
mobile layout (≥1100px exits, hysteresis in between prevents jitter), phones/tablets/desktop narrow windows all auto-adapt:

- **No template**: Form renders at design size (font not shrunk), parts beyond screen scroll
  to pan and view—usable, but not a small-screen optimized layout;
- **With template**: Write an HTML template for the form (`{%control-name%}` placeholder references control Name,
  browser moves existing control DOM into template for flow layout), events and incremental patches as usual, automatically switches
  between breakpoints without losing state; change template and refresh takes effect, no recompile needed:
  - Mobile `<root>\tpl\<form-name>.m.html` — phone single-column layout, form fills viewport;
  - Desktop `<root>\tpl\<form-name>.html` — custom desktop layout (centered card,
    two columns, etc.), **form position and size stay at design time**, only client area content becomes flow;
- Manual switch: URL `?layout=mobile|desktop` or `LW.layout.set()`;
- **One-click template skeleton generation**: After installing design-time package `lwdesign`, the IDE **Tools menu**
  has an extra item "Generate lazarusWeb Form Template (Current Unit LFM)"—generates **desktop + mobile** two
  template skeletons to `<project directory>\tpl\` from the currently open form's .lfm (including
  `{%control-name%}` placeholders, basic CSS with per-control fixed height from design time, main area filling form
  stretches by **container** height `calc(100% - other controls)` (desktop accumulates by row, mobile single column adds directly;
  not `100vh` — client area is smaller than viewport when form is opened in a floating window), asks individually before overwriting existing),
  generates self-check report (skipped non-visual controls, duplicate/illegal placeholder names, nested containers, main area
  changes); after generation copy to runtime root (or directly effective when project directory is runtime root), refresh to see;
  see `MANUAL.md` 16.0; ready-made example `demos\mobile_demo\tpl\` (manually adjusted proportions),
  generator itself uses `demos\gallery` and `demos\dbaware` real forms for parsing and size
  regression (the latter covers main form in floating window, login page without main area, top toolbar row + PDF main area);
- **Capture upload**: `TLWCamera` control (drag from component palette to use)—mobile clicking button invokes
  system camera, auto-uploads to server after shooting (`OnCapture`), browser local instant preview;
  LAN http works (no HTTPS needed), see README "Capture (TLWCamera)" section;
- Usage see `docs/MANUAL.md` usage section "Mobile", template development guide see
  `MANUAL.md` Part Two "16. Form Template Development Guide (Desktop + Mobile)", mechanism and
  testing see `docs/MOBILE.md` §8, runnable example `demos/mobile_demo`
  (same form configured with desktop + mobile templates).

## Known Limitations

- Single-form applications default to one thread per session request on a port; other requests in that session during modal are queued on event queue (consistent with desktop modal semantics);
- Modal timeout `LW_MODAL_TIMEOUT_MS = 180000` (3 minutes);
- Only one dialog at a time: nesting a second dialog in same session is ignored (browser cannot overlay two modals);
- `TOpenDialog` does not read server directory list — browser selection box can only "upload file", cannot browse server disk;
  to select files on server, build your own UI with `TListView`/`TShellListView` etc.;
- Unadapted controls show gray box placeholder in browser (server side alive as usual), does not affect other controls;
  specific list see `docs/CONTROL_MATRIX.md`;
- `TSplitter` only draws divider, **does not support dragging**; `TProgressBar` / `TTrackBar` /
  `TUpDown` browser-side adjustments write back to server (`TUpDown` up/down arrows also link
  Associate edit box, see `docs/NOTES.md` pitfall 152);
- High DPI only processed as virtual display 96 DPI (`lwws.pas` constant can be changed);
  Forms designed on Windows at 125%/150% scaling (lfm `DesignTimePPI=120/144`)
  are automatically scaled back to 96 DPI on creation (geometry + font together, driven by `Application.Scaled`,
  see `docs/NOTES.md` pitfall 18).

## Database Applications (TDBGrid / TDBEdit + SQLite)

`demos/db` is a complete CRUD example, `demos/dbaware` is **DB-aware control full set**
(12 data-aware controls laid out on one page, support see `docs/DB_AWARE_MATRIX.md`).
DB controls bind directly to `TDataSource`, behavior in browser is consistent with desktop programs: click row to locate,
edit field, Post / Cancel / Delete / Locate.

| DB control | Support |
|---|---|
| TDBGrid / TDBEdit / TDBMemo / TDBComboBox | Complete (browse + write-back) |
| TDBCheckBox | Complete (binding 0/1 field must set `ValueChecked`/`ValueUnchecked`) |
| TDBListBox / TDBRadioGroup / TDBLookupComboBox / TDBLookupListBox | Complete (return selected item/key value and write back to field) |
| TDBText / TDBImage | Read-only (text / PNG image follows field in real time) |
| TDBNavigator | Complete. lfm must write real class name `TLWDBNavigator` and `RegisterClass(TLWDBNavigator)`—`RegisterClassAlias` cannot replace already registered `TDBNavigator` (pitfalls 29/41 have overturned old scheme); code side can also use `LWNewNavigator` factory |

Three hard rules (see `docs/NOTES.md` for details):

1. **SQLite string columns always use `VARCHAR(n)`** — `sqlite3conn` maps `TEXT`/`CHAR`
   to `ftMemo`, DBGrid only displays `(MEMO)`;
2. **`sqoAutoApplyUpdates` only sends SQL, does not commit transaction** — clicking "Save" in browser looks
   successful, but actually hangs in uncommitted transaction: all rolls back when program exits, another session writing gets
   `database is locked`. After Post/Delete must explicitly `SQLTransaction.Commit`;
   add `Params.Add('journal_mode=WAL')` + `PRAGMA busy_timeout=10000` to connection,
   `CommitRetaining` before writing to discard old read snapshot (WAL's `SQLITE_BUSY_SNAPSHOT`
   is not governed by busy_timeout). Complete method see `docs/NOTES.md` pitfall 9.2;
3. **Framework does not send grid rows while dataset is in edit state** (moving cursor triggers auto Post),
   browser uses last data, auto-refreshes after save/cancel.

## Reports (Print / Export)

`src/core/lwreport.pas` is the server-side report engine: one report definition (title + columns + summary +
paper), shared by three outlets:

| Outlet | Description |
|---|---|
| Printable HTML | A4 `@page`, `@media print`, `thead` repeated per page, zebra stripes, total row; preview page has built-in "Print / Save as PDF" buttons |
| CSV | UTF-8 BOM + CRLF, Excel / WPS double-click no garbled |
| XLSX | Real OOXML (`zipper` packaging, no third-party library dependency): header style, freeze panes, column width, total row |

`demos/dbaware`'s "Report Center" form is a complete example: data source switching, preview (iframe +
view token), click "Print…" with `#print` auto-pops print dialog, guest account disables export.

```pascal
rpt := TLWReport.Create(nil);
rpt.DataSet := FQry;
rpt.Title := 'Inventory Large Table Details';
rpt.Columns.AddCol('Code', 'code', 30);
rpt.Columns.AddCol('Amount', 'amount', 34, taRightJustify, rsSum);
rpt.SaveHTML(fn);   // Or SaveCSV / SaveXLSX
```

## Custom AJAX Endpoints (Third-Party JS Integration Escape Hatch)

When you want to embed your own JS / third-party component library in the page and bypass the component tree protocol to get data directly, use
`TLWApp.AddAjax` to register an endpoint with any name (name case-insensitive, `/` allowed):

```pascal
TLWApp.AddAjax('items/price',
  function (Ctx: TLWAjaxContext): Boolean
  begin
    Ctx.Json('{"price":299.00}');    // Or Ctx.Text(...) / Ctx.Error(...)
    Result := True;
  end);
```

Browser side directly `fetch('/lw/ajax/items?limit=3')`, cross-page integration add
`--ajax-cors` startup parameter. Context object provides `Param()/Header()/JSONBody()/
FormField()` and `Session` (`?sid=` or `X-LW-Sid` header, can read session-level data).
Complete example: `demos/dbaware/uAjax.pas` (items / items/price / whoami / echo four endpoints,
main form "Charts/Other" tab has a native HTML frame that directly fetches them).
Unregistered names return 404 and list all available endpoints for introspection.

## Cross-Tab Session Sharing

The second tab in the same browser no longer "starts a new session and logs in again": sid is stored in
`localStorage`, new tab first `GET /lw/api/attach?sid=…` to attach to existing session
— login identity, opened forms, server data all there, directly see main form.

- Pushes (modal / message box / mask / download instructions…) uniformly enter session queue with sequence numbers, each tab uses
  `/lw/api/poll?after=N` to fetch its own, mutually non-consuming;
- Dialog instructions carry `to=<tab identifier>`, only the tab that initiated the event pops up, other tabs do not re-pop;
- Any tab's operation (open form / close form / mask) syncs to other tabs in real time;
- When session expires / service restarts returns 410, browser automatically discards old sid, creates new session, returns to login page;
- `?fresh=1` forces new session (for multiple people sharing one browser, debugging).

Regression: `tests/t_multitab.py` (22 items) + `tests/cdp_multitab.py` (CDP dual real tabs 6 items).

## GUI Server Panel

Each demo has two builds (using dbaware as example):

| Build method | Artifact | Form |
|---|---|---|
| `dbaware.lpi` (default, `--ws=nogui`) | `dbaware.exe` | Console subsystem: large black terminal prints logs in real time, for tests/CI |
| `dbaware_gui.lpi` (win32 + `-WG`) | `dbaware_gui.exe` | **GUI subsystem**: double-click to run, only a small panel window |

GUI version starts with a server panel (benchmarked against uniGUI standalone server's window):

- Title `lazarusWeb 0.9.6 Standalone Server - Port <N>`;
- Menu "File": Open browser (F5) / Copy access address / Exit;
- Menu "Manage": Clear log / Toggle verbose log (verbose) / About;
- Middle is scrolling log area (startup banner + session creation + request logs, limited to 4000 lines);
- Status bar three cells: Listen address / Online session count (refreshed per second) / Uptime;
- **System tray**: persistent tray icon (blue background "LW"), clicking X only hides to tray (first time pops
  balloon reminder), left-click icon restores panel, right-click menu: Open panel / Open browser / Exit;
- **Only menu "Exit" truly stops the service** (graceful stop ~0.3s: wakes suspended long polling,
  disconnects keep-alive connections, accept loop exits within 250ms, see NOTES pitfall 44).

Command-line parameters take effect for both builds: `--nogui` (GUI build falls back to windowless mode,
for service deployment), `--log=path` (log to disk). Logs uniformly go through `lwrlog` unit:
console build writes to console, GUI build writes to panel, both can also write to file simultaneously.

To make your own program a GUI version, just copy `demos/dbaware/dbaware_gui.lpi`:
The only difference from a normal `.lpi` is the `LCLWidgetType=win32` macro +
`-WG` compile option + target name with `_gui` suffix. Note that `.lpr` should not write
`{$APPTYPE CONSOLE}` (it overrides command-line `-WG`).

## Deployment (HTTPS / Reverse Proxy / Cluster)

There are two paths for HTTPS, both zero code changes:

1. **Use FPC's built-in TLS directly (recommended, no proxy needed)**: Add `--ssl` to business exe or
   `lwhyper`, same port changes from HTTP to HTTPS; auto-generates
   self-signed cert if none given. Requires bundling `libssl-3-x64.dll` + `libcrypto-3-x64.dll`.
   For cluster scenarios enable at lwhyper outer layer, workers still use plaintext between them.
2. **Front reverse proxy**: nginx / Caddy terminates TLS, exe stays HTTP. Complete guide and
   ready-made configuration see **`deploy/README.md`**, [`deploy/nginx.conf`](deploy/nginx.conf),
   [`deploy/Caddyfile`](deploy/Caddyfile).

`--ssl-host` is filled with **certificate hostname** (domain/IP in browser address, must match certificate SAN),
not listen address. For non-self-signed certificates from formal CA or private CA, command-line examples and intranet
CA generation steps see `deploy/README.md` §1.1; only when both parameters are empty is self-signed cert auto-generated.

Key points:

- Add `--trust-proxy` when starting exe behind proxy (IP in logs is then real client IP);
- nginx's `/lw/ws` location must have `Upgrade`/`Connection` headers (WebSocket),
  otherwise silently degrades to long polling;
- Cluster = same exe multiple ports + **sticky sessions** (nginx `ip_hash` /
  Caddy `lb_policy ip_hash`): sessions in process memory, not sticky means "lost session";
- Health check uniformly hits `/lw/healthz` (pure memory read, returns online session count and uptime);
- After instance downtime failover, browser receives 410 and auto-creates new session returning to login page (fallback chain already implemented).

## Dedicated Load Balancer lwhyper (Benchmarked Against uniGUI Hyper Server)

When you don't want to install nginx, use `tools/lwhyper.exe` one process to handle the cluster (counterpart of uniGUI Hyper Server):
starts N workers (same business exe multiple instances), auto-restarts on crash, external single port
reverse proxy, session stickiness by sid, WebSocket TCP-level passthrough, built-in health monitoring.

```
:: Compile (once)
lazbuild -B --ws=nogui tools\lwhyper.lpi

:: Start: 2 workers (dbaware.exe multiple instances), external listen 8080
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\dbaware\dbaware.exe
```

If you don't want to remember parameters, use GUI version `tools\lwhyper_gui.exe` (Windows uses
`tools\build_hyper_gui.bat` to compile, Linux/macOS uses `tools/build.sh hyper_gui`):
fill in business exe / port / worker count in the window, click "Start", panel has worker
detail table (port/PID/sessions/restarts), real-time logs and persistent tray (click X to hide, right-click to exit).
GUI version and console version share `src/core/lwhyper.pas`, proxy behavior is completely identical.

Browser directly opens `http://127.0.0.1:8080/`, no difference from direct single instance. Parameters:

```
--port=8080          Listen port (worker default port+1 sequential)
--workers=N          Number of worker processes (default 2)
--exe=path           Business exe (required)
--base-port=N        First worker port
--root= / --theme=   Forwarded to worker
--worker-args="..."  Appended verbatim to worker command line (e.g., --trust-proxy)
--logdir=directory   Worker log directory (default <TEMP>\lwhyper)
--ssl                Outer layer HTTPS; workers still use HTTP
--ssl-host=name      Certificate hostname/SAN domain or IP; use self-signed cert when empty
--ssl-cert=file      Specify PEM certificate (paired with --ssl-key); providing it auto-enables HTTPS
--ssl-key=file       Specify PEM private key (paired with --ssl-cert)
--tls-cert= / --tls-key=  Aliases for above two (providing them also auto-enables HTTPS)
--hot-update         Hot update (default on): monitor new version exe, roll restart workers after shell swap
--no-hot-update      Turn off hot update
--update-dir=directory  New version drop directory (place file same name as business exe; default sees <exe>.new)
--verbose            Print each proxy request and probe
```

**Hot update (zero-downtime version swap)**: After compiling, copy new exe as `<business-exe>.new` (or throw into
`--update-dir`), lwhyper decides after about 4 seconds and swaps shell, and **one by one** restarts workers
(at least N-1 serving at any moment); if new version fails to start, auto-rolls back and keeps `.bad-<time>`.
Stopping workers uses graceful exit (worker side `POST /lw/shutdown` + token), not forced kill.
Mechanism and usage see `docs/WHYPER.md` §5.1 (usage) / §5.2 (implementation).

Own endpoints: `/lw/healthz` (aggregate probe), `/lw/hyper/status` (worker details:
port/pid/alive/session count/restart count/sticky session count).

How it works and boundaries:

- **Sticky**: sid on each API call (`?sid=` / `X-LW-Sid`), new sessions round-robin assigned,
  then lookup table sticks to same worker; after lwhyper restart loses table, requests with unknown sid round-robin forwarded,
  worker returns 410 → browser auto-rebuilds session (fallback chain existing);
- **Worker crash**: auto-restart within 2-second probe cycle (`restarts` count visible),
  sessions on that worker lost with process (sessions in process memory, session externalization to Redis not done);
- **HTTP scenarios no longer need nginx**; HTTPS directly add `--ssl` to lwhyper
  (pure FPC built-in, workers still plaintext; self-signed cert zero config). Front reverse proxy also supported,
  but reverse proxy config no longer needs `ip_hash` / worker list (stickiness managed by lwhyper);
- Regression: `tests/t_hyper.py` (20 items, requires manually starting lwhyper) +
  `tests/t_hyper_ws.py` (6 items WS tunnel, run_with_server fully automatic).

Distribution mechanism (why application-layer stickiness is required, how sid table is maintained, probe/warmup gate/retry semantics,
why WebSocket TCP-level passthrough, single point of failure boundaries) see **`docs/LOADBALANCE.md`**.

## Roadmap

- ~~Print and export~~ ✅ Implemented: `lwreport` report engine (HTML print preview / CSV / XLSX,
  see `demos/dbaware` report center). FastReport commercial library not available locally, LazReport
  strongly bound to LCL preview window/printer (unusable under nogui), so browser print engine is used.
- ~~WebSocket replacing long polling~~ ✅ Implemented (`lwwebsocket`, `tests/t_ws.py`)
- ~~Server-side PDF direct output~~ Temporarily replaced by browser "Save as PDF" (fcl-pdf verified to embed Chinese
  TrueType subset, but that version's ToUnicode/page output is not yet stable)
- ~~Cross-tab session sharing~~ ✅ Implemented (localStorage reuse sid + `/lw/api/attach` +
  cursor push queue, see above)
- ~~Cluster/load balancing~~ ✅ Dual solutions landed: **lwhyper dedicated load balancer** (see "Dedicated Load Balancer" section,
  benchmarked against uniGUI Hyper Server) and nginx/Caddy sticky sessions (`deploy/nginx.conf`'s
  `ip_hash`, `/lw/healthz` probe, `--trust-proxy`; session externalization to Redis not implemented)
- ~~`lwconvert` deepening~~ ✅ Completed (v2: base class rewrite, startup code rewrite, `.lpi` regeneration, support report, `tests/t_convert.py` end-to-end regression)
- ~~Add renderers for high-frequency controls in placeholder~~ ✅ Implemented: `TRadioGroup`/`TCheckGroup`/`TCheckListBox`/`TValueListEditor` (pitfalls 25/42/97), `TDateEdit`/`TTimeEdit` (pitfalls 55/70) all ok, see `docs/CONTROL_MATRIX.md`
- Alpine.js lightweight client ✅ Implemented: **default rendering layer** `lw-alpine.js`, no ext directory needed; Ext JS is optional layer, requires explicit `--client=ext` (pitfalls 89–97)

## Open Source License

This project is open sourced under the [MIT License](LICENSE):

```
MIT License

Copyright (c) 2026 szlbz(QiuFeng) QQ:315795176
```

Free to use, modify, distribute (including commercial use), only need to retain the above copyright notice.

### Ext JS (Optional Dependency) and Licensing Statement

- This project **does not bundle, package, or distribute** any Sencha / Ext JS files (`ext-all.js`,
  theme CSS, charts packages, etc. are all excluded). If you need the Ext rendering layer, obtain `ext-<version>` from Sencha official
  channels and place it in the deployment directory; licensing compliance is borne by the deployer using Ext JS;
- Ext JS is released by Sencha under GPLv3 / commercial dual license, official GPL version only up to 7.0.x,
  later versions go through commercial licensing channels — when using GPLv3 version please comply with its open source terms
  (open application source code, etc.), for commercial closed-source distribution please purchase commercial license;
- Ext rendering layer scripts `lw.js` / `lw.css` are original code of this project, distributed with this project under MIT,
  do not contain, do not derive from any Sencha code;
- Framework default rendering layer is Alpine.js (MIT), **fully functional when no ext directory is placed in deployment**
  (startup auto-detection prefers alpine, `?client=` can switch per request);
- Other third-party dependencies: Lazarus/FPC is modified GPL (runtime linking exception),
  please explain to downstream along with distribution target.

### Alpine.js (Built-in Dependency) and Licensing Statement

- `src/client/alpine.min.js` (3.14.9 official CDN build, no modifications) **distributed with this project**,
  is the only built-in third-party runtime file in the release package;
- Alpine.js is released under MIT (Copyright (c) Caleb Porzio and Alpine.js
  contributors). To satisfy MIT's "retain copyright and license notice" requirement, the distributed file header
  has attached license notice (including official LICENSE link), do not remove when redistributing;
- Project's own `lw-alpine.js` / `lw-alpine.css` are original code, distributed under MIT
  (file header contains SPDX notice);
- Alpine rendering layer is the framework's default rendering layer, deployment requires no external download.


<img width="1836" height="1271" alt="QQ_2026-11-12_17-10-34" src="https://github.com/user-attachments/assets/5b863786-318e-496f-85d9-c603eb295d5a" />
<img width="1845" height="1269" alt="QQ_2026-11-12_17-11-14" src="https://github.com/user-attachments/assets/2f6bb2ff-cae0-4177-b82e-1032c1663d2c" />
<img width="1821" height="1179" alt="QQ_2026-11-12_17-11-33" src="https://github.com/user-attachments/assets/6cf0fb0d-6586-470a-94ca-04641d33620e" />
<img width="1815" height="1170" alt="QQ_2026-11-12_17-11-48" src="https://github.com/user-attachments/assets/305a37e0-0fae-4fb5-b123-fa741f96c0b5" />
<img width="1815" height="1179" alt="QQ_2026-11-12_17-12-04" src="https://github.com/user-attachments/assets/c3ccde1f-ddb7-4089-8073-978f3d0dacaa" />
<img width="1815" height="1184" alt="QQ_2026-11-12_17-12-21" src="https://github.com/user-attachments/assets/5748a74a-e25f-4aed-b3d5-fc23327430b8" />
<img width="1815" height="1173" alt="QQ_2026-11-12_17-12-38" src="https://github.com/user-attachments/assets/54d084f1-e637-4b60-a2ed-7b5f97cccd4f" />
<img width="1809" height="1177" alt="QQ_2026-11-12_17-13-01" src="https://github.com/user-attachments/assets/7fbe0270-3a95-424a-8c35-24fc87f50a05" />
<img width="1815" height="1179" alt="QQ_2026-11-12_17-17-44" src="https://github.com/user-attachments/assets/92e18df9-9ca7-4565-9b78-1e73260f254c" />
<img width="1817" height="1179" alt="QQ_2026-11-12_17-18-11" src="https://github.com/user-attachments/assets/8b8df772-352e-43ad-97e9-f559cfc02b66" />
<img width="1824" height="1173" alt="QQ_2026-11-13_09-15-53" src="https://github.com/user-attachments/assets/90ca9690-cba7-48da-bb30-1cefebaad4d1" />
<img width="1770" height="1118" alt="QQ_2026-11-14_05-46-50" src="https://github.com/user-attachments/assets/c9a81e47-b5a5-45a1-93a2-fd6443108711" />
<img width="895" height="995" alt="ea06f9d6c6f516fa2af43e02e73d267a" src="https://github.com/user-attachments/assets/12276ce3-5c55-403a-b342-b9f2a4831cb3" />
<img width="1280" height="2769" alt="b2340579cb8b66a2d08744b6e7cefff9_720" src="https://github.com/user-attachments/assets/1892599a-91e8-4b40-9a4f-b6214b52cf4a" />
<img width="1083" height="747" alt="c324b8f680f555105b954aeeaf104029" src="https://github.com/user-attachments/assets/008d8db0-8bbd-42a0-b576-6184f0c57960" />
<img width="1284" height="2778" alt="1165bfa448560c9dc2f3cb7e7429f91a" src="https://github.com/user-attachments/assets/52012cd3-bf35-4eb2-b352-cbc791dbb383" />
