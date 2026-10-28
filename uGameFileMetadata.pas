unit uGameFileMetadata;
{$mode objfpc}{$H+}
interface
type
  TGameFileTag = record Name, Value: string; end;
  TGameFileTags = array of TGameFileTag;
function CopyGameFileTags(const Tags: TGameFileTags): TGameFileTags;
function GameFileTagsEqual(const A,B: TGameFileTags): Boolean;
function GameFileTagValue(const Tags: TGameFileTags; const Name, Fallback: string): string;
implementation
function CopyGameFileTags(const Tags: TGameFileTags): TGameFileTags;
begin Result:=Copy(Tags,0,Length(Tags)); end;
function GameFileTagsEqual(const A,B: TGameFileTags): Boolean;
var I: Integer;
begin
  Result:=False; if Length(A)<>Length(B) then Exit;
  for I:=0 to High(A) do if (A[I].Name<>B[I].Name) or (A[I].Value<>B[I].Value) then Exit;
  Result:=True;
end;
function GameFileTagValue(const Tags: TGameFileTags; const Name,Fallback: string): string;
var I: Integer;
begin
  for I:=0 to High(Tags) do if Tags[I].Name=Name then Exit(Tags[I].Value);
  Result:=Fallback;
end;
end.
