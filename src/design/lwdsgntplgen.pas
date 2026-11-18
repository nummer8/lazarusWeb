{ lazarusWeb :: lwdsgntplgen
  ------------------------------------------------------------------
  设计期 IDE 集成：Tools 菜单「生成 lazarusWeb 窗体模板（当前单元 LFM）」。

  行为：取当前源码编辑器文件——.lfm 直接用；.pas/.pp 按同名 .lfm 找——
  点击菜单先弹模式选择，再解析顶层控件（lwdsgntplcore）写入 <工程目录>\tpl\：
    窗口模式：浮窗可移动/缩放；平面模式：标准网页整页布局（无浮窗标题/边框）。
    两种模式都生成桌面 <窗体名>.html 与移动 <窗体名>.m.html 两份，文件头写
    lw-tpl-mode:window|flat 标记，由客户端按标记决定渲染方式。
    两份模板都只作背景/装饰层，控件始终按 LFM 的 Left/Top 绝对定位；
    移动端有 .m.html 时用移动模板，没有则回退桌面端 LCL 布局。
  文件已存在时询问是否覆盖。无工程时写到单元文件旁边的 tpl\。
  生成后弹窗告知路径（模板 no-store 下发，放进运行根目录的 tpl\ 即生效）。

  解析与内容生成在 lwdsgntplcore（无 IDE 依赖），本单元只管 IDE 交互。 }
unit lwdsgntplgen;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

procedure Register;

implementation

uses
  MenuIntf, LazIDEIntf, ProjectIntf, SrcEditorIntf,
  Dialogs, Controls, LazFileUtils, StrUtils, lwdsgntplcore;

type
  { RegisterIDEMenuCommand 的回调是 method 指针，处理逻辑挂在这个
    单例对象上（单元 initialization 创建） }
  TTplGenMenuHandler = class
  public
    procedure ExecGenFormTpl(Sender: TObject);
  end;

var
  TplGenMenuHandler: TTplGenMenuHandler = nil;

procedure SaveUtf8File(const FN, Content: string);
var
  fs: TFileStream;
  b: string;
begin
  b := Content;   { IDE 内部字符串即 UTF-8 }
  fs := TFileStream.Create(FN, fmCreate);
  try
    if Length(b) > 0 then
      fs.WriteBuffer(b[1], Length(b));
  finally
    fs.Free;
  end;
end;

{ 当前打开单元对应的 lfm：.lfm 直接用，.pas/.pp 找同名 .lfm }
function CurrentLfmFile: string;
var
  fn: string;
begin
  Result := '';
  if SourceEditorManagerIntf.ActiveEditor = nil then
    Exit;
  fn := SourceEditorManagerIntf.ActiveEditor.FileName;
  if fn = '' then
    Exit;
  if LowerCase(ExtractFileExt(fn)) = '.lfm' then
    Result := fn
  else if LowerCase(ExtractFileExt(fn)) = '.dfm' then
    Result := ''
  else
  begin
    Result := ChangeFileExt(fn, '.lfm');
    if not FileExistsUTF8(Result) then
      Result := '';
  end;
end;

procedure TTplGenMenuHandler.ExecGenFormTpl(Sender: TObject);
var
  LfmPath, OutDir, FormName, sMsg: string;
  FormWidth, i: Integer;
  Kids: TObjectList;
  SL, Warnings: TStringList;
  Prj: TLazProject;
  FOut, FOutM: string;
  Flat: Boolean;
begin
  LfmPath := CurrentLfmFile;
  if LfmPath = '' then
  begin
    ShowMessage('lazarusWeb 模板生成：' + sLineBreak +
      '请先打开窗体单元（.pas）或窗体文件（.lfm）。' + sLineBreak +
      '当前编辑器里没有可识别的单元文件。');
    Exit;
  end;

  { 模式选择：两种模式都写同一个 <窗体名>.html，靠文件头标记区分 }
  case QuestionDlg('lazarusWeb 模板生成',
    '请选择要生成的模板模式：' + sLineBreak +
    '  窗口模式：现有浮窗（可移动、调整大小）；' + sLineBreak +
    '  平面模式：标准网页整页布局（无标题栏、不可拖动缩放）；' + sLineBreak +
    '两者都只生成 <窗体名>.html，控件始终保持设计期绝对位置。',
    mtConfirmation, [mrYes, '窗口模式', mrNo, '平面模式', mrCancel, '取消'], 0) of
    mrYes: Flat := False;
    mrNo: Flat := True;
  else
    Exit;
  end;

  SL := TStringList.Create;
  Warnings := TStringList.Create;
  Kids := nil;
  try
    SL.LoadFromFile(LfmPath);
    if not ParseLfmTextEx(SL, FormName, FormWidth, Kids, Warnings) or (FormName = '') then
    begin
      ShowMessage('lazarusWeb 模板生成：' + sLineBreak +
        '解析失败，没有找到窗体对象：' + sLineBreak + LfmPath);
      Exit;
    end;
    if Kids.Count = 0 then
      Warnings.Add('窗体 ' + FormName +
        ' 没有顶层可视控件（非可视控件与状态栏会被跳过），本次生成空容器骨架');

    { 输出目录：<工程目录>\tpl\（工程目录取 .lpi 所在目录），无工程时退回 lfm 旁边 }
    OutDir := '';
    try
      Prj := LazarusIDE.ActiveProject;
      if (Prj <> nil) and (Prj.ProjectInfoFile <> '') then
        OutDir := AppendPathDelim(ExtractFilePath(Prj.ProjectInfoFile)) + 'tpl';
    except
      OutDir := '';
    end;
    if (OutDir = '') or not DirectoryExistsUTF8(ExtractFileDir(
       ExcludeTrailingPathDelimiter(OutDir))) then
      OutDir := AppendPathDelim(ExtractFilePath(LfmPath)) + 'tpl';
    if not DirectoryExistsUTF8(OutDir) then
      ForceDirectoriesUTF8(OutDir);

    { 桌面单文件 <窗体名>.html + 移动 <窗体名>.m.html：两份同为装饰层，
      文件头标记决定渲染方式；两模式共用同一批文件名，不会模式间互残 }
    FOut := OutDir + PathDelim + FormName + '.html';
    FOutM := OutDir + PathDelim + FormName + '.m.html';
    if FileExistsUTF8(FOut) and
       (QuestionDlg('lazarusWeb', '桌面模板已存在，覆盖？' + sLineBreak +
        FOut, mtConfirmation, [mrYes, '覆盖', mrNo, '跳过'], 0) <> mrYes) then
      FOut := '';
    if FileExistsUTF8(FOutM) and
       (QuestionDlg('lazarusWeb', '移动模板已存在，覆盖？' + sLineBreak +
        FOutM, mtConfirmation, [mrYes, '覆盖', mrNo, '跳过'], 0) <> mrYes) then
      FOutM := '';

    if FOut <> '' then
      SaveUtf8File(FOut, GenUnifiedTplEx(FormName, Kids, FormWidth, Flat, Warnings));
    if FOutM <> '' then
      SaveUtf8File(FOutM, GenUnifiedTplEx(FormName, Kids, FormWidth, Flat, Warnings));

    if (FOut = '') and (FOutM = '') then
      sMsg := 'lazarusWeb 窗体模板：两份模板都已存在且未覆盖，未做改动。'
    else
    begin
      if Flat then
        sMsg := 'lazarusWeb 平面模板已生成（窗体 ' + FormName + '，' +
          IntToStr(Kids.Count) + ' 个顶层控件）：'
      else
        sMsg := 'lazarusWeb 窗口模板已生成（窗体 ' + FormName + '，' +
          IntToStr(Kids.Count) + ' 个顶层控件）：';
      if FOut <> '' then
        sMsg := sMsg + sLineBreak + '  桌面：' + FOut;
      if FOutM <> '' then
        sMsg := sMsg + sLineBreak + '  移动：' + FOutM;
      sMsg := sMsg + sLineBreak + sLineBreak +
        '放进运行根目录的 tpl\ 下即被 /lw/tpl/ 下发（no-store，改动刷新即生效）；' +
        sLineBreak + '模板只作背景装饰层，控件保持设计期 Left/Top 绝对位置；' +
        sLineBreak + '文件头 lw-tpl-mode:' +
        IfThen(Flat, 'flat', 'window') + ' 决定浮窗或整页渲染；' +
        sLineBreak + '移动端优先用 .m.html，没有则回退桌面端 LCL 布局。';
    end;

    { 覆盖被跳过时也要给反馈，否则点了菜单像没反应 }
    if (FOut <> '') or (FOutM <> '') then
    begin
      if Warnings.Count > 0 then
      begin
        sMsg := sMsg + sLineBreak + sLineBreak + '自检提示（也已写入模板文件头）：';
        for i := 0 to Warnings.Count - 1 do
          if Pos('生成占位符', Warnings[i]) = 0 then   { 统一模板不用占位符 }
            sMsg := sMsg + sLineBreak + '  - ' + Warnings[i];
      end;
    end;
    ShowMessage(sMsg);
  finally
    Kids.Free;
    SL.Free;
    Warnings.Free;
  end;
end;

procedure Register;
begin
  RegisterIDEMenuCommand(itmSecondaryTools, 'lwGenFormTpl',
    '生成 lazarusWeb 窗体模板（当前单元 LFM）',
    @TplGenMenuHandler.ExecGenFormTpl);
end;

initialization
  TplGenMenuHandler := TTplGenMenuHandler.Create;

finalization
  FreeAndNil(TplGenMenuHandler);

end.
