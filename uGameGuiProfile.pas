unit uGameGuiProfile;
{$mode objfpc}{$H+}
{ Composition policy belongs to the GUI, never to the game rules contract. }
interface
uses Classes, uGamePosition, uGameBoardControl, uGameTreePdn, uGameFileReader, uEngineRegistry, uGameOrchestrator;
type
  TGuiGameFeature=(gfPdn,gfPositionSetup,gfDatabase,gfTournament,gfEngines,gfNewGame,gfAutoPlay,gfMcts);
  TGuiGameFeatures=set of TGuiGameFeature;
  TGameBoardClass=class of TGameBoardControl;
  TGameGuiProfile=record
    DefaultClock: TTimeControl;
    Features: TGuiGameFeatures;
    EngineKinds: set of TExternalEngineKind;
    BoardClass: TGameBoardClass;
    SourceClickSingleMove: Boolean;
    FileFormat: TGameFileFormat;
    FormatName,FileFilter,FileExtension: string;
  end;
function ChessGuiProfile: TGameGuiProfile;
function DraughtsGuiProfile: TGameGuiProfile;
procedure RegisterGameGuiProfile(Variant: TGameVariant; const Profile: TGameGuiProfile);
function GameGuiProfileFor(Variant: TGameVariant): TGameGuiProfile;
function CreateProfileReader(const Profile: TGameGuiProfile; Variant: TGameVariant): TGameFileReader;
implementation
uses uChessPosition, uChessBoardControl, uDraughtsPosition, uDraughtsBoardControl,
  uChessPgn, uPdnFileReader;
var SelectedVariant: TGameVariant=nil; SelectedProfile: TGameGuiProfile;
function ChessGuiProfile: TGameGuiProfile;
begin
  Result.DefaultClock:=DefaultTimeControl; Result.DefaultClock.MovesPerPeriod:=0;
  Result.DefaultClock.MinutesPerPeriod:=5; Result.DefaultClock.IncrementSeconds:=3;
  Result.Features:=[gfPdn,gfEngines,gfNewGame]; Result.EngineKinds:=[eekUci]; Result.BoardClass:=TChessBoardControl;
  Result.SourceClickSingleMove:=False; Result.FileFormat:=gffPgn;
  Result.FormatName:='PGN'; Result.FileFilter:='PGN files (*.pgn)|*.pgn|All files (*)|*'; Result.FileExtension:='pgn';
end;
function DraughtsGuiProfile: TGameGuiProfile;
begin
  Result.DefaultClock:=DefaultTimeControl;
  Result.Features:=[Low(TGuiGameFeature)..High(TGuiGameFeature)]; Result.EngineKinds:=[eekHub,eekDxp]; Result.BoardClass:=TDraughtsBoardControl;
  Result.SourceClickSingleMove:=True; Result.FileFormat:=gffPdn;
  Result.FormatName:='PDN'; Result.FileFilter:='PDN files (*.pdn)|*.pdn|All files (*)|*'; Result.FileExtension:='pdn';
end;
procedure RegisterGameGuiProfile(Variant: TGameVariant; const Profile: TGameGuiProfile);
begin SelectedVariant:=Variant; SelectedProfile:=Profile; end;
function GameGuiProfileFor(Variant: TGameVariant): TGameGuiProfile;
begin
  if (SelectedVariant<>nil) and (SelectedVariant=Variant) then Exit(SelectedProfile);
  // Compatibility compositions (including the inherited draughts GUI tests).
  // All concrete-game choices are centralized here, including the board class.
  if Variant is TChessVariant then Exit(ChessGuiProfile);
  if Variant is TDraughtsVariant then Exit(DraughtsGuiProfile);
  raise EGamePositionError.Create('No GUI composition for '+Variant.Name);
end;
function CreateProfileReader(const Profile: TGameGuiProfile; Variant: TGameVariant): TGameFileReader;
begin
  case Profile.FileFormat of
    gffPgn:Result:=TChessPgnReader.Create(Variant);
    gffPdn:Result:=TPdnFileReader.Create;
  end;
end;
end.
