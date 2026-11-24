program GenerateBuildInfo;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes, SysUtils, Process
  {$IFDEF MSWINDOWS}, Windows, ShellApi{$ENDIF};

const ArchiveCommit = '$Format:%H$';
function FilenameIsAbsolute(const Name:string):Boolean;
begin
 {$IFDEF MSWINDOWS}Result:=(ExtractFileDrive(Name)<>'') or ((Name<>'') and (Name[1]='\'));
 {$ELSE}Result:=(Name<>'') and (Name[1]='/');{$ENDIF}
end;
function HexCommit(const Value:string):Boolean;
var I:Integer;
begin
 Result:=Length(Value) in [40,64];if not Result then Exit;
 for I:=1 to Length(Value) do if not (Value[I] in ['0'..'9','a'..'f','A'..'F']) then Exit(False);
end;
function MetadataText(const Name:string):string;
var Lines:TStringList;
begin
 Lines:=TStringList.Create;try Lines.LoadFromFile(Name);Result:=Trim(Lines.Text);finally Lines.Free;end;
end;
function CheckoutCommit(const Root:string):string;
var Directory,Head,Ref,Common,Part:string;Parts,Lines:TStringList;I:Integer;
begin
 Result:='';Parts:=TStringList.Create;Lines:=TStringList.Create;
 try
 try
  Directory:=Root+DirectorySeparator+'.git';
  if FileExists(Directory) then begin
   Head:=MetadataText(Directory);if Copy(Head,1,8)<>'gitdir: ' then Exit;
   Head:=Copy(Head,9,MaxInt);
   if not FilenameIsAbsolute(Head) then Head:=Root+DirectorySeparator+Head;
   Directory:=ExpandFileName(Head);
  end;
  Head:=MetadataText(Directory+DirectorySeparator+'HEAD');
  if Copy(Head,1,5)='ref: ' then begin
   Ref:=Copy(Head,6,MaxInt);
   if (Copy(Ref,1,5)<>'refs/') or (Pos('\',Ref)>0) or (Pos(':',Ref)>0) then Exit;
   Parts.StrictDelimiter:=True;Parts.Delimiter:='/';Parts.DelimitedText:=Ref;
   for I:=0 to Parts.Count-1 do if (Parts[I]='') or (Parts[I]='.') or (Parts[I]='..') then Exit;
   Common:=Directory;
   if FileExists(Directory+DirectorySeparator+'commondir') then begin
    Part:=MetadataText(Directory+DirectorySeparator+'commondir');
    if not FilenameIsAbsolute(Part) then Part:=Directory+DirectorySeparator+Part;
    Common:=ExpandFileName(Part);
   end;
   Part:=Common+DirectorySeparator+StringReplace(Ref,'/',DirectorySeparator,[rfReplaceAll]);
   if FileExists(Part) then Head:=MetadataText(Part)
   else begin
    Head:='';Lines.LoadFromFile(Common+DirectorySeparator+'packed-refs');
    for I:=0 to Lines.Count-1 do if Copy(Lines[I],Pos(' ',Lines[I])+1,MaxInt)=Ref then begin
     Head:=Copy(Lines[I],1,Pos(' ',Lines[I])-1);Break;end;
   end;
  end;
  if HexCommit(Head) then Result:=LowerCase(Head);
 except Result:='';end;
 finally Parts.Free;Lines.Free;end;
end;

function InputParam(Index: Integer): string;
{$IFDEF MSWINDOWS}
type TWideArgs = array[0..65535] of PWideChar;
     PWideArgs = ^TWideArgs;
var Args: PWideArgs; Count: LongInt;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  // RTL ParamStr uses the ANSI command line: use Unicode paths on Windows.
  Args := PWideArgs(CommandLineToArgvW(GetCommandLineW, @Count));
  if Args = nil then RaiseLastOSError;
  try
    if (Index < 0) or (Index >= Count) then
      raise Exception.Create('Missing build information argument');
    Result := UTF8Encode(UnicodeString(Args^[Index]));
  finally
    LocalFree(HLOCAL(Args));
  end;
  {$ELSE}
  Result := ParamStr(Index);
  {$ENDIF}
end;

function Git(const Root: string; const Args: array of string): string;
var P: TProcess; Output: TStringStream; I: Integer;
begin
  P := TProcess.Create(nil);
  Output := TStringStream.Create('');
  try
    P.Executable := 'git';
    P.Parameters.Add('-C');
    P.Parameters.Add(Root);
    for I := 0 to High(Args) do P.Parameters.Add(Args[I]);
    P.Options := [poUsePipes, poNoConsole];
    P.Execute;
    // Drain stdout before waiting, including large dirty working trees.
    Output.CopyFrom(P.Output, 0);
    P.WaitOnExit;
    if P.ExitStatus <> 0 then raise Exception.Create('Git identity unavailable');
    Result := Trim(Output.DataString);
  finally
    Output.Free;
    P.Free;
  end;
end;

function Quoted(const Text: string): string;
begin
  Result := '''' + StringReplace(Text, '''', '''''', [rfReplaceAll]) + '''';
end;

function ReadText(const Name: string): string;
var S: TFileStream;
begin
  S := TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, S.Size);
    if Length(Result) > 0 then S.ReadBuffer(Result[1], Length(Result));
  finally
    S.Free;
  end;
end;

procedure WriteText(const Name,Text:string);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Name,fmCreate);
  try
    if Length(Text)>0 then Stream.WriteBuffer(Text[1],Length(Text));
  finally Stream.Free;end;
end;

procedure CompileManual(const Directory,Compiler,Manual:string);
var P:TProcess;Log:TStringStream;
begin
  WriteText(Directory+DirectorySeparator+'gwdgui-manual.md',Manual);
  WriteText(Directory+DirectorySeparator+'gwdgui-manual.rc',
    'ZGUI_MANUAL RCDATA "gwdgui-manual.md"'+#10);
  P:=TProcess.Create(nil);Log:=TStringStream.Create('');
  try
    P.Executable:=Compiler;
    P.CurrentDirectory:=Directory;
    P.Parameters.Add('-of');P.Parameters.Add('res');
    P.Parameters.Add('gwdgui-manual.rc');P.Parameters.Add('-o');
    P.Parameters.Add('gwdgui-manual.res');
    P.Options:=[poUsePipes,poStderrToOutPut,poNoConsole];
    P.Execute;Log.CopyFrom(P.Output,0);P.WaitOnExit;
    if P.ExitStatus<>0 then
      raise Exception.Create('Manual resource compilation failed: '+Log.DataString);
  finally Log.Free;P.Free;end;
end;

var Root, Commit, Revision, Manual, Text, OutputName, Compiler, ResourceDirectory: string;
    Dirty,ChangesKnown: Boolean;
begin
  {$IFDEF MSWINDOWS}
  SetMultiByteConversionCodePage(CP_UTF8);
  SetMultiByteFileSystemCodePage(CP_UTF8);
  {$ENDIF}
  try
    if not (ParamCount in [2,3]) then
      raise Exception.Create('Expected source root, output filename and optional fpcres path');
    Root := ExcludeTrailingPathDelimiter(ExpandFileName(InputParam(1)));
    OutputName := ExpandFileName(InputParam(2));
    Compiler:='fpcres';if ParamCount=3 then Compiler:=InputParam(3);
    try
      {$IFDEF MSWINDOWS}
      if CompareText(ExpandFileName(Git(Root, ['rev-parse', '--show-toplevel'])), Root) <> 0 then
    {$ELSE}
      if ExpandFileName(Git(Root, ['rev-parse', '--show-toplevel'])) <> Root then
    {$ENDIF}
        raise Exception.Create('Source folder is not the repository root');
      Commit := Git(Root, ['rev-parse', '--verify', 'HEAD']);
      Revision := Git(Root, ['describe', '--tags', '--always']);
      Dirty := Git(Root, ['status', '--porcelain', '--untracked-files=no']) <> '';
      ChangesKnown:=True;
    except
      Commit:=CheckoutCommit(Root);
      if (Commit='') and HexCommit(ArchiveCommit) then Commit:=ArchiveCommit;
      if Commit='' then Commit := 'unavailable (source archive)';
      Revision := 'source build';
      Dirty := False;ChangesKnown:=False;
    end;
    Manual := StringReplace(ReadText(Root + DirectorySeparator + 'MANUAL.md'), #13#10, #10, [rfReplaceAll]);
    Manual := StringReplace(Manual, #13, #10, [rfReplaceAll]);
    if not ForceDirectories(ExtractFileDir(OutputName)) then
      raise Exception.Create('Cannot create build information directory');
    ResourceDirectory:=ExtractFileDir(OutputName)+DirectorySeparator+'resources';
    if not ForceDirectories(ResourceDirectory) then
      raise Exception.Create('Cannot create manual resource directory');
    CompileManual(ResourceDirectory,Compiler,Manual);
    Text := '{$R ' + Quoted(ResourceDirectory+DirectorySeparator+'gwdgui-manual.res') + '}' + #10 + 'const' + #10 + '  BuildCommit = ' + Quoted(Commit) + ';' + #10 +
      '  BuildRevision = ' + Quoted(Revision) + ';' + #10 +
      '  BuildHasChanges = ' + BoolToStr(Dirty, True) + ';' + #10 +
      '  BuildChangesKnown = ' + BoolToStr(ChangesKnown,True) + ';' + #10;
    WriteText(OutputName,Text);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.Message);
      Halt(1);
    end;
  end;
end.
