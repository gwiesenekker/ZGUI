unit uEngineInstallation;
{$mode objfpc}{$H+}
interface
function InstallationPathKey(const Path:string):string;
implementation
uses SysUtils{$IFDEF UNIX},BaseUnix{$ENDIF}{$IFDEF MSWINDOWS},Windows{$ENDIF};
function InstallationPathKey(const Path:string):string;
var Full:string;
 {$IFDEF UNIX}Info:Stat;{$ENDIF}
 {$IFDEF MSWINDOWS}Handle:THandle;Info:TByHandleFileInformation;{$ENDIF}
begin
 if Path='' then Exit('');
 // Ask the OS about the original path before lexical normalization: collapsing
 // symlink/.. first could change which file the engine actually executes.
 Full:=Path;
 {$IFDEF UNIX}
 if fpStat(PChar(Full),Info)=0 then
  Exit('file-id:'+IntToStr(Info.st_dev)+':'+IntToStr(Info.st_ino));
 {$ENDIF}
 {$IFDEF MSWINDOWS}
 Handle:=CreateFileW(PWideChar(UTF8Decode(Full)),0,
  FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,nil,OPEN_EXISTING,
  FILE_FLAG_BACKUP_SEMANTICS,0);
 if Handle<>INVALID_HANDLE_VALUE then
  try if GetFileInformationByHandle(Handle,Info) then
   Exit('file-id:'+IntToStr(Info.dwVolumeSerialNumber)+':'+IntToStr(Info.nFileIndexHigh)+':'+IntToStr(Info.nFileIndexLow));
  finally CloseHandle(Handle);end;
 {$ENDIF}
 Full:=ExpandFileName(Path);
 if Length(Full)>Length(ExtractFileDrive(Full))+1 then Full:=ExcludeTrailingPathDelimiter(Full);
 {$IFDEF MSWINDOWS}Full:=LowerCase(Full);{$ENDIF}
 Result:='path:'+Full;
end;
end.
