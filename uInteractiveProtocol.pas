unit uInteractiveProtocol;
{$mode objfpc}{$H+}
interface
function ProtocolError(const Code,Text:string):string;
function ValidCliUtf8(const S:string):Boolean;
implementation
uses FPJSON;
function ProtocolError(const Code,Text:string):string;
var J:TJSONObject;
begin J:=TJSONObject.Create;try J.Add('code',Code);J.Add('message',Text);Result:='ERROR '+J.AsJSON;finally J.Free;end;end;
function ValidCliUtf8(const S:string):Boolean;
var I,N,J:Integer;B,C:Byte;Value,Minimum:Cardinal;
begin
 I:=1;while I<=Length(S) do begin
  B:=Ord(S[I]);if B<128 then begin Inc(I);Continue;end;
  if (B>=$C2) and (B<=$DF) then begin N:=1;Value:=B and $1F;Minimum:=$80;end
  else if (B>=$E0) and (B<=$EF) then begin N:=2;Value:=B and $F;Minimum:=$800;end
  else if (B>=$F0) and (B<=$F4) then begin N:=3;Value:=B and 7;Minimum:=$10000;end
  else Exit(False);
  if I+N>Length(S) then Exit(False);
  for J:=1 to N do begin C:=Ord(S[I+J]);if (C and $C0)<>$80 then Exit(False);Value:=(Value shl 6) or (C and $3F);end;
  if (Value<Minimum) or (Value>$10FFFF) or ((Value>=$D800) and (Value<=$DFFF)) then Exit(False);
  Inc(I,N+1);
 end;Result:=True;
end;
end.
