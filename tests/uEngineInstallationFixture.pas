unit uEngineInstallationFixture;
{$mode objfpc}{$H+}
interface
function InstallEngineFixture(const Source,Name:string):string;
implementation
uses Classes,SysUtils{$IFDEF UNIX},BaseUnix{$ENDIF};
function InstallEngineFixture(const Source,Name:string):string;
var Directory,Script:string;Input,Output:TFileStream;
begin
 Directory:=IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))))+
  'installation-fixtures'+DirectorySeparator+Name;
 if not ForceDirectories(Directory) then raise Exception.Create('Cannot create engine fixture directory');
 {$IFDEF UNIX}
 // Each registration has its own executable file and working directory. The
 // small peer launcher delegates test behavior to this test program, not to an
 // installed user engine. Avoid copying large GUI test binaries repeatedly.
 Result:=Directory+DirectorySeparator+ExtractFileName(Source);
 Script:='#!/bin/sh'+#10+'exec '+#39+
  StringReplace(ExpandFileName(Source),#39,#39+#34+#39+#34+#39,[rfReplaceAll])+#39+' "$@"'+#10;
 Output:=TFileStream.Create(Result,fmCreate);
 try Output.WriteBuffer(Script[1],Length(Script));finally Output.Free;end;
 if fpChmod(PChar(Result),&755)<>0 then raise Exception.Create('Cannot mark engine fixture executable');
 {$ELSE}
 Result:=Directory+DirectorySeparator+ExtractFileName(Source);
 Input:=TFileStream.Create(Source,fmOpenRead or fmShareDenyNone);
 try Output:=TFileStream.Create(Result,fmCreate);
  try Output.CopyFrom(Input,0);finally Output.Free;end;
 finally Input.Free;end;
 {$ENDIF}
end;
end.
