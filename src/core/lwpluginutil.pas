unit lwpluginutil;
{ 插件辅助单元：JSON 转义。
  它没有 RegisterModule，tools/lwplugins.py 会自动跳过，不会被当成模块。

  注意：「按注册名打开页面」已经是框架 API —— 直接用 TLWApp.OpenForm('Notes')，
  不需要本单元。这里保留 LWOpenForm 只是早期示例的兼容包装。 }
{$mode objfpc}{$H+}

interface

uses
  SysUtils;

{ 把任意文本转成可安全放进 JSON 字符串字面量的形式 }
function JsonEscape(const S: string): string;

{ 兼容包装：等价于 TLWApp.OpenForm(AName) }
function LWOpenForm(const AName: string): Boolean;

implementation

uses
  lwapp;

function JsonEscape(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if c < #32 then
        Result := Result + '\u' + IntToHex(Ord(c), 4)
      else
        Result := Result + c;
    end;
  end;
end;

function LWOpenForm(const AName: string): Boolean;
begin
  Result := TLWApp.OpenForm(AName);
end;

end.
