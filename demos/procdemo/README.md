# procdemo — 进程级插件演示（插件 = 独立 exe）

主框架（宿主）**不链接任何插件单元**；每个插件是**独立的 lazarusWeb 服务
exe**，自己监听自己的端口。宿主通过框架内置的 `lwroute` 把
`/p/<插件名>/...` 反向代理到对应进程。

本 demo **自带全部插件模块源码**（`modules/`），不再从项目根的 `plugins/`
目录借用 —— 复制出来的是独立的一份，改这里不会影响编译期形态的
`plugindemo`，反之亦然。

```
demos/procdemo/
  modules/                 三个插件模块源码（procdemo 独占）
    umod_dashboard.pas     仪表盘（纯代码建窗）
    umod_notes.pas         便签（配 umod_notes.lfm）
    umod_notes.lfm
    umod_reports.pas       报表汇总（纯代码建窗）
  host/      宿主：导航页 + lwroute       8860
  notesplug/ 插件 1                      8871
  dashplug/  插件 2                      8872
  reportsplug/ 插件 3                    8873
```

| 进程 | 目录 | 端口 | 说明 |
|---|---|---|---|
| `hostdemo.exe` | `host/` | 8860 | 宿主：导航页 + lwroute 路由 |
| `notesplug.exe` | `notesplug/` | 8871 | 便签插件（umod_notes + .lfm） |
| `dashplug.exe` | `dashplug/` | 8872 | 仪表盘插件（umod_dashboard） |
| `reportsplug.exe` | `reportsplug/` | 8873 | 报表插件（umod_reports） |

## 运行

```bat
build.bat
rem 或者分别：
lazbuild demos\procdemo\notesplug\notesplug.lpi
lazbuild demos\procdemo\dashplug\dashplug.lpi
lazbuild demos\procdemo\reportsplug\reportsplug.lpi
lazbuild demos\procdemo\host\hostdemo.lpi

demos\procdemo\notesplug\notesplug.exe
demos\procdemo\dashplug\dashplug.exe
demos\procdemo\reportsplug\reportsplug.exe
demos\procdemo\host\hostdemo.exe
```

浏览器打开 <http://127.0.0.1:8860/>：宿主导航页三个按钮在**本标签**打开插件页面
（`location.href='/p/<名>/'`，按浏览器「后退」回宿主）；也可以直接访问
<http://127.0.0.1:8860/p/notes/>、`/p/dash/`、`/p/reports/`，或者直连插件进程
本身的端口（<http://127.0.0.1:8871/>）。

**三个插件页的导航完全对称**：每个页面都带「另两个插件」+「返回首页」，
所以任意两页之间都能直达，也都能回宿主首页：

| 页面 | 业务按钮 | 导航按钮 |
|---|---|---|
| `/p/dash/` | 刷新指标 | 打开便签页 · 打开报表页 · 返回首页 |
| `/p/notes/` | 保存 · 清空 | 返回仪表盘 · 打开报表页 · 返回首页 |
| `/p/reports/` | 重新汇总 | 打开仪表盘 · 打开便签页 · 返回首页 |

全部是 `TLWApp.OpenForm('注册名')` + 本标签整页跳转，**模块源码与编译期 demo
完全相同**。独立 exe 下每个进程只有自己的窗体（reports 进程里没有 Dashboard
也没有 Notes，也没有宿主），靠各插件 ini 的 `page.<注册名>=<URL>` 映射让
`OpenForm` 回退成推 JS 跳转；**返回首页就是把 `Host` 映射到宿主根路径 `/`**：

```ini
; dashplug.ini
page.Notes=/p/notes/
page.Reports=/p/reports/
page.Host=/
; notesplug.ini
page.Dashboard=/p/dash/
page.Reports=/p/reports/
page.Host=/
; reportsplug.ini
page.Dashboard=/p/dash/
page.Notes=/p/notes/
page.Host=/
```

编译期 demo（plugindemo）不配这些项，`OpenForm` 走进程内切页，行为不变。

回归：`python tests/t_route.py`（需四个进程都在跑，含 9 条跨插件/回首页导航
与三个 AJAX 断言）。

## 插件 exe 是怎么写的

插件 exe 就是一个普通的 lazarusWeb 应用，只是**只注册自己的模块**：

```pascal
program notesplug;
uses Interfaces, Forms, lwapp, umod_notes;
begin
  Application.Initialize;
  RegisterModule;      { umod_notes 的模块契约，与 plugindemo 完全相同 }
  TLWApp.Run;
end.
```

模块单元本身（`procdemo/modules/umod_notes.pas`）**一行不改**就能在两种形态下
复用：编译期链入宿主（plugindemo 形态），或者装进独立 exe（本形态）。两边各
自持有一份副本（项目根的 `plugins/` 归 plugindemo，本目录的 `modules/` 归
procdemo），互不牵连。

三个插件的模块契约完全一样，只有业务不同：

| 模块 | 窗体注册名 | AJAX 端点 | 界面 |
|---|---|---|---|
| `umod_dashboard` | `Dashboard` | `dashboard_stats` | 纯代码建窗 |
| `umod_notes` | `Notes` | `notes_export` | `.lfm` 拖控件 |
| `umod_reports` | `Reports` | `reports_summary` | 纯代码建窗 |

## 宿主怎么登记插件

宿主 ini（`host/hostdemo.ini`）：

```ini
plugin.notes=127.0.0.1:8871
plugin.dash=127.0.0.1:8872
plugin.reports=127.0.0.1:8873
```

规则：`plugin.<名>=<host:port>`（也接受完整 `http://URL`）。
宿主页面的按钮用 `TLWForm.RunJS('location.href=''/p/reports/''')` 在同标签打开插件页
（若改 `window.open('', '_blank')` 就是新页签，插件端无需改动）。

## 工作原理

1. 浏览器请求宿主 `/p/notes/...`；
2. `lwroute` 剥掉 `/p/notes` 前缀，加 `X-Forwarded-For` /
   `X-Forwarded-Prefix: /p/notes/` 头，转发到 `127.0.0.1:8871`；
3. 插件的外壳 HTML 读 `X-Forwarded-Prefix`，把 `/lw/...` 资源 URL 生成在
   `/p/notes/` 前缀下；客户端 JS 按页面路径推导 BASE，API 调用同样落回
   代理前缀 —— 于是整条会话（建会话、事件、长轮询、上传、AJAX）都经代理
   回到插件进程；
4. 无尾斜杠的 `/p/notes` 会 301 到 `/p/notes/`（相对路径推导依赖尾斜杠）；
5. **职责划分：插件只负责业务，非业务功能由主程序处理** —— 框架静态资源
   （`lw.js`/`lw.css`/`lw-alpine.js`/`lw-alpine.css`/`alpine.min.js`、
   `favicon.ico`、`/ext/`）经代理时由宿主直出（`lwroute.LWRouteStaticLocal`
   白名单改写本地路径），不转发给插件：升级客户端运行时只换宿主一处，
   插件部署可以只带 exe。会话绑定类端点（`/lw/api/*`、`/lw/ajax/*`、
   验证码、`/lw/tpl/` 模板）状态在插件会话里，仍代理回插件。

## 已知边界

- **会话独立**：插件有自己的 sid / 登录 / 会话状态，与宿主互不相通
  （这是进程隔离的另一面）。要"宿主登录、插件免登"需要令牌传递，属后续工作；
- **WebSocket 暂不透传**：经代理的插件页面走长轮询（功能完整，只是推送
  从毫秒级变成轮询节奏），前端会自动回退；WS 隧道列入后续增强；
- 页面粒度 B（往宿主已有页面的组件树里加控件）在进程形态下做不到 ——
  那需要编译期链入（plugindemo 形态）或 Runtime Package；
- 插件端口只对本机开放即可；对局域网开放时注意插件自身也要设防火墙规则。

## 两种形态怎么选

| | plugindemo（编译期链入） | procdemo（独立 exe） |
|---|---|---|
| 页面粒度 | A/B/C 全支持 | A/C |
| 故障隔离 | 同进程 | **进程级** |
| 独立发布/升级 | 要重编宿主 | **换插件 exe 即可** |
| 跨平台 | 一份源码各平台编 | 一份源码各平台编 |
| 会话 | 同一会话体系 | 各自独立 |
