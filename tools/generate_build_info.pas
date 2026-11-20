program GenerateBuildInfo;
{$mode objfpc}{$H+}{$codepage utf8}
uses Classes, SysUtils, Process
  {$IFDEF MSWINDOWS}, Windows, ShellApi{$ENDIF};

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
    Dirty: Boolean;
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
    except
      Commit := 'unavailable (source archive)';
      Revision := 'source build';
      Dirty := False;
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
      '  BuildHasChanges = ' + BoolToStr(Dirty, True) + ';' + #10;
    WriteText(OutputName,Text);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, E.Message);
      Halt(1);
    end;
  end;
end.
