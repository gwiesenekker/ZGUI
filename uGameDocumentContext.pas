unit uGameDocumentContext;
{$mode objfpc}{$H+}
// Format detection chooses a candidate. Existing readers/preflights remain the
// sole validators; no game parsing or database migration is implemented here.
interface
uses SysUtils,uGamePosition,uGameGuiProfile,uGameTreePdn;
function VariantForFormat(Format:TGameFileFormat;Fallback:TGameVariant):TGameVariant;
function GameFileCandidate(const Name:string;Fallback:TGameVariant):TGameVariant;
function DatabaseFileVariant(const Name:string;Fallback:TGameVariant):TGameVariant;
function TournamentFileVariant(const Name:string;Fallback:TGameVariant):TGameVariant;
implementation
uses Classes,uGameDatabase,uTournamentStorage,fpjson;
function VariantForFormat(Format:TGameFileFormat;Fallback:TGameVariant):TGameVariant;
begin
  if RegisteredGameCount>1 then begin
    if Format=gffPgn then Exit(GameVariantById('chess')) else Exit(GameVariantById('draughts'));
  end;
  if (Fallback<>nil) and (GameGuiProfileFor(Fallback).FileFormat=Format) then Exit(Fallback);
  raise EGamePositionError.Create('This game is not registered');
end;
function GameFileCandidate(const Name:string;Fallback:TGameVariant):TGameVariant;
var Ext,Head:string;Stream:TFileStream;Size:Integer;
begin
  Ext:=LowerCase(ExtractFileExt(Name));
  if Ext='.pgn' then Exit(VariantForFormat(gffPgn,Fallback));
  if Ext='.pdn' then Exit(VariantForFormat(gffPdn,Fallback));
  Stream:=TFileStream.Create(Name,fmOpenRead or fmShareDenyNone);
  try Size:=Stream.Size;if Size>16384 then Size:=16384;SetLength(Head,Size);if Size>0 then Stream.ReadBuffer(Head[1],Size);finally Stream.Free;end;
  Head:=UpperCase(Head);
  if (Pos('[FEN "W:',Head)>0) or (Pos('[FEN "B:',Head)>0) or (Pos('[GAMETYPE "20',Head)>0) then
    Exit(VariantForFormat(gffPdn,Fallback));
  if (Pos('[FEN "',Head)>0) and (Pos('/',Head)>0) then Exit(VariantForFormat(gffPgn,Fallback));
  if RegisteredGameCount<2 then Exit(Fallback);
  Result:=nil; // unknown extension without decisive game metadata: explicit choice
end;
function DatabaseFileVariant(const Name:string;Fallback:TGameVariant):TGameVariant;
var Format:TGameFileFormat;Probe:TGameDatabase;Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Name,fmOpenRead or fmShareDenyNone);
  try if Stream.Size=0 then raise EConvertError.Create('Empty file is not a game database');finally Stream.Free;end;
  for Format:=Low(Format) to High(Format) do begin
    Probe:=TGameDatabase.Create(Format);
    try
      try Probe.ValidateDatabaseFile(Name);except on E:Exception do Continue;end;
      Exit(VariantForFormat(Format,Fallback));
    finally Probe.Free;end;
  end;
  raise EConvertError.Create('Unsupported game database: schema, columns or metadata do not match');
end;
function TournamentFileVariant(const Name:string;Fallback:TGameVariant):TGameVariant;
var Format:TGameFileFormat;Probe:TJSONObject;
begin
  for Format:=Low(Format) to High(Format) do begin
    Probe:=nil;
    try
      try Probe:=ReadTournamentDocument(Name,Format);except on E:Exception do Continue;end;
      Exit(VariantForFormat(Format,Fallback));
    finally Probe.Free;end;
  end;
  raise EConvertError.Create('Unsupported or invalid tournament document');
end;
end.
