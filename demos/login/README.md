# login 演示 —— TLWLoginForm 登录/权限框架

uniGUI 的 TUniLoginForm 对应物。演示「lfm/IDE 可设计」的登录窗体 +
会话级认证拦截 + 退出登录 + 图形验证码。

## 运行

```
logindemo.exe --port=8094
```

浏览器打开 `http://127.0.0.1:8094/` —— 新会话自动被登录窗体接管。
演示账号 admin / 123456（`uLogin.pas` 的 `DoLoginEx` 里，内网演示用）。

排障时可用 `set LW_CAPTCHA_DEBUG=1` 再启动：服务端会把
`[lw] captcha <令牌> = <答案>` 打到 stderr，用来分清"码不对"还是"图不对"。

## 结构

- `uLogin.pas / uLogin.lfm` —— `TLoginForm = class(TLWLoginForm)`，
  **lfm 设计**：published 区声明控件字段（lblTitle/lblUser/lblPass/lblCode/
  edUser/edPass/edCode/captcha1/btnOk/btnReset），lfm 根节点
  `OnCreate = FormCreate`，btnOk `OnClick = DoLogin`（基类 published 方法，
  直接在 lfm 里引用），btnReset `OnClick = DoReset`。业务校验在 `OnLogin`
  事件（`DoLoginEx`：对账号密码，`AOk := True`；错则填 AErr 并 Toast）。
- `captcha1: TLWCaptcha` —— 图形验证码。**基类负责校验**：`TryLogin` 先验码
  再验账号密码，码错弹 Toast 并自动换一张；`edCode` 是约定的输入框名。
  点图片换一张是纯前端动作（`src` 加 `&r=<时间戳>`），零往返。
  把控件删掉就等于关掉验证码（`RequireCaptcha` 也可以设 False）。
- `uMain.pas` —— 业务主窗体（代码建控件，**Name 必须显式设置**）。
  `DoLogout`：`S.Authenticated := False; S.SessionShowForm(S.LoginForm)`。
- `logindemo.lpr` —— 关键就两行：

```pascal
TLWApp.SetLogin(TLoginForm);     // 登录窗体（不进默认窗体顺序）
TLWApp.Register(TMainForm);      // 业务主窗体
```

## 框架语义

- 未认证会话请求任意窗体 → 一律先给登录窗体；
- 认证成功（`S.Authenticated := True`）→ 框架自动
  `TLWApp.CreateForm(DefaultFormName)` 并推送到浏览器；
- 未认证期间**所有**非登录窗体上的事件（含 API 调用）→
  `400 {"ok":false,"err":"not authenticated"}`；
- 登录失败（验证码错 / 账号密码错）→ `PushToast` 提示 + 换一张验证码，
  会话仍停在登录窗体。

## 回归

`tests/t_login.py`（19 项）：接管、lfm 控件齐全、password 标志、
**验证码控件与图片下载**、错误密码 Toast、正确密码进主窗体、显示用户、
认证后事件、退出登录、注销拦截、重新登录。运行方式：

```
python tests/run_with_server.py demos/login/logindemo.exe tests/t_login.py 8144
```

验证码答案测试没法"看图"：包装器会用 `LW_CAPTCHA_DEBUG=1` 启动服务端、
把输出落到 `tests/.server.log` 并通过 `LW_CAPTCHA_LOG` 告诉测试脚本，
测试按令牌去日志里取答案 —— 这样验的是"图/码/校验"三者一致，
而不是某个写死的字符串能不能过。

浏览器侧另有 `tests/cdp_captcha_e2e.py`（真实 Edge + 真实鼠标）：
首屏解码、点图换码（对照服务端日志确认答案真变了）、小写也能通过、
错误码 Toast + 自动换图、Ext 层渲染。
