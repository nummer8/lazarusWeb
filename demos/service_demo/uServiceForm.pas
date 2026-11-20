{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: service_demo 业务窗体

  刻意用纯代码建控件、不带 .lfm —— 证明服务里跑的就是普通 TLWForm，
  也省掉一份 lfm 资源。浏览器里看到的就是这个 LCL 窗体的控件树。
}
unit uServiceForm;
{$codepage utf8}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, lwform;

type
  TServiceForm = class(TLWForm)
  private
    FCount: Integer;
    btnPing: TButton;
    edtName: TEdit;
    mmoLog: TMemo;
    procedure BtnPingClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

constructor TServiceForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := 'lazarusWeb Windows Service 演示';
  Width := 520;
  Height := 320;

  edtName := TEdit.Create(Self);
  edtName.Parent := Self;
  edtName.Name := 'edtName';
  edtName.Text := '访客';
  edtName.Left := 16;
  edtName.Top := 16;
  edtName.Width := 200;

  btnPing := TButton.Create(Self);
  btnPing.Parent := Self;
  btnPing.Name := 'btnPing';
  btnPing.Caption := '点击（服务端事件）';
  btnPing.Left := 224;
  btnPing.Top := 16;
  btnPing.Width := 160;
  btnPing.OnClick := @BtnPingClick;

  mmoLog := TMemo.Create(Self);
  mmoLog.Parent := Self;
  mmoLog.Name := 'mmoLog';
  mmoLog.Left := 16;
  mmoLog.Top := 56;
  mmoLog.Width := 480;
  mmoLog.Height := 230;
  mmoLog.ReadOnly := True;
  mmoLog.Lines.Add('服务已启动。每个会话在服务端创建一个真实的 LCL 窗体。');
  mmoLog.Lines.Add('点击按钮验证：事件经浏览器回传到服务端处理。');
end;

procedure TServiceForm.BtnPingClick(Sender: TObject);
begin
  Inc(FCount);
  mmoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) +
    '  ' + edtName.Text + ' 第 ' + IntToStr(FCount) + ' 次点击（服务端已处理）');
end;

end.
