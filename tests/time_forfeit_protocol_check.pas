program time_forfeit_protocol_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF}Classes,SysUtils,uGameRunnerThread,uGameSetupTypes,uGameOrchestrator,
 uTimeForfeit,uEngineBase,uEngineRegistry,uChessUciEngine,uDraughtsHubEngine,uGamePosition,
 uChessPosition,uDraughtsPosition,uDraughtsBoard,uEngineParamsJson;
var Chess,Draughts:TGameVariant;Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Peer;
var L,Mode,Fen,Raw,W,B,Move:string;Words:TStringList;P:TGamePosition;I,N:Integer;Budget:Double;
begin
 Mode:=ParamStr(2);Words:=TStringList.Create;Budget:=0;Move:='';
 if Mode='uci' then P:=Chess.CreatePosition else P:=Draughts.CreatePosition;
 try while not EOF(Input) do begin
  ReadLn(L);
  if L='uci' then begin WriteLn('id name Forfeit peer');WriteLn('uciok');end
  else if L='hub' then begin WriteLn('id name=Forfeit version=1');WriteLn('wait');end
  else if L='init' then WriteLn('ready') else if L='isready' then WriteLn('readyok')
  else if Copy(L,1,9)='position ' then begin
   Words.Clear;ExtractStrings([' '],[],PChar(L),Words);N:=Words.IndexOf('moves');Fen:='';
   if Words[1]='startpos' then Fen:=Chess.DefaultStartingFEN else
    for I:=2 to 7 do begin if I>2 then Fen+=' ';Fen+=Words[I];end;
   P.LoadFromFEN(Fen);if N>=0 then for I:=N+1 to Words.Count-1 do P.PlayMove(Words[I]);
  end else if Copy(L,1,4)='pos ' then begin
   Raw:=ExtractHubArgument(L,'pos');W:='';B:='';
   for I:=2 to Length(Raw) do begin
    if Raw[I] in ['w','W'] then begin if W<>'' then W+=',';if Raw[I]='W' then W+='K';W+=IntToStr(I-1);end;
    if Raw[I] in ['b','B'] then begin if B<>'' then B+=',';if Raw[I]='B' then B+='K';B+=IntToStr(I-1);end;
   end;P.LoadFromFEN(Raw[1]+':W'+W+':B'+B);
  end else if Copy(L,1,6)='level ' then TryStrToFloat(ExtractHubArgument(L,'time'),Budget)
  else if Copy(L,1,3)='go ' then begin
   Move:=P.LegalMove(0);
   if Mode='uci' then begin
    if Pos('movetime',L)>0 then begin WriteLn('info depth 5 score cp 300 pv '+Move);
      if ParamStr(3)='hold' then begin W:=ParamStr(4);with TStringList.Create do try Text:='search';SaveToFile(W);finally Free;end;end
      else WriteLn('bestmove '+Move);end;
   end else if Budget>=0.5 then begin WriteLn('info depth=5 score=3.0 pv="'+Move+'"');
     if ParamStr(3)='hold' then begin W:=ParamStr(4);with TStringList.Create do try Text:='search';SaveToFile(W);finally Free;end;end
     else WriteLn('done move='+Move);end;
  end else if L='stop' then begin if Mode='uci' then WriteLn('bestmove '+Move) else WriteLn('done move='+Move);end
  else if L='quit' then Break;
  Flush(Output);
 end;finally Words.Free;P.Free;end;
end;
type TCapture=class
 Last:TGameRunnerSnapshot;
 procedure Snapshot(Sender:TObject;S:TGameRunnerSnapshot);
 end;
procedure TCapture.Snapshot(Sender:TObject;S:TGameRunnerSnapshot);
begin Last.Free;Last:=S;end;
procedure Run(V:TGameVariant;Kind:TExternalEngineKind;Black:Boolean;Cancel:Boolean=False);
var Setup:TGameSetup;Runner:TGameRunnerThread;Capture:TCapture;Tick:QWord;Fen,Mode,SignalFile:string;P:TGamePosition;
begin
 if Kind=eekUci then Mode:='uci' else Mode:='hub';
 Setup:=Default(TGameSetup);Setup.Variant:=V;Setup.ForcePonderOff:=True;
 Setup.WhitePlayer:=pkRegistered;Setup.BlackPlayer:=pkRegistered;
 Setup.WhiteEngine:=TExternalEngineDefinition.Create;Setup.BlackEngine:=TExternalEngineDefinition.Create;
 Setup.WhiteEngine.Kind:=Kind;Setup.WhiteEngine.ExePath:=ExpandFileName(ParamStr(0));Setup.WhiteEngine.Arguments:='--peer '+Mode+' white';
 if Cancel then begin
  SignalFile:=GetTempDir+'zgui-forfeit-cancel-'+IntToStr(GetProcessID)+'-'+Mode;DeleteFile(SignalFile);
  Setup.WhiteEngine.Arguments:='--peer '+Mode+' hold '+SignalFile;
 end;
 Setup.BlackEngine.Assign(Setup.WhiteEngine);Setup.BlackEngine.Arguments:='--peer '+Mode+' black';
 Setup.TimeControl.MinutesPerPeriod:=0.0002;Setup.StartingFEN:=V.DefaultStartingFEN;
 if Black then if Kind=eekUci then Setup.StartingFEN:=StringReplace(Setup.StartingFEN,' w ',' b ',[]) else Setup.StartingFEN[1]:='B';
 Setup.TimeForfeit:=DefaultTimeForfeit;Setup.TimeForfeit.EngineKey:=EngineIdentityKey(Setup.WhiteEngine);
 Setup.TimeForfeit.EngineName:='Protocol judge';Setup.TimeForfeitEngine:=Setup.WhiteEngine;
 P:=V.CreatePosition;try P.LoadFromFEN(Setup.StartingFEN);Fen:=P.ToFEN;finally P.Free;end;
 Capture:=TCapture.Create;Runner:=TGameRunnerThread.Create(Setup,1,@Capture.Snapshot,nil);
 try
  Runner.Start;Tick:=GetTickCount64;
  while not Runner.Finished and (GetTickCount64-Tick<12000) do begin
    if Cancel and FileExists(SignalFile) then Runner.PostStop;
    CheckSynchronize(10);Sleep(5);
  end;
  if not Runner.Finished then Runner.PostStop;Runner.WaitFor;
  Check(Capture.Last<>nil,'Runner publishes final adjudication');
  if (Capture.Last.GameResult='*') and not Cancel then WriteLn(Capture.Last.LogLines.Text);
  if Cancel then Check((Capture.Last.GameResult='*') and FileExists(SignalFile),'Stop cancels active adjudicator without declaring a result')
  else if Black then begin Check(Capture.Last.GameResult=V.ResultText(goBlackWins),'Black-to-move scores normalized to White perspective');Check(Pos('-300 <= -200',Capture.Last.GameEndReason)>0,'Negative score reason');end
  else begin Check(Capture.Last.GameResult=V.ResultText(goWhiteWins),'Positive score reverses default time forfeit');Check(Pos('300 >= 200',Capture.Last.GameEndReason)>0,'Positive score reason');end;
  Check((Capture.Last.PlyCount=0) and (Capture.Last.Position.ToFEN=Fen),'Final board and game tree exclude adjudicator move');
 finally Runner.Free;Capture.Last.Free;Capture.Free;Setup.WhiteEngine.Free;Setup.BlackEngine.Free;end;
end;
begin
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 try
  if ParamStr(1)='--peer' then Peer else begin
   Run(Chess,eekUci,False);Run(Chess,eekUci,True);Run(Draughts,eekHub,False);Run(Draughts,eekHub,True);
   Run(Chess,eekUci,False,True);Run(Draughts,eekHub,False,True);
   WriteLn('Time forfeit protocol checks passed: ',Checks);
  end;
 finally Chess.Free;Draughts.Free;end;
end.
