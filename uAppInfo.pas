unit uAppInfo;
{$mode objfpc}{$H+}{$codepage utf8}
interface
function AppBuildVersion: string;
function AppBuildCommit: string;
function AppAboutText(const AGameName: string = 'International draughts'): string;
function AppManualText: string;
implementation
uses Classes, SysUtils{$IFDEF MSWINDOWS}, Windows{$ENDIF};
{$IFDEF GWDGUI_EMBEDDED_HELP}
{$I gwdgui-build.inc}
{$ELSE}
const
  BuildCommit = 'unavailable (build with build.sh or the Windows build mode to embed the commit)';
  BuildRevision = 'development build';
  BuildHasChanges = False;
  BuildChangesKnown = False;
{$ENDIF}
resourcestring
  AppReleaseVersion = '1.2';
function AppBuildVersion:string;
var ShortId:string;I:Integer;
begin
 ShortId:='unknown';
 if Length(BuildCommit) in [40,64] then begin
  ShortId:=LowerCase(Copy(BuildCommit,1,7));
  for I:=1 to Length(BuildCommit) do if not (BuildCommit[I] in ['0'..'9','a'..'f','A'..'F']) then begin ShortId:='unknown';Break;end;
 end;
 Result:=AppReleaseVersion+'-'+ShortId;
end;
function AppBuildCommit: string;
begin Result := BuildCommit; end;
function AppAboutText(const AGameName: string): string;
begin
  Result := 'ZGUI ' + AppBuildVersion + LineEnding + AGameName + LineEnding +
    LineEnding + 'Build: ' + BuildRevision + LineEnding + 'Commit: ' + BuildCommit;
  if BuildHasChanges then Result += LineEnding + 'Includes uncommitted changes.';
  if not BuildChangesKnown then Result += LineEnding + 'Working-tree status unavailable.';
end;
function AppManualText: string;
var Lines: TStringList; Path: string;
    {$IFDEF GWDGUI_EMBEDDED_HELP}Stream:TResourceStream;{$ENDIF}
begin
  Result := '';
  {$IFDEF GWDGUI_EMBEDDED_HELP}
  Stream:=TResourceStream.Create(HInstance,'ZGUI_MANUAL',RT_RCDATA);
  try
    SetLength(Result,Stream.Size);
    if Length(Result)>0 then Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free;end;
  {$ENDIF}
  if Result <> '' then Exit;
  // Direct IDE/source-archive builds can use a manual beside the executable.
  Path := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0)))) + 'MANUAL.md';
  Lines := TStringList.Create;
  try
    if FileExists(Path) then
    begin Lines.LoadFromFile(Path); Result := Lines.Text; end
    else Result := 'The manual is not included in this build.' + LineEnding +
      'Build with build.sh or the Windows build mode, or place MANUAL.md beside the application.';
  finally Lines.Free; end;
end;
end.
