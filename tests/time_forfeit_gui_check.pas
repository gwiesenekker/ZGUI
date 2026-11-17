program time_forfeit_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}Interfaces,Forms,Controls,Classes,SysUtils,StdCtrls,ExtCtrls,Grids,FPJSON,JSONParser,
 uMainForm,uTournamentDialog,uTournamentGridModel,uTournamentStorage,uTimeForfeit,uGamePosition,uChessPosition,
 uDraughtsPosition,uGameGuiProfile,uEngineRegistry,uGameSetupTypes,uGuiDialogs,Dialogs,uEngineBase;
var Checks:Integer=0;Chess,Draughts:TGameVariant;Main:TMainForm;JudgeScore:string='3';Directory:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
type TMockEngine=class(TGameEngine)
 public Variant:TGameVariant;
 protected function DoStartThinking:string;override;
 public function LaunchAndInit:Boolean;override;function Capabilities:TEngineCapabilities;override;
 end;
function TMockEngine.LaunchAndInit:Boolean;
begin Result:=True;end;
function TMockEngine.Capabilities:TEngineCapabilities;
begin Result:=[ecAnalysis];end;
function TMockEngine.DoStartThinking:string;
var P:TGamePosition;M:TStringList;
begin
 if MoveTimeLimitMs<1000 then begin MarkMoveTimedOut;Exit('');end;
 P:=Variant.CreatePosition;M:=TStringList.Create;
 try P.LoadFromFEN(StartingFEN);P.CopyLegalMovesTo(M);Result:=M[0];LastScore:=JudgeScore;
 finally P.Free;M.Free;end;
end;
function Factory(D:TExternalEngineDefinition):TGameEngine;
begin
 Result:=TMockEngine.Create;
 if D.Kind=eekUci then TMockEngine(Result).Variant:=Chess else TMockEngine(Result).Variant:=Draughts;
end;
procedure RegisterEngines;
var E:TExternalEngineDefinition;L:TExternalEngineList;I:Integer;
begin
 L:=TExternalEngineList.Create;
 try for I:=0 to 5 do begin
  E:=TExternalEngineDefinition.Create;E.ExePath:=ExpandFileName(ParamStr(0));E.Arguments:='unused '+IntToStr(I);
  if I<3 then begin E.Kind:=eekUci;E.UciId:='Judge UCI '+IntToStr(I);end
  else begin E.Kind:=eekHub;E.HubId:='Judge Hub '+IntToStr(I);end;L.Add(E);
 end;SaveExternalEngines(EnginesJsonFileName,L);finally L.Free;end;
end;
function Response(const Command,Prefix:string):TJSONObject;
var Text:string;
begin
 Text:=Main.InteractiveCommand(Command);Check(Copy(Text,1,Length(Prefix)+1)=Prefix+' ',Command+' -> '+Text);
 Result:=TJSONObject(GetJSON(Copy(Text,Length(Prefix)+2,MaxInt)));
end;
procedure Pump;
begin Application.ProcessMessages;Main.TestDrainGuiEvents(True);Sleep(10);end;
procedure VariantCheck(V:TGameVariant;Base:Integer;const Name,Judge:string);
var J,Doc:TJSONObject;D:TTournamentDialog;Combo:TComboBox;G:TStringGrid;Id,I:Integer;Tick:QWord;L,Busy:TStringList;
 S:TGameSetup;Before,FileName:string;C:TTimeForfeitSettings;ReadOnly:TEdit;
begin
 J:=Response('run_tournament engine1_id='+IntToStr(Base)+' engine2_id='+IntToStr(Base+1)+
  ' time=0.01 increment=0 time_forfeit="'+Judge+'" adjudication_time=1.0 adjudication_threshold=200 allow_shared_executable=true','OK');
 try Id:=J.Get('tournament',0);finally J.Free;end;
 D:=Main.TournamentHost.Dialogs[Main.TournamentHost.Count-1];
 Check(D<>nil,'Real tournament tab');G:=TStringGrid(D.FindComponent('TournamentPairings'));
 Check(D.GameSetupForRow(1,S),'Existing shared setup');Busy:=TStringList.Create;
 try Main.CollectBusyEngineKeys(Busy);Check(Busy.IndexOf(S.TimeForfeit.EngineKey)>=0,'Adjudicator shares live cross-tournament reservations');finally Busy.Free;end;
 Combo:=TComboBox(D.FindComponent('TournamentTimeForfeit'));Check(Combo.ItemIndex>0,'CLI policy selected in GUI');
 Tick:=GetTickCount64;
 repeat
  Pump;J:=Response('query_tournament id='+IntToStr(Id),'OK');
  try if (J.Get('state','')='completed') and not D.IsRunning then Break;finally J.Free;end;
 until GetTickCount64-Tick>10000;
 if D.IsRunning then for I:=1 to G.RowCount-1 do WriteLn('Pending row: ',G.Cells[TournamentColResult,I],' ',G.Cells[TournamentColReason,I]);
 Check(not D.IsRunning,'Timeout games complete through existing runner');
 for I:=1 to G.RowCount-1 do begin
  Check(G.Cells[TournamentColResult,I]=V.ResultText(goWhiteWins),'Adjudication result overrides time loss in both colours');
  Check((Pos('Annotator ',G.Cells[TournamentColReason,I])=1) and (Pos('300 >= 200',G.Cells[TournamentColReason,I])>0) and (Pos(Judge,G.Cells[TournamentColReason,I])>0),'Reason contains engine and comparison');
 end;
 Check(D.GameSetupForRow(1,S) and (S.TimeForfeit.EngineKey=EngineIdentityKey(S.TimeForfeitEngine)),'Shared setup retains adjudicator');
 L:=TStringList.Create;
 try
  FileName:=Directory+'/'+Name+'.json';D.SaveTournamentToFile(FileName);L.LoadFromFile(FileName);Before:=L.Text;
  Doc:=TJSONObject(GetJSON(Before));try C:=ReadTimeForfeit(Doc.Find('time_forfeit'));Check(Doc.Get('storage_version',0)=5,'Adjudication policies use guarded version 5');Check((C.Seconds=1) and (C.ThresholdCp=200) and (C.EngineKey<>''),'Saved adjudication policy');finally Doc.Free;end;
  D.ResetForVariant(V);D.LoadTournamentFromFile(FileName);
  Combo:=TComboBox(D.FindComponent('TournamentTimeForfeit'));Check(Combo.ItemIndex>0,'Reload keeps adjudicator');
  ReadOnly:=TEdit(D.FindComponent('TournamentAdjudicationTime'));Check(ReadOnly.Enabled,'Adjudication edits enabled for engine policy');
  J:=D.SprtSnapshot;J.Free;L.LoadFromFile(FileName);Check(L.Text=Before,'Read-only reports leave policy and records unchanged');
  D.ResetForVariant(V);Check(Combo.ItemIndex=0,'New event defaults to Orchestrator');Check(not ReadOnly.Enabled,'Orchestrator disables adjudication edits');
 finally L.Free;end;
end;
var J:TJSONObject;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
 Directory:=GetTempDir+'zgui-forfeit-gui-'+IntToStr(GetProcessID);ForceDirectories(Directory);RegisterEngines;
 RegisterGameEngineFactory(eekUci,@Factory);RegisterGameEngineFactory(eekHub,@Factory);
 Main:=TMainForm.Create(nil);
 try
  J:=Response('list_engines','OK');J.Free;
  J:=Response('run_tournament engine1_id=1 engine2_id=2 time_forfeit=loss adjudication_time=1','ERROR');Check(J.Get('code','')='BAD_ARGUMENT','Analysis settings require adjudicator');J.Free;
  J:=Response('run_tournament engine1_id=1 engine2_id=2 time_forfeit="Judge Hub 3"','ERROR');Check(J.Get('code','')='GAME_MISMATCH','Cross-game adjudicator rejected');J.Free;
  J:=Response('run_tournament engine1_id=1 engine2_id=2 time_forfeit="Judge UCI 2" adjudication_threshold=0','ERROR');Check(J.Get('code','')='BAD_ARGUMENT','Zero threshold rejected');J.Free;
  VariantCheck(Chess,1,'chess','Judge UCI 2');VariantCheck(Draughts,4,'draughts','Judge Hub 3');
  GuiTestConfirmationResult:=mrNo;Check(Main.TournamentHost.PrepareCloseAll and Main.TournamentHost.FinishCloseAll,'Normal close lifecycle');
  WriteLn('Time forfeit GUI checks passed: ',Checks);
 finally Main.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
