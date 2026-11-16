# lwhyper 使用说明

lwhyper 是 lazarusWeb 的专用负载均衡器（对标 uniGUI Hyper Server）：一个进程
托管 N 个业务 worker，对外单端口监听，自带 HTTP 反向代理 + sid 会话粘性 +
WebSocket TCP 透传。HTTP 场景**不再需要 nginx**（HTTPS 仍需前置反代做 TLS 终结）。

- 控制台版：`tools\lwhyper.exe`（脚本/服务化部署）
- GUI 版：`tools\lwhyper_gui.exe`（双击即用，无黑窗口）

---

## 1. 架构一览

```
                    ┌─ worker #1  业务exe --port=8091 --nogui --log=worker1.log
浏览器 ──► lwhyper ─┼─ worker #2  业务exe --port=8092 --nogui --log=worker2.log
  :8080             └─ worker #N  ...
        │
        ├ HTTP 反向代理（按 sid 粘性转发）
        ├ WebSocket TCP 透传（ws://:8080 → worker 的 ws 端口）
        ├ healthz 巡检 + 崩溃自动重启（带热身闸门）
        └ /lw/healthz、/lw/hyper/status 两个自身端点
```

关键语义：

- **worker 是同一个业务 exe 多开**：`--port`、`--nogui`、`--log` 由 lwhyper 注入，
  业务 exe 无需感知自己是不是 worker；
- **会话在 worker 进程内存里**：worker 重启 = 该 worker 上的会话全部丢失；
- **lwhyper 重启会丢 sid→worker 表**：带未知 sid 的请求轮询转发兜底（客户端
  会自动重建会话）；
- **粘性三路取 sid**：URL `?sid=` → `X-LW-Sid` 头 → JSON body 的 `sid` 字段。

## 2. 快速上手（控制台版）

```bash
cd C:\lazarusWeb
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos/gallery/gallery.exe --worker-args="--patch=1"
```

浏览器打开 `http://127.0.0.1:8080/` 即可。验证：

```bash
curl --noproxy '*' http://127.0.0.1:8080/lw/healthz
curl --noproxy '*' http://127.0.0.1:8080/lw/hyper/status
```

> ⚠️ 本机测试时 curl 必须带 `--noproxy '*'`：若环境变量 `HTTP_PROXY` 指向本地
> 代理，发往 8080 的请求会被劫持到别处（返回 "upstream connect failed"）。

## 3. 命令行参数

| 参数 | 缺省 | 说明 |
|---|---|---|
| `--port=N` | 8080 | lwhyper 对外监听端口 |
| `--workers=N` | 2 | worker 进程数 |
| `--exe=路径` | （必填） | 业务可执行文件；Linux/macOS 无扩展名 |
| `--base-port=N` | port+1 | 第一个 worker 的端口，之后顺次 +1 |
| `--root=路径` | — | 转发为 worker 的 `--root=`（项目根，含 `src/client/alpine.min.js` 等默认渲染资源；`ext-<版本>/` 仅可选 Ext 层需要） |
| `--theme=名字` | — | 转发为 worker 的 `--theme=` |
| `--worker-args="..."` | — | **原样追加**到 worker 命令行，空格分隔多个参数 |
| `--logdir=目录` | `<TEMP>\lwhyper` | worker 日志目录（worker1.log…） |
| `--verbose` | 关 | 打印每个代理请求 |
| `--help` | — | 帮助 |

worker 还会自动带上 `--nogui`（不弹服务端面板）与 `--log=<logdir>\workerN.log`。

### 3.1 `--worker-args` 详解（重要）

`--worker-args` 是 lwhyper → worker 的**参数透传通道**：里面的内容被原样追加
到每个 worker 的命令行末尾（空格分隔，可传多个）。worker 收到后按
`src/core/lwapp.pas` 的标准参数解析处理——也就是说，**业务 exe 单独运行时
支持的参数，worker 都能通过它拿到**。

**最常用：`--patch=1`（增量补丁，强烈建议开启）**

```bash
--worker-args="--patch=1"
```

- worker 序列化窗体状态后与上次快照 diff，**每次事件只回传变化的 ops**，
  而不是整棵窗体树；
- 效果：单会话 156 事件/秒 vs 全量 63 事件/秒，载荷 1.5KB vs 71KB
  （流量降 97%，BENCH §7/§8）；
- 兼容性：老前端的渲染层不支持增量协议时**自动退回全量**，功能不坏，
  只是吃不到收益——所以可以放心常开；
- 排障提示：pipe_bench 输出里"退回全量 N 次"说明当时客户端没带增量能力，
  不是 worker 出错。

**其它可透传的 worker 参数**（与 worker `--help` 一致）：

| 参数 | 说明 | 典型场景 |
|---|---|---|
| `--config=path` | 指定业务 ini；缺省自动找 exe 同目录 `<exe名>.ini` | 多套配置切换 |
| `--root=路径` | 项目根目录（默认 Alpine 资源在 `src/client/`；可选 Ext 才需 `ext-<版本>/`）；也可用 lwhyper 的 `--root=` 转发 | 部署目录不在缺省位置 |
| `--form=Name` | 默认窗体名（打开首页呈现的窗体） | 一 exe 多入口 |
| `--client=alpine\|ext` | 浏览器渲染层：`alpine` 默认（内置）；`ext` 可选，需自备 ext 目录；不指定时自动探测优先 alpine | 调试渲染层差异 |
| `--ext=x.x.x` / `--extdir=目录` | Ext 版本 / ext-js 目录 | 多版本 Ext 共存 |
| `--theme=crisp` | classic/crisp/gray/material/neptune/graphite，URL `?theme=` 可覆盖 | 也可用 lwhyper 的 `--theme=` 转发 |
| `--title=标题` | 浏览器标签页标题 | 品牌定制 |
| `--timeout=20` | 会话空闲超时（分钟） | 长值守业务调大 |
| `--verbose` | worker 打印每个请求（进 workerN.log） | 排障 |
| `--ajax-cors` | `/lw/ajax/*` 回 CORS 头 | 第三方站点直调 ajax |
| `--trust-proxy` | nginx/Caddy 反代后取 X-Forwarded-For 作客户端 IP | HTTPS 前置反代场景 |

注意 `--port`、`--nogui`、`--log` 由 lwhyper **注入**，不要再写进
`--worker-args`（写了会与注入值冲突/重复）。

**组合示例**：

```bash
# 生产：增量补丁 + 反代后取真实 IP + 会话 60 分钟
tools\lwhyper.exe --port=8080 --workers=4 --exe=demos\gallery\gallery.exe ^
  --worker-args="--patch=1 --trust-proxy --timeout=60"

# 排障：worker 记录每个请求
tools\lwhyper.exe --port=8080 --workers=2 --exe=demos\gallery\gallery.exe ^
  --worker-args="--patch=1 --verbose"

# GUI 版：同样内容写在 lwhyper_gui.cfg 的 extra= 里
#   extra=--patch=1 --trust-proxy --timeout=60
```

**转义与注意事项**：

- cmd.exe 用双引号包住整串：`--worker-args="--patch=1 --verbose"`；bash 里
  同样用双引号；
- 多个参数以空格分隔，不要加逗号/分号；
- 历史坑 106（追加参数时 `--port` 被抹掉、worker 撞 8090 无限重启）已修复；
  排障第一步永远是看 `[hyper] launch #N ... args=...` 日志行，核对 worker
  实际拿到的命令行；
- 每次改 `--worker-args` 后重启 lwhyper 才生效（worker 命令行在拉起时定型）。

## 4. GUI 版（lwhyper_gui.exe）

配置固定放 **exe 目录**：`tools\lwhyper_gui.cfg`（与 exe 同行部署，排查直观）：

```ini
[cfg]
port=8096
workers=2
baseport=0
exe=C:/lazarusWeb/demos/gallery/gallery.exe
root=
theme=
logdir=C:/Users/szlbz/AppData/Local/Temp/lwhyper_gui
extra=--patch=1
verbose=0
autostart=1
```

- `extra` 等价于控制台版的 `--worker-args`；
- `autostart=1`：启动即自动点「启动」，拉起服务（无头部署/CI 冒烟用）；
- 界面日志窗口显示启动横幅与错误；worker 各自写自己的日志文件；
- GUI 版与控制台版共用同一套核心代码（src/core/lwhyper.pas），实测吞吐/延迟
  完全一致（BENCH §8），可放心作为日常部署入口。

## 5. 自身端点

| 端点 | 用途 |
|---|---|
| `/lw/healthz` | 汇总健康：`{ ok, role:"hyper", workers, alive, sessions, uptime }`，LB/k8s 探针直接用 |
| `/lw/hyper/status` | worker 明细：端口/pid/存活/会话数/重启次数；另有 `wsopen`（正在透传的 WS 隧道数，收尾正确时必然回 0）/`wsdone`（累计正常收尾）/`heap`（当前 FPC 堆占用）—— 排查 "每连接漏对象" 先看 `wsopen` 是不是单调上涨（坑 122） |

## 6. 监控与自愈

- 探针：每 worker 巡检其 `/lw/healthz`，IO 超时 3 秒（探针不会被挂死的 worker 拖住）；
- 崩溃重启：worker 异常退出时清掉粘在它上面的 sid 表项并重启，日志记
  `[hyper] worker #N (端口) 异常退出，重启中 (第 X 次)`；
- **热身闸门**：重启后的 worker 要连续通过 2 轮探针才重新对外放流量
  （重启初期进程还在起，别急着把请求打过去）；首轮启动不受影响；
- 没就绪的 worker 被探针标成 dead，代理对它回 502；
- 关闭：lwhyper 收退出信号 → 关监听（≤250ms）→ 杀全部 worker，日志目录里
  留有完整过程。

## 7. 日志

- **lwhyper 自身日志**：控制台打印（GUI 版进日志窗口）；GUI 版另落一份
  `<logdir>\hyper.log`；worker 启动行格式：
  `[hyper] launch #N port=XXXX exe=... args=...`（排障第一步先看这行，核对
  worker 拿到的命令行）；
- **worker 日志**：`<logdir>\workerN.log`，只记请求行与会话事件（启动横幅走
  backlog/控制台，不落这里），逐行 flush。

## 8. 性能与容量（参考 BENCH §7/§8）

- 单 worker 上限 ≈ 160 事件/秒（gallery demo，4C8T）；2 worker 4 会话实测 225/秒；
- **建议 `--workers` = 物理核数 / 2**，再多收益递减（CPU 是瓶颈不是架构）；
- `--patch=1`（增量补丁）单会话 156/秒 vs 全量 63/秒，流量降 97%，**强烈建议开启**；
- 20 并发内 p50 < 300ms 可用；40 并发起 p95 过 1s；80 并发触发
  `MaxLiveConnectionCount=128` 的 503 洪峰（503 来自活动连接上限，
  `QueueSize=64` 是更前面的 listen backlog，超了直接拒连不带 503，
  见 BENCH §5）——扩 worker 数或加前置缓冲。

## 9. 排障速查（详见 NOTES 坑 106/107/108）

| 症状 | 原因 | 处理 |
|---|---|---|
| worker 无限重启，`Binding of socket failed: 8090` | `--worker-args` 追加参数时把 `--port` 抹掉（坑 106，已修复） | 升级到含坑 106 修复的版本；看 `[hyper] launch` 行核对 args |
| worker 抛 FPImageException 后失响应 | 无头 widgetset 上异常对话框雷，原始异常被吞（坑 107） | 三层修复已内建（OnException 接管/WriteControl 降级/DDL 一次化）；worker 日志查 `unhandled` 行找真凶 |
| 进程"启动即退出"、无崩溃记录 | 终端工具 Job Object 在命令结束杀进程树（坑 108，测试环境假象） | 长驻服务用后台任务/系统服务方式启动；真实用户终端不受影响 |
| curl 请求被劫持到别的服务 | 环境变量 HTTP_PROXY 指向本地代理 | curl 加 `--noproxy '*'` |
| 40 并发以上大量 503 | fphttpserver MaxLiveConnectionCount=128（活动连接上限）洪峰 | 加 worker 数；或前置 nginx/Caddy 做缓冲 |
