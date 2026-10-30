unit uGameGuiProfile;
{$mode objfpc}{$H+}
{ Composition policy belongs to the GUI, never to the game rules contract. }
interface
uses Classes, uGamePosition, uGameBoardControl, uGameTreePdn, uGameFileReader, uEngineRegistry, uGameOrchestrator, uPositionSetupAdapter;
type
  TGuiGameFeature=(gfPdn,gfPositionSetup,gfDatabase,gfTournament,gfEngines,gfNewGame,gfAutoPlay,gfMcts);
  TGuiGameFeatures=set of TGuiGameFeature;
  TGameBoardClass=class of TGameBoardControl;
  TGameGuiProfile=record
    TournamentForcePonderOff: Boolean;
    AutoPlayStopsOnOutcome:Boolean;
    DefaultClock: TTimeControl;
    Features: TGuiGameFeatures;
    EngineKinds: set of TExternalEngineKind;
    BoardClass: TGameBoardClass;
    SetupAdapterClass:TPositionSetupAdapterClass;
    SourceClickSingleMove: Boolean;
    FileFormat: TGameFileFormat;
    FormatName,FileFilter,FileExtension: string;
  end;
// Application registration owns its variants until ClearRegisteredGames, after
// all windows, runners and queued events have been released.
procedure RegisterGame(Variant:TGameVariant;const Profile:TGameGuiProfile);
procedure ClearRegisteredGames;
function RegisteredGameCount:Integer;
function RegisteredGame(Index:Integer):TGameVariant;
function GameVariantById(const Id:string):TGameVariant;
function GameVariantId(Variant:TGameVariant):string;
function GameForEngineKind(Kind:TExternalEngineKind):TGameVariant;
function ChessGuiProfile: TGameGuiProfile;
function DraughtsGuiProfile: TGameGuiProfile;
procedure RegisterGameGuiProfile(Variant: TGameVariant; const Profile: TGameGuiProfile);
function GameGuiProfileFor(Variant: TGameVariant): TGameGuiProfile;
function CreateProfileReader(const Profile: TGameGuiProfile; Variant: TGameVariant): TGameFileReader;
implementation
uses SysUtils, Contnrs, uChessPosition, uChessBoardControl, uDraughtsPosition, uDraughtsBoardControl,
  uChessPgn, uPdnFileReader,uChessPositionSetupAdapter,uDraughtsPositionSetupAdapter;
type TRegisteredGame=class
  Variant:TGameVariant;Profile:TGameGuiProfile;Owned:Boolean;
  destructor Destroy;override;
end;
var Games:TObjectList=nil;
destructor TRegisteredGame.Destroy;
begin if Owned then Variant.Free;inherited Destroy;end;
procedure ClearRegisteredGames;
begin FreeAndNil(Games);end;
function RegisteredGameCount:Integer;
var I:Integer;
begin Result:=0;if Games<>nil then for I:=0 to Games.Count-1 do if TRegisteredGame(Games[I]).Owned then Inc(Result);end;
function RegisteredGame(Index:Integer):TGameVariant;
var I:Integer;
begin
  if Games<>nil then for I:=0 to Games.Count-1 do if TRegisteredGame(Games[I]).Owned then begin
    if Index=0 then Exit(TRegisteredGame(Games[I]).Variant);Dec(Index);
  end;
  raise EGamePositionError.Create('Invalid registered game index');
end;
function GameVariantId(Variant:TGameVariant):string;
begin
  if Variant is TChessVariant then Exit('chess');
  if Variant is TDraughtsVariant then Exit('draughts');
  if Variant=nil then raise EGamePositionError.Create('Missing game variant');
  Result:=LowerCase(Variant.Name);
end;
function GameVariantById(const Id:string):TGameVariant;
var I:Integer;
begin
  for I:=0 to RegisteredGameCount-1 do if SameText(GameVariantId(RegisteredGame(I)),Id) then Exit(RegisteredGame(I));
  raise EGamePositionError.Create('Unregistered game: '+Id);
end;
function GameForEngineKind(Kind:TExternalEngineKind):TGameVariant;
var I:Integer;Entry:TRegisteredGame;
begin
  if Games<>nil then for I:=0 to Games.Count-1 do begin
    Entry:=TRegisteredGame(Games[I]);
    if Entry.Owned and (Kind in Entry.Profile.EngineKinds) then Exit(Entry.Variant);
  end;
  raise EGamePositionError.Create('No game registered for engine protocol');
end;
procedure RegisterGame(Variant:TGameVariant;const Profile:TGameGuiProfile);
var I:Integer;Entry:TRegisteredGame;
begin
  if Variant=nil then raise EGamePositionError.Create('Missing game registration');
  if Games<>nil then for I:=0 to Games.Count-1 do begin
    Entry:=TRegisteredGame(Games[I]);
    if Entry.Owned and ((GameVariantId(Entry.Variant)=GameVariantId(Variant)) or
      ((Entry.Profile.EngineKinds*Profile.EngineKinds)<>[])) then
      raise EGamePositionError.Create('Duplicate game or overlapping engine protocols');
  end;
  if Games=nil then Games:=TObjectList.Create(True);
  Entry:=TRegisteredGame.Create;Entry.Variant:=Variant;Entry.Profile:=Profile;Entry.Owned:=True;Games.Add(Entry);
end;
function ChessGuiProfile: TGameGuiProfile;
begin
  Result.SetupAdapterClass:=TChessPositionSetupAdapter;
  Result.TournamentForcePonderOff:=True;
  Result.AutoPlayStopsOnOutcome:=True;
  Result.DefaultClock:=DefaultTimeControl; Result.DefaultClock.MovesPerPeriod:=0;
  Result.DefaultClock.MinutesPerPeriod:=5; Result.DefaultClock.IncrementSeconds:=3;
  Result.Features:=[gfPdn,gfEngines,gfNewGame,gfTournament,gfPositionSetup,gfDatabase,gfAutoPlay]; Result.EngineKinds:=[eekUci]; Result.BoardClass:=TChessBoardControl;
  Result.SourceClickSingleMove:=False; Result.FileFormat:=gffPgn;
  Result.FormatName:='PGN'; Result.FileFilter:='PGN files (*.pgn)|*.pgn|All files (*)|*'; Result.FileExtension:='pgn';
end;
function DraughtsGuiProfile: TGameGuiProfile;
begin
  Result.SetupAdapterClass:=TDraughtsPositionSetupAdapter;
  Result.TournamentForcePonderOff:=False;
  Result.AutoPlayStopsOnOutcome:=False;
  Result.DefaultClock:=DefaultTimeControl;
  Result.Features:=[Low(TGuiGameFeature)..High(TGuiGameFeature)]; Result.EngineKinds:=[eekHub,eekDxp]; Result.BoardClass:=TDraughtsBoardControl;
  Result.SourceClickSingleMove:=True; Result.FileFormat:=gffPdn;
  Result.FormatName:='PDN'; Result.FileFilter:='PDN files (*.pdn)|*.pdn|All files (*)|*'; Result.FileExtension:='pdn';
end;
procedure RegisterGameGuiProfile(Variant: TGameVariant; const Profile: TGameGuiProfile);
var I:Integer;Entry:TRegisteredGame;
begin
  if Variant=nil then begin
    if Games<>nil then for I:=Games.Count-1 downto 0 do if not TRegisteredGame(Games[I]).Owned then Games.Delete(I);
    Exit;
  end;
  if Games<>nil then for I:=0 to Games.Count-1 do if TRegisteredGame(Games[I]).Variant=Variant then begin
    TRegisteredGame(Games[I]).Profile:=Profile;Exit;
  end;
  if Games=nil then Games:=TObjectList.Create(True);
  Entry:=TRegisteredGame.Create;Entry.Variant:=Variant;Entry.Profile:=Profile;Games.Add(Entry);
end;
function GameGuiProfileFor(Variant: TGameVariant): TGameGuiProfile;
var I:Integer;
begin
  if Games<>nil then for I:=0 to Games.Count-1 do if TRegisteredGame(Games[I]).Variant=Variant then Exit(TRegisteredGame(Games[I]).Profile);
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
finalization
  ClearRegisteredGames;
end.
