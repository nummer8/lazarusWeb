{
  lazarusWeb :: mobile_demo（方案 B：移动模板 + 自适应布局）
  ------------------------------------------------------------------
  同一个窗体、同一棵控件树，两种布局：

    桌面（>= 1100px 视口，或 835~1099 非触控回滞区）：
      控件按 LFM 的绝对坐标渲染（.lw-n 绝对定位），和所有老窗体一样；

    移动（<= 834px 视口，或触控设备落在回滞区）：
      客户端 fetch /lw/tpl/MobileMainForm.m.html，把 {%控件名%} 占位符
      替换成既有控件 DOM 节点（原节点搬迁：不重建、不重取树，事件 id
      与增量补丁照旧），单列流式排布。切回宽窗口自动搬回原位。

  模板文件在 <root>\tpl\MobileMainForm.m.html（本 demo 的 root 是
  C:\lazarusWeb）。占位符引用了不存在的控件名时整体回退桌面布局，
  不会半套。全部为框架机制，业务侧只多写一份模板 HTML。

  编译：仓库根目录 build.bat mobile_demo（lazbuild + --ws=nogui）。
  运行：mobile_demo.exe --port=8106（或 mobile_demo.ini 配置）。
}
unit uMobileMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, lwform, lwweb,
  lwcamera;

type

  { TMobileMainForm }

  TMobileMainForm = class(TLWForm)
    btnClear: TButton;
    btnHello: TButton;
    camPhoto: TLWCamera;
    edName: TEdit;
    imgPhoto: TImage;
    lblInfo: TLabel;
    lblName: TLabel;
    lblTitle: TLabel;
    memLog: TMemo;
    pnlInfo: TPanel;
    StatusBar1: TStatusBar;
    procedure btnClearClick(Sender: TObject);
    procedure btnHelloClick(Sender: TObject);
    procedure camPhotoCapture(Sender: TObject; const AFileName: string);
    procedure FormCreate(Sender: TObject);
  end;

implementation

{$R *.lfm}

function Now_: string;
begin
  Result := FormatDateTime('hh:nn:ss', Now);
end;

procedure TMobileMainForm.FormCreate(Sender: TObject);
begin
  lblInfo.Caption := '把浏览器窗口拖窄到 834px 以下（或用手机打开），'
    + '顶层控件会自动搬进移动模板单列排布；拖宽回 1100px 以上再搬回来。'
    + '两种布局共用同一棵控件树与事件通道。'
    + '「拍照上传」在手机上直接唤起系统相机，局域网 http 也能用。';
  memLog.Lines.Add('[' + Now_ + '] 窗体已创建（桌面布局渲染中）');
end;

{ TLWCamera：照片由浏览器经 /lw/api/upload 传上来，服务端落盘后触发本事件。
  回显（右侧图片框）是浏览器本地做的 —— 手机照片几 MB，不走组件树补丁；
  服务端这里只拿到文件路径，要缩略图/入库自己往下做。 }
procedure TMobileMainForm.camPhotoCapture(Sender: TObject; const AFileName: string);
var
  sz: Int64;
  fs: TFileStream;
begin
  sz := 0;
  try
    fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      sz := fs.Size;
    finally
      fs.Free;
    end;
  except
    sz := 0;
  end;
  memLog.Lines.Add(Format('[%s] 收到照片：%s（%d KB）-> %s',
    [Now_, ExtractFileName(AFileName), sz div 1024, AFileName]));
  lblInfo.Caption := Format('照片已保存到服务端：%s（%d KB）。'
    + '图片框是浏览器本地预览；换前置/后置摄像头改 TLWCamera.Facing。',
    [ExtractFileName(AFileName), sz div 1024]);
end;

procedure TMobileMainForm.btnHelloClick(Sender: TObject);
var
  s: string;
begin
  s := Format('你好，%s！服务端事件在两种布局下同样生效。', [edName.Text]);
  lblInfo.Caption := s;
  memLog.Lines.Add('[' + Now_ + '] ' + s);
end;

procedure TMobileMainForm.btnClearClick(Sender: TObject);
begin
  memLog.Clear;
  lblInfo.Caption := '日志已清空。';
end;

end.
