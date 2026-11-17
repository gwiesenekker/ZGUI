program runner_engine_release_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}Classes,SysUtils,uGameRunnerThread,uGameSetupTypes,
 uGameOrchestrator,uEngineBase,uEngineRegistry,uProcessEngineWorker,uGamePosition,
 uChessPosition,uDraughtsPosition;
var Checks,LiveAdapters,IdleCalls:LongInt;
procedure Check(B:Boolean;const Text:string);
begin Inc(Checks);if not B then raise Exception.Create(Text);end;
type
 TPeer=class(TGameEngine)
 private Worker:TProcessEngineWorker;
  procedure ExecuteCommand(Command:TObject);
  procedure Idle;
 protected function DoStartThinking:string;override;
 public constructor Create(const Name:string='Engine');override;
  destructor Destroy;override;
  function LaunchAndInit:Boolean;override;
 end;
 TCapture=class
  Last:TGameRunnerSnapshot;
  procedure Snapshot(Sender:TObject;Value:TGameRunnerSnapshot);
 end;
constructor TPeer.Create(const Name:string);
begin
 inherited Create(Name);InterlockedIncrement(LiveAdapters);
 Worker:=TProcessEngineWorker.Create(@ExecuteCommand,nil,nil,'test',@Idle);
end;
destructor TPeer.Destroy;
begin Worker.Free;InterlockedDecrement(LiveAdapters);inherited Destroy;end;
procedure TPeer.ExecuteCommand(Command:TObject);
begin end;
procedure TPeer.Idle;
begin InterlockedIncrement(IdleCalls);end;
function TPeer.LaunchAndInit:Boolean;
begin Result:=True;end;
function TPeer.DoStartThinking:string;
var P:TGamePosition;
begin
 P:=DefaultGameVariant.CreatePosition;
 try PublishSearchInfo(P.LegalMove(0),'0.25','8','0.01');finally P.Free;end;
 SetGameResult(DefaultGameVariant.ResultText(goDraw),'Draw claimed');Result:='';
end;
function Factory(Definition:TExternalEngineDefinition):TGameEngine;
begin Result:=TPeer.Create('finished peer');end;
procedure TCapture.Snapshot(Sender:TObject;Value:TGameRunnerSnapshot);
begin try Last.AssignFrom(Value);finally Value.Free;end;end;
procedure Run(V:TGameVariant;Kind:TExternalEngineKind);
const Games=160;
var Setup:TGameSetup;Runners:array[0..Games-1] of TGameRunnerThread;
 Captures:array[0..Games-1] of TCapture;I,N:Integer;Tick,CloseTick:QWord;
begin
 RegisterDefaultGameVariant(V);RegisterGameEngineFactory(Kind,@Factory);
 Setup:=Default(TGameSetup);Setup.Variant:=V;Setup.StartingFEN:=V.DefaultStartingFEN;
 Setup.TimeControl.MinutesPerPeriod:=1;Setup.WhitePlayer:=pkRegistered;Setup.BlackPlayer:=pkRegistered;
 Setup.WhiteEngine:=TExternalEngineDefinition.Create;Setup.WhiteEngine.Kind:=Kind;
 Setup.BlackEngine:=TExternalEngineDefinition.Create;Setup.BlackEngine.Kind:=Kind;
 for I:=0 to Games-1 do begin Runners[I]:=nil;Captures[I]:=nil;end;
 try
  for I:=0 to Games-1 do begin
   Captures[I]:=TCapture.Create;Captures[I].Last:=TGameRunnerSnapshot.Create;
   Runners[I]:=TGameRunnerThread.Create(Setup,I+1,@Captures[I].Snapshot,nil);
   Runners[I].Start;Tick:=GetTickCount64;
   while not Runners[I].Finished and (GetTickCount64-Tick<5000) do begin CheckSynchronize(1);Sleep(1);end;
   Check(Runners[I].Finished,'Runner terminates');Runners[I].WaitFor;
   Check(LiveAdapters=0,'Finished history holds no engine adapters/workers');
   Check(Captures[I].Last.State=gosGameOver,'Finished snapshot retains game state');
   Check(Captures[I].Last.GameResult=V.ResultText(goDraw),'Finished snapshot retains result');
   Check(Captures[I].Last.EngineEndReason='Draw claimed','Finished snapshot retains engine reason');
   Check(Captures[I].Last.PrincipalVariation<>'','Finished snapshot retains PV');
   Check(Captures[I].Last.PvScore='0.25','Finished snapshot retains score');
  end;
  N:=IdleCalls;Sleep(150);Check(IdleCalls=N,'No idle worker polling remains after completion');
  CloseTick:=GetTickCount64;
  for I:=0 to Games-1 do FreeAndNil(Runners[I]);
  WriteLn(V.Name,': ',Games,' retained completed games released in ',GetTickCount64-CloseTick,' ms; live adapters=',LiveAdapters);
 finally
  for I:=0 to Games-1 do begin
   if Runners[I]<>nil then begin Runners[I].PostStop;Runners[I].WaitFor;Runners[I].Free;end;
   if Captures[I]<>nil then begin Captures[I].Last.Free;Captures[I].Free;end;
  end;
  Setup.BlackEngine.Free;Setup.WhiteEngine.Free;
 end;
end;
var Chess,Draughts:TGameVariant;
begin
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 try Run(Chess,eekUci);Run(Draughts,eekHub);
 finally RegisterDefaultGameVariant(nil);Chess.Free;Draughts.Free;end;
 WriteLn('Finished-engine release checks passed: ',Checks);
end.
