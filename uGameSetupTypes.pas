unit uGameSetupTypes;

{$mode objfpc}{$H+}

interface

uses uEngineRegistry, uGameOrchestrator, uGamePosition;

type
  TPlayerKind = (pkHuman, pkRegistered);

  TGameSetup = record
    Variant:TGameVariant; // Application-owned, outlives this setup and its runner.
    ForcePonderOff: Boolean;
    StartingFEN: string;
    WhitePlayer: TPlayerKind;
    BlackPlayer: TPlayerKind;
    WhiteEngine: TExternalEngineDefinition;
    BlackEngine: TExternalEngineDefinition;
    TimeControl: TTimeControl;
  end;

  TGameSetupAcceptedEvent = procedure(Sender: TObject; const ASetup: TGameSetup) of object;

function GameSetupVariant(const Setup:TGameSetup):TGameVariant;
procedure ValidateGameSetup(const Setup: TGameSetup; Variant: TGameVariant; Allowed: TExternalEngineKinds);
implementation
uses SysUtils, Math;
function GameSetupVariant(const Setup:TGameSetup):TGameVariant;
begin
  Result:=Setup.Variant;
  if Result=nil then Result:=DefaultGameVariant; // Legacy callers during migration.
end;
procedure ValidateGameSetup(const Setup: TGameSetup; Variant: TGameVariant; Allowed: TExternalEngineKinds);
var P: TGamePosition;
  procedure Player(Kind: TPlayerKind; Engine: TExternalEngineDefinition);
  begin
    if Kind<>pkRegistered then Exit;
    if (Engine=nil) or not (Engine.Kind in Allowed) then raise EConvertError.Create('Select a supported engine for this game');
    if EngineExecutableProblem(Engine)<>'' then raise EConvertError.Create(EngineExecutableProblem(Engine));
  end;
begin
  if (Setup.Variant<>nil) and (Setup.Variant<>Variant) then raise EConvertError.Create('Game setup variant mismatch');
  if (Setup.TimeControl.MovesPerPeriod<0) or IsNan(Setup.TimeControl.MinutesPerPeriod) or
    IsInfinite(Setup.TimeControl.MinutesPerPeriod) or (Setup.TimeControl.MinutesPerPeriod<=0) or
    (Setup.TimeControl.MinutesPerPeriod>MaxDouble/60) or IsNan(Setup.TimeControl.IncrementSeconds) or
    IsInfinite(Setup.TimeControl.IncrementSeconds) or (Setup.TimeControl.IncrementSeconds<0) then
    raise EConvertError.Create('Time control requires nonnegative moves/increment and positive finite minutes');
  Player(Setup.WhitePlayer,Setup.WhiteEngine); Player(Setup.BlackPlayer,Setup.BlackEngine);
  if (Setup.WhitePlayer=pkRegistered) and (Setup.BlackPlayer=pkRegistered) and
    (EngineIdentityKey(Setup.WhiteEngine)=EngineIdentityKey(Setup.BlackEngine)) then
    raise EConvertError.Create('Choose distinct engine registrations');
  P:=Variant.CreatePosition; try P.LoadFromFEN(Setup.StartingFEN); finally P.Free; end;
end;

end.
