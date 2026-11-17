{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: lwcamera
  ------------------------------------------------------------------
  TLWCamera —— 移动端拍照控件（点按钮唤起系统相机，拍完的照片传回服务端）。

  为什么用 <input type=file capture> 而不是 getUserMedia：
    · getUserMedia（页面内实时取景框）只在**安全上下文**可用 —— HTTPS 或
      localhost。局域网里用手机访问 http://192.168.x.x:8090 会被浏览器
      直接拒绝（navigator.mediaDevices 为 undefined），业务现场装证书
      不现实；
    · <input type="file" accept="image/*" capture="environment"> 没有这个
      限制，任何 http 页面都能唤起系统相机 App（安卓 Camera / iOS 拍照），
      拍完由系统把 JPEG 交回页面 —— 与普通选文件同一条上传通道；
    · 代价是没有页面内取景框（用户看到的是系统相机界面）。对"拍一张
      上传"这类业务，这反而更稳、更省电，也不会被"必须 HTTPS"卡死。

  桌面端另走一条路（客户端自动判断，业务代码不用管）：
    · 鼠标/触控板的设备上，浏览器忽略 capture。若页面在安全上下文
      （HTTPS 或 localhost）里，客户端改用 getUserMedia 弹页面内取景框，
      点"拍摄"把当前帧画进 canvas 转 JPEG，走同一条上传通道；
    · 局域网 http 的桌面页面调不了摄像头（浏览器硬限制），自动退化成
      "选择图片文件"对话框 —— 这是环境限制，不是控件缺陷。

  与 TLWFileUpload 的关系：
    直接继承 TLWFileUpload —— 落盘、大小上限、TargetFolder、会话目录、
    multipart 端点（/lw/api/upload?sid=&id=）、增量补丁回包全部复用，
    服务端 lwupload 一行都不用改（它按 `C is TLWFileUpload` 找控件）。
    本单元只加两样东西：
      · Facing：前置/后置摄像头（序列化成 capture 属性）；
      · OnCapture：语义更明确的事件（= OnUpload，二者都会触发）。

  数据流：
    1. 设计期把 TLWCamera 拖到窗体上（按钮外观，设 Caption/坐标）；
    2. 浏览器渲染成带相机图标的按钮，点击 -> 动态建
       <input type=file accept="image/*" capture="environment"> 并 click()；
    3. 用户拍完 -> XHR POST /lw/api/upload?sid=..&id=<控件 id>；
    4. 服务端落盘（uploads/<sid>/<控件名>/photo-<时间>.jpg），
       调 AddUploadedFile -> 触发 OnCapture(Sender, 文件全路径)；
    5. 回包是新组件树，浏览器照常增量协调（可在 OnCapture 里更新
       TImage/TLabel，同一轮补丁就带回浏览器）。

  隐私/合规提示：
    · 相机由系统 App 采集，浏览器不会"偷偷"打开摄像头，页面也拿不到
      实时画面流；
    · 照片落在服务端会话上传目录，随会话清理；业务侧要长期保存请把
      TargetFolder 指到自己的目录，或 OnCapture 里 MoveFile 走。
}
unit lwcamera;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StdCtrls, lwfileupload;

type
  { 用哪颗摄像头：cfRear 后置（默认）/ cfFront 前置。
    手机端序列化成 capture 属性（唤起系统相机的那颗）；
    桌面端序列化成 getUserMedia 的 facingMode（笔记本通常只有一颗）。 }
  TLWCameraFacing = (cfRear, cfFront);

  { 一张照片已保存到服务端。AFileName 是服务端完整路径（可直接
    TFileStream / TPicture.LoadFromFile 打开）。 }
  TLWCameraEvent = procedure(Sender: TObject; const AFileName: string) of object;

  TLWCamera = class(TLWFileUpload)
  private
    FFacing: TLWCameraFacing;
    FPreviewImage: string;
    FOnCapture: TLWCameraEvent;
  public
    constructor Create(AOwner: TComponent); override;
    { 基类在文件落盘后调用；这里再触发 OnCapture }
    procedure AddUploadedFile(const APath: string); override;
  published
    { 前置/后置摄像头，默认后置（cfRear）。桌面浏览器忽略此属性 }
    property Facing: TLWCameraFacing read FFacing write FFacing default cfRear;
    { 拍照后在浏览器里立即回显到哪个 TImage：填该 TImage 的 Name（如
      'imgPhoto'）。留空则只上传不回显。

      回显是**浏览器本地做的**（拍照后直接拿 Blob 显示），图片数据不走
      服务端补丁 —— 手机照片动辄 3~5MB，转 base64 塞进组件树会让每次
      增量补丁都白跑几 MB。服务端只负责落盘与 OnCapture。 }
    property PreviewImage: string read FPreviewImage write FPreviewImage;
    { 照片保存完成。每次拍照触发一次 }
    property OnCapture: TLWCameraEvent read FOnCapture write FOnCapture;
  end;

{ capture 属性的取值：cfRear -> 'environment'，cfFront -> 'user'
  （HTML 规范值；lwwriter 序列化时用） }
function LWCameraFacingAttr(AFacing: TLWCameraFacing): string;

implementation

function LWCameraFacingAttr(AFacing: TLWCameraFacing): string;
begin
  if AFacing = cfFront then
    Result := 'user'
  else
    Result := 'environment';
end;

constructor TLWCamera.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFacing := cfRear;
  { 相机不按文件类型过滤（系统相机只会给图片），但基类的 Filter 默认
    空 = 不限制，前端对 camera 固定 accept=image/* 并忽略 filter }
  if Caption = '' then
    Caption := '拍照…';
end;

procedure TLWCamera.AddUploadedFile(const APath: string);
begin
  inherited AddUploadedFile(APath);
  if Assigned(FOnCapture) then
    FOnCapture(Self, APath);
end;

initialization
  { lfm 按类名实例化（GetClass），可执行文件不加载 lwdesign 包，
    所以运行时这份注册是必需的 —— 与 TLWFileUpload 同理 }
  RegisterClass(TLWCamera);

end.
