unit uTournamentFileLocks;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
type
  { GUI-thread-owned leases. Sidecars remain on disk: OS locks, not PID text,
    establish ownership. Never unlink a live flock inode. }
  TTournamentFileLocks = class
  private
    FPaths: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Acquire(const FileName: string);
    procedure KeepOnly(const JsonFile, Publication: string);
  end;
implementation
uses LazFileUtils, LazUTF8{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF}{$IFDEF MSWINDOWS}, Windows{$ENDIF};
type
  TLease = class
    Handle: THandle;
    References: Integer;
  end;
var Leases: TStringList;
function Canonical(const Name: string): string;
begin
  if Name='' then Exit('');
  Result:=GetPhysicalFilename(ExpandFileName(Name),pfeOriginal);
  {$IFDEF MSWINDOWS}Result:=UTF8LowerCase(Result);{$ENDIF}
end;
procedure ReleasePath(const Name:string);
var I:Integer;L:TLease;
begin
  I:=Leases.IndexOf(Name);if I<0 then Exit;
  L:=TLease(Leases.Objects[I]);Dec(L.References);
  if L.References=0 then begin FileClose(L.Handle);L.Free;Leases.Delete(I);end;
end;
constructor TTournamentFileLocks.Create;
begin inherited Create;FPaths:=TStringList.Create;end;
destructor TTournamentFileLocks.Destroy;
var I:Integer;
begin
  for I:=0 to FPaths.Count-1 do ReleasePath(FPaths[I]);
  FPaths.Free;inherited Destroy;
end;
procedure TTournamentFileLocks.Acquire(const FileName:string);
var Name,Sidecar,Info:string;I:Integer;H:THandle;L:TLease;
begin
  Name:=Canonical(FileName);if (Name='') or (FPaths.IndexOf(Name)>=0) then Exit;
  I:=Leases.IndexOf(Name);
  if I>=0 then L:=TLease(Leases.Objects[I])
  else begin
    Sidecar:=Name+'.lock';
    {$IFDEF UNIX}
    H:=fpOpen(PChar(Sidecar),O_RDWR or O_CREAT,&600);
    if H<>THandle(-1) then begin
      fpFcntl(H,F_SETFD,1) { FD_CLOEXEC };
      if fpFlock(H,LOCK_EX or LOCK_NB)<>0 then begin FileClose(H);H:=THandle(-1);end;
    end;
    {$ELSE}
    H:=CreateFileW(PWideChar(UTF8Decode(Sidecar)),GENERIC_READ or GENERIC_WRITE,
      FILE_SHARE_READ,nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
    {$ENDIF}
    if H=THandle(-1) then raise EInvalidOperation.Create(
      'Cannot exclusively open tournament file: '+FileName+LineEnding+
      'It may be open in another ZGUI, or the directory may not be writable.');
    L:=TLease.Create;L.Handle:=H;L.References:=0;
    Info:='ZGUI PID '+IntToStr(GetProcessID)+' host '+GetEnvironmentVariable('HOSTNAME')+
      GetEnvironmentVariable('COMPUTERNAME')+LineEnding;
    FileSeek(H,0,fsFromBeginning);FileWrite(H,Info[1],Length(Info));
    Leases.AddObject(Name,L);
  end;
  Inc(L.References);FPaths.Add(Name);
end;
procedure TTournamentFileLocks.KeepOnly(const JsonFile,Publication:string);
var I:Integer;A,B:string;
begin
  A:=Canonical(JsonFile);B:=Canonical(Publication);
  for I:=FPaths.Count-1 downto 0 do if (FPaths[I]<>A) and (FPaths[I]<>B) then begin
    ReleasePath(FPaths[I]);FPaths.Delete(I);
  end;
end;
initialization
  Leases:=TStringList.Create;
finalization
  Leases.Free;
end.
