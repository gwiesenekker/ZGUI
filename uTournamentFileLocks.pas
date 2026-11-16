unit uTournamentFileLocks;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
type
  ETournamentReadOnly = class(EInvalidOperation);
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
uses LazFileUtils, LazUTF8{$IFDEF UNIX}, BaseUnix, Unix{$ENDIF}{$IFDEF LINUX}, Linux{$ENDIF}{$IFDEF MSWINDOWS}, Windows{$ENDIF};
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
function UnlockedReadableSidecar(const Name:string):Boolean;
var H:THandle;
begin
  if not FileExists(Name) then Exit(True);
  {$IFDEF UNIX}
  H:=fpOpen(PChar(Name),O_RDONLY {$IFDEF LINUX}or O_CLOEXEC{$ENDIF});
  if H=THandle(-1) then Exit(False);
  {$IFNDEF LINUX}
  if fpFcntl(H,F_SETFD,1)<0 then begin FileClose(H);Exit(False);end;
  {$ENDIF}
  try Result:=fpFlock(H,LOCK_EX or LOCK_NB)=0;finally FileClose(H);end;
  {$ELSE}
  H:=CreateFileW(PWideChar(UTF8Decode(Name)),GENERIC_READ,FILE_SHARE_READ,nil,
    OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
  Result:=H<>THandle(-1);if Result then FileClose(H);
  {$ENDIF}
end;
procedure TTournamentFileLocks.Acquire(const FileName:string);
var Name,Sidecar,Info:string;I,OpenError:Integer;H:THandle;L:TLease;PermissionFailure:Boolean;
begin
  Name:=Canonical(FileName);if (Name='') or (FPaths.IndexOf(Name)>=0) then Exit;
  I:=Leases.IndexOf(Name);
  if I>=0 then L:=TLease(Leases.Objects[I])
  else begin
    Sidecar:=Name+'.lock';
    PermissionFailure:=False;
    {$IFDEF UNIX}
    H:=fpOpen(PChar(Sidecar),O_RDWR or O_CREAT {$IFDEF LINUX}or O_CLOEXEC{$ENDIF},&600);
    if H=THandle(-1) then begin
      OpenError:=fpGetErrno;
      PermissionFailure:=OpenError in [ESysEACCES,ESysEROFS];
    end else begin
      {$IFNDEF LINUX}
      if fpFcntl(H,F_SETFD,1)<0 then begin FileClose(H);
        raise EInvalidOperation.Create('Could not make tournament lock close-on-exec');end;
      {$ENDIF}
      if fpFlock(H,LOCK_EX or LOCK_NB)<>0 then begin FileClose(H);H:=THandle(-1);end;
    end;
    {$ELSE}
    H:=CreateFileW(PWideChar(UTF8Decode(Sidecar)),GENERIC_READ or GENERIC_WRITE,
      FILE_SHARE_READ,nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
    if H=THandle(-1) then begin
      OpenError:=GetLastError;PermissionFailure:=OpenError in [ERROR_ACCESS_DENIED,ERROR_WRITE_PROTECT];
    end;
    {$ENDIF}
    if H=THandle(-1) then begin
      { Permission failure may mean viewing an archive. Never fall back for a
        held lock, including an existing sidecar that cannot be inspected. }
      if PermissionFailure and UnlockedReadableSidecar(Sidecar) then
        raise ETournamentReadOnly.Create('Tournament directory is read-only: '+FileName);
      raise EInvalidOperation.Create('Cannot exclusively open tournament file: '+FileName+LineEnding+
        'It may be open in another ZGUI, or the directory may not be writable.');
    end;
    {$IFDEF UNIX}
    if fpAccess(PChar(ExtractFilePath(Name)),W_OK)<>0 then begin
    {$ELSE}
    if not DirectoryIsWritable(ExtractFilePath(Name)) then begin
    {$ENDIF}
      FileClose(H);raise ETournamentReadOnly.Create('Tournament directory is read-only: '+FileName);
    end;
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
