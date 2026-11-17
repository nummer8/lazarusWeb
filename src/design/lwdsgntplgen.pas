{ lazarusWeb :: lwdsgntplgen
  ------------------------------------------------------------------
  设计期 IDE 集成：Tools 菜单「生成 lazarusWeb 窗体模板（当前单元 LFM）」。

  行为：取当前源码编辑器文件——.lfm 直接用；.pas/.pp 按同名 .lfm 找——
  解析顶层控件（lwdsgntplcore），在 <工程目录>\tpl\ 下生成两份模板骨架：
    <窗体名>.html    桌面（按设计期宽度比例流式）
    <窗体名>.m.html  移动（单列流式）
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
  Dialogs, Controls, LazFileUtils, lwdsgntplcore;

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
  FMobile, FDesktop: string;
begin
  LfmPath := CurrentLfmFile;
  if LfmPath = '' then
  begin
    ShowMessage('lazarusWeb 模板生成：' + sLineBreak +
      '请先打开窗体单元（.pas）或窗体文件（.lfm）。' + sLineBreak +
      '当前编辑器里没有可识别的单元文件。');
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
    begin
      ShowMessage('lazarusWeb 模板生成：' + sLineBreak +
        '窗体 ' + FormName + ' 没有可进模板的顶层控件' + sLineBreak +
        '（非可视控件与状态栏会被跳过）。');
      Exit;
    end;

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

    FMobile := OutDir + PathDelim + FormName + '.m.html';
    FDesktop := OutDir + PathDelim + FormName + '.html';
    if FileExistsUTF8(FMobile) and
       (QuestionDlg('lazarusWeb', '移动模板已存在，覆盖？' + sLineBreak +
        FMobile, mtConfirmation, [mrYes, '覆盖', mrNo, '跳过'], 0) <> mrYes) then
      FMobile := '';
    if FileExistsUTF8(FDesktop) and
       (QuestionDlg('lazarusWeb', '桌面模板已存在，覆盖？' + sLineBreak +
        FDesktop, mtConfirmation, [mrYes, '覆盖', mrNo, '跳过'], 0) <> mrYes) then
      FDesktop := '';

    if FMobile <> '' then
      SaveUtf8File(FMobile, GenMobileTplEx(FormName, Kids, FormWidth, Warnings));
    if FDesktop <> '' then
      SaveUtf8File(FDesktop, GenDesktopTplEx(FormName, Kids, FormWidth, Warnings));

    if (FMobile = '') and (FDesktop = '') then
      ShowMessage('lazarusWeb 窗体模板：两份模板都已存在且未覆盖，未做改动。')
    else
    begin
      sMsg := 'lazarusWeb 窗体模板已生成（窗体 ' + FormName + '，' +
        IntToStr(Kids.Count) + ' 个顶层控件）：';
      if FDesktop <> '' then
        sMsg := sMsg + sLineBreak + '  桌面：' + FDesktop;
      if FMobile <> '' then
        sMsg := sMsg + sLineBreak + '  移动：' + FMobile;
      sMsg := sMsg + sLineBreak + sLineBreak +
        '放进运行根目录的 tpl\ 下即被 /lw/tpl/ 下发（no-store，改动刷新即生效）；' +
        sLineBreak + '骨架只含占位符与基础 CSS，可按手册第二篇 16 精修。';
      if Warnings.Count > 0 then
      begin
        sMsg := sMsg + sLineBreak + sLineBreak + '自检提示（也已写入模板文件头）：';
        for i := 0 to Warnings.Count - 1 do
          sMsg := sMsg + sLineBreak + '  - ' + Warnings[i];
      end;
      ShowMessage(sMsg);
    end;
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
