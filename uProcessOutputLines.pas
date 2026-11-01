unit uProcessOutputLines;
{$mode objfpc}{$H+}
interface
uses Classes;
procedure FrameProcessOutput(var Buffer:string;var Dropping:Boolean;const AText:string;ALines:TStrings);
implementation
uses SysUtils;
procedure FrameProcessOutput(var Buffer:string;var Dropping:Boolean;const AText:string;ALines:TStrings);
var LineEnd:Integer;Line:string;
begin
    Buffer += AText;
    while True do
    begin
      // LF terminates both LF and CRLF output, even when a chunk mixes them.
      LineEnd := Pos(#10, Buffer);
      if LineEnd = 0 then
      begin
        if Length(Buffer) > 65536 then
        begin Buffer := ''; Dropping := True; end;
        Break;
      end;
      if Dropping or (LineEnd > 65537) then
      begin
        Delete(Buffer, 1, LineEnd);
        Dropping := False;
        Continue;
      end;

      Line := Trim(Copy(Buffer, 1, LineEnd - 1));
      Delete(Buffer, 1, LineEnd);
      if Line<>'' then ALines.Add(Line);
    end;
end;
end.
