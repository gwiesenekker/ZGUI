program uci_engine_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, SyncObjs, uChessUciEngine,
  uChessUciProtocol, uChessPosition, uGamePosition, uEngineBase, uEngineRegistry,
  uEngineParamsJson, uProcessEngineWorker;
var Checks: Integer=0;
procedure Check(OK: Boolean; const Text: string);
begin Inc(Checks); if not OK then raise Exception.Create(Text); end;
procedure Fake;
var Line,Mode,Move,PV: string; P: TChessPosition; Parts: TStringList; I,At: Integer; Active: Boolean;
begin
  Mode:=ParamStr(2); P:=TChessPosition.Create; Parts:=TStringList.Create; Active:=False; Move:='e2e4';
  try
    while not EOF(Input) do begin
      ReadLn(Line);
      if Line='uci' then begin
        if Mode='hang' then Continue;
        WriteLn('id name Deterministic UCI');
        WriteLn('option name hAsH type spin default 16 min 1 max 1024');
        WriteLn('option name Ponder type check default true');
        WriteLn('option name MultiPV type spin default 2 min 1 max 5');
        WriteLn('option name Style Choice type combo default Normal var Normal var Very Aggressive');
        WriteLn('option name File Path type string default <empty>');
        WriteLn('option name Clear Hash type button'); WriteLn('uciok');
      end else if Line='isready' then WriteLn('readyok')
      else if Copy(Line,1,9)='position ' then begin
        Parts.Clear; ExtractStrings([' '],[],PChar(Line),Parts); At:=Parts.IndexOf('moves');
        if Parts[1]='startpos' then P.LoadFromFEN(ChessStartingFEN)
        else begin PV:=''; for I:=2 to 7 do begin if I>2 then PV+=' '; PV+=Parts[I]; end; P.LoadFromFEN(PV); end;
        if At>=0 then for I:=At+1 to Parts.Count-1 do P.PlayMove(Parts[I]);
        if P.LegalMoveCount>0 then Move:=P.LegalMove(0) else Move:='0000';
      end else if Copy(Line,1,3)='go ' then begin
        Active:=True;
        if Mode='longline' then WriteLn(StringOfChar('x',70000));
        if Mode='mate' then WriteLn('info depth 5 score mate 3 pv '+Move)
        else begin
          WriteLn('info depth 1 time 12 score cp 10 pv '+Move);
          WriteLn('info depth 99 score cp 999 lowerbound pv '+Move);
          WriteLn('info multipv 2 depth 99 score cp 888 pv '+Move);
          if Mode<>'bound' then WriteLn('info depth 2 time 20 score cp 35 pv '+Move);
        end;
        if (Mode<>'nostop') and (Mode<>'bound') then begin
          WriteLn('bestmove '+Move+' ponder e7e5'); Active:=False;
          if Mode='duplicate' then WriteLn('bestmove '+Move);
        end;
      end else if (Line='stop') and Active then begin
        WriteLn('readyok'); // deliberately not a search completion acknowledgement
        if Mode<>'nostop' then begin WriteLn('bestmove '+Move); Active:=False; end;
      end else if Line='setoption name Clear Hash' then WriteLn('info string button pressed')
      else if Line='quit' then Break;
      Flush(Output);
    end;
  finally Parts.Free; P.Free; end;
end;
function NewEngine(const Mode: string): TUciEngine;
var D: TExternalEngineDefinition;
begin
  D:=TExternalEngineDefinition.Create;
  try D.Kind:=eekUci; D.UciId:='test'; D.ExePath:=ExpandFileName(ParamStr(0)); D.Arguments:='--fake-uci '+Mode;
    Result:=TUciEngine.Create(D);
  finally D.Free; end;
end;
procedure RegistryTests;
var A,B: TExternalEngineList; D: TExternalEngineDefinition; Name,HubKey,DxpKey: string;
begin
  Name:=ChangeFileExt(ExpandFileName(ParamStr(0)),'.registry-test.json');
  A:=TExternalEngineList.Create; B:=TExternalEngineList.Create;
  try
    Check((Ord(eekHub)=0) and (Ord(eekDxp)=1),'Legacy protocol ordinals preserved');
    D:=TExternalEngineDefinition.Create; D.ExePath:=ExpandFileName(ParamStr(0)); D.HubId:='same'; A.Add(D); HubKey:=EngineIdentityKey(D);
    D:=TExternalEngineDefinition.Create; D.ExePath:=ExpandFileName(ParamStr(0)); D.Kind:=eekDxp; D.DxpId:='same'; A.Add(D); DxpKey:=EngineIdentityKey(D);
    D:=TExternalEngineDefinition.Create; D.ExePath:=ExpandFileName(ParamStr(0)); D.Kind:=eekUci; D.UciId:='same'; A.Add(D);
    Check(D.InitText='','UCI does not inherit Hub init');
    Check((EngineIdentityKey(D)<>HubKey) and (EngineIdentityKey(D)<>DxpKey),'Protocol identities remain distinct');
    SaveExternalEngines(Name,A); LoadExternalEngines(Name,B);
    Check((B.Count=3) and (B[2].Kind=eekUci) and (B[2].UciId='same'),'UCI registry round trip');
    Check((EngineIdentityKey(B[0])=HubKey) and (EngineIdentityKey(B[1])=DxpKey),'Hub and DXP identity round trip unchanged');
  finally A.Free; B.Free; DeleteFile(Name); end;
end;
procedure Tests;
var E,E2: TUciEngine; Options,Params: TEngineParamArray; P: TEngineParam; C: TProcessEngineCommand;
  PV,Score,Depth,TimeText,FileName: string; Info: TUciInfo; Moves: TStringList; I: Integer; Raised: Boolean; Tick: QWord;
begin
  FileName:=EngineParamsFileName(ExpandFileName(ParamStr(0)));
  Params:=nil; AddOrUpdateParam(Params,'hash','spin','64',False);
  AddOrUpdateParam(Params,'gui-stop-timeout-ms','string','100',False);
  SaveEngineParamsToJson(FileName,'uci',Params);
  try
    Check(ParseUciOption('option name With Spaces type combo default Very Fast var Very Fast var Slow',P),'Spaced options');
    Check((P.Name='With Spaces') and (P.Value='Very Fast'),'Option spelling/value');
    ValidateUciValue(P,'Very Fast'); Raised:=False;
    try ValidateUciValue(P,'invalid'); except on E:EConvertError do Raised:=True; end; Check(Raised,'Combo validation');
    Check(ParseUciInfo('info depth 12 score cp 30 upperbound pv e2e4',Info) and Info.Bounded,'Upper bounds recognized');
    Check(ParseUciInfo('info depth 13 score cp 30 lowerbound pv e2e4',Info) and Info.Bounded,'Lower bounds recognized');
    Check(ParseUciInfo('info multipv 2 score cp 30 pv e2e4',Info) and (Info.MultiPV=2),'Secondary line recognized');
    Check(not ParseUciInfo('info score cp 99999999999999999999999 pv e2e4',Info),'Overflowing scores rejected');
    Raised:=False; try ValidateUciText('unsafe'+#10+'quit'); except on X:EConvertError do Raised:=True; end;
    Check(Raised,'Protocol line injection rejected');
    Check(ParseUciOption('option name Hash type spin default 16 min 1 max 256',P),'Spin metadata parsed');
    Raised:=False; try ValidateUciValue(P,'257'); except on X:EConvertError do Raised:=True; end;
    Check(Raised,'Spin bounds enforced');
    for I:=0 to 3 do begin
      case I of 0:E:=NewEngine('normal'); 1:E:=NewEngine('bound'); 2:E:=NewEngine('mate'); 3:E:=NewEngine('longline'); end;
      try
        Check(E.LaunchAndInit,'UCI handshake '+E.LastError); Options:=E.DiscoveredOptions;
        Check((Length(Options)=6) and (Options[0].Name='hAsH') and (Options[0].Value='64'),'Saved options match case insensitively');
        Check(Options[1].Value='false','Ponder override'); Check(Options[2].Value='1','Primary line override');
        E.PressButton('clear hash');
        if I=2 then E.SetGamePosition('4k3/8/8/8/8/8/8/R3K3 b - - 0 37',nil) else E.SetGamePosition(ChessStartingFEN,nil);
        E.SetClockInfo(1,0.1,0); E.StartAnalyzing;
        for Tick:=1 to 5 do begin E.PollOutput; Sleep(10); end;
        E.ReadSearchInfo(PV,Score,Depth,TimeText);
        Check(PV<>'','Legal primary PV');
        if I=1 then Check((Score='0.10') and (Depth='1'),'Bounds/secondary lines do not replace exact pair')
        else if I=2 then Check((Score='#-3') and (Depth='5'),'Mate normalized to White at Black root')
        else Check((Score='0.35') and (Depth='2'),'Latest exact primary info');
        E.StopSearch; E.SetGamePosition(ChessStartingFEN,nil);
        Check(E.PrincipalVariation='','Position change clears old PV');
        if I<>1 then Check(E.StartThinking<>'','Finite one-shot returns legal move');
        if I=0 then begin
          Moves:=TStringList.Create;
          try
            Moves.Add('e2e4'); Moves.Add('c7c5'); E.SetGamePosition(ChessStartingFEN,Moves);
            Check(E.StartThinking<>'','Position history is sent and replayed');
          finally Moves.Free; end;
          E.SetGamePosition('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1',nil);
          Check(E.StartThinking='','Terminal positions do not launch a search');
        end;
      finally E.Free; end;
    end;
    E:=NewEngine('normal'); E2:=NewEngine('mate');
    try
      Check(E.LaunchAndInit and E2.LaunchAndInit,'Separate UCI processes initialize');
      E.SetGamePosition(ChessStartingFEN,nil);
      E2.SetGamePosition('4k3/8/8/8/8/8/8/R3K3 b - - 0 37',nil);
      E.SetClockInfo(1,0.1,0); E2.SetClockInfo(1,0.1,0); E.StartAnalyzing; E2.StartAnalyzing;
      for I:=1 to 5 do begin E.PollOutput; E2.PollOutput; Sleep(10); end;
      E.ReadSearchInfo(PV,Score,Depth,TimeText); Check(Score='0.35','First UCI process retains its own score');
      E2.ReadSearchInfo(PV,Score,Depth,TimeText); Check(Score='#-3','Second UCI process retains its own score');
      E.Stop; Check(E2.StartThinking<>'','Closing one UCI process leaves the other usable');
    finally E.Free; E2.Free; end;
    E:=NewEngine('nostop');
    try
      Check(E.LaunchAndInit,'Unresponsive fake handshake'); E.SetGamePosition(ChessStartingFEN,nil); E.StartAnalyzing;
      Tick:=GetTickCount64; Raised:=False;
      try E.StopSearch; except on X:Exception do Raised:=True; end;
      Check(Raised and (GetTickCount64-Tick<2500),'readyok cannot replace missing bestmove');
      Raised:=False; try E.StartAnalyzing; except on X:Exception do Raised:=True; end;
      Check(Raised,'Failed fence prevents reuse');
    finally E.Free; end;
    E:=NewEngine('hang');
    try
      C:=E.BeginInitialize; try Sleep(40); E.RequestStop;
        Check(C.Completed.WaitFor(2000)=wrSignaled,'Async discovery cancellation'); Check(not C.BoolResult,'Cancelled handshake is not ready');
      finally C.Free; end;
    finally E.Free; end;
    E:=NewEngine('duplicate');
    try
      Check(E.LaunchAndInit,'Duplicate fake handshake'); E.SetGamePosition(ChessStartingFEN,nil); E.StartAnalyzing;
      Raised:=False; for I:=1 to 5 do begin try E.PollOutput; except on X:Exception do Raised:=True; end; Sleep(10); end;
      Check(Raised,'Duplicate bestmove faults the session');
    finally E.Free; end;
  finally DeleteFile(FileName); end;
end;
var E: TUciEngine; D: TExternalEngineDefinition; PV,Score,Depth,T: string; I: Integer;
begin
  if ParamStr(1)='--fake-uci' then begin Fake; Halt; end;
  RegistryTests; Tests;
  if ParamStr(1)<>'' then begin
    D:=TExternalEngineDefinition.Create; D.Kind:=eekUci; D.ExePath:=ExpandFileName(ParamStr(1));
    E:=TUciEngine.Create(D);
    try
      Check(E.LaunchAndInit,'Stockfish handshake '+E.LastError); WriteLn('Real engine: ',E.ReportedName);
      E.SetGamePosition(ChessStartingFEN,nil); E.SetClockInfo(1,0.1,0); E.StartAnalyzing;
      for I:=1 to 30 do begin Sleep(10); E.PollOutput; end;
      E.ReadSearchInfo(PV,Score,Depth,T); Check((PV<>'') and (Score<>''),'Real engine analysis');
      E.StopSearch; E.NewGame('4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
      E.SetGamePosition('4k3/8/8/8/8/8/8/R3K3 b - - 0 37',nil); Check(E.StartThinking<>'','Real Black-root finite search');
    finally E.Free; D.Free; end;
  end;
  WriteLn('UCI engine checks passed (',Checks,' checks)');
end.
