unit uTournamentResults;

{$mode objfpc}{$H+}

interface

uses uGameTreePdn;

type
  TTournamentResult = (trUnknown, trWhiteWin, trDraw, trBlackWin);

function ParseTournamentResult(const AText: string; AFormat:TGameFileFormat=gffPdn): TTournamentResult;
function TournamentResultIsKnown(AResult: TTournamentResult): Boolean;
function TournamentResultPointsForBlack(AResult: TTournamentResult): Integer;
function TournamentResultPointsForWhite(AResult: TTournamentResult): Integer;

function TournamentResultText(AResult:TTournamentResult;AFormat:TGameFileFormat=gffPdn):string;
implementation

uses
  SysUtils;

function ParseTournamentResult(const AText: string; AFormat:TGameFileFormat): TTournamentResult;
var
  Text: string;
begin
  Text := Trim(AText);
  if AFormat=gffPgn then begin
    if Text='1-0' then Exit(trWhiteWin);
    if Text='1/2-1/2' then Exit(trDraw);
    if Text='0-1' then Exit(trBlackWin);
    Exit(trUnknown);
  end;
  if SameText(Text, '2-0') then
    Result := trWhiteWin
  else if SameText(Text, '1-1') then
    Result := trDraw
  else if SameText(Text, '0-2') then
    Result := trBlackWin
  else
    Result := trUnknown;
end;

function TournamentResultText(AResult:TTournamentResult;AFormat:TGameFileFormat):string;
begin
  Result:='*';
  if AFormat=gffPgn then case AResult of
    trWhiteWin:Result:='1-0';trDraw:Result:='1/2-1/2';trBlackWin:Result:='0-1';
  end else case AResult of
    trWhiteWin:Result:='2-0';trDraw:Result:='1-1';trBlackWin:Result:='0-2';
  end;
end;
function TournamentResultIsKnown(AResult: TTournamentResult): Boolean;
begin
  Result := AResult <> trUnknown;
end;

function TournamentResultPointsForBlack(AResult: TTournamentResult): Integer;
begin
  case AResult of
    trDraw:
      Result := 1;
    trBlackWin:
      Result := 2;
  else
    Result := 0;
  end;
end;

function TournamentResultPointsForWhite(AResult: TTournamentResult): Integer;
begin
  case AResult of
    trWhiteWin:
      Result := 2;
    trDraw:
      Result := 1;
  else
    Result := 0;
  end;
end;

end.
