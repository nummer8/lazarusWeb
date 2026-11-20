{
  SPDX-License-Identifier: MIT  (c) 2026 szlbz(秋风) QQ:315795176 -- 见仓库根目录 LICENSE
  lazarusWeb :: service_demo 守护映射

  DaemonApp 运行时需要一个 TDaemonMapper 才能找到要启动的 daemon 类。
  Mapper 由框架以流式方式创建（就像 DataModule），所以必须有 lfm 资源：
  官方 TDaemon 示例同样带 daemonmapperunit.lfm。

  lfm 里声明的 DaemonClassName = 'TLWServiceDaemon' 会由 DaemonApp 的
  BindDaemonDefs 绑定到 RegisterDaemonClass 注册的守护类。
}
unit uServiceMapper;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DaemonApp;

type
  TServiceDaemonMapper = class(TDaemonMapper)
  end;

{ 注册映射类；在 DaemonApp.Application.Initialize 之前调用 }
procedure RegisterServiceMapper;

implementation

{$R *.lfm}

procedure RegisterServiceMapper;
begin
  RegisterDaemonMapper(TServiceDaemonMapper);
end;

end.
