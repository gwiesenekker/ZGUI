program startup_cli_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,
 StdCtrls,ExtCtrls,Dialogs,Grids,CheckLst,Process,uMainForm,uTournamentHostForm,uTournamentDialog,
 uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,uEngineRegistry,
 uDraughtsHubEngine,uChessUciEngine,uDraughtsEngine,uGuiDialogs,uStartupCommand,
 uTournamentFileLocks,uRunningGame,uEngineParamsJson,uGameTree,Types;
type TErrors=class
 procedure Report(Sender:TObject;E:Exception);
end;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
var Chess,Draughts:TGameVariant;Checks:Integer=0;Directory:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Peer;
var L,Mode,Move,Fen,Raw,Whites,Blacks:string;P:TGamePosition;Parts:TStringList;I,N:Integer;Active:Boolean;
begin
  Mode:=ParamStr(2);Parts:=TStringList.Create;Active:=False;
  if Mode='uci' then P:=TChessPosition.Create else P:=TDraughtsPosition.Create;
  try
    while not EOF(Input) do begin
      ReadLn(L);
      if L='uci' then begin WriteLn('id name Mixed UCI');WriteLn('uciok');end
      else if L='hub' then begin WriteLn('id name=Mixed version=1');WriteLn('wait');end
      else if L='init' then WriteLn('ready') else if L='isready' then WriteLn('readyok')
      else if Copy(L,1,9)='position ' then begin
        Parts.Clear;ExtractStrings([' '],[],PChar(L),Parts);N:=Parts.IndexOf('moves');
        if Parts[1]='startpos' then P.LoadFromFEN(Chess.DefaultStartingFEN) else begin
          Fen:='';for I:=2 to 7 do begin if I>2 then Fen+=' ';Fen+=Parts[I];end;P.LoadFromFEN(Fen);
        end;
        if N>=0 then for I:=N+1 to Parts.Count-1 do P.PlayMove(Parts[I]);
      end else if Copy(L,1,4)='pos ' then begin
        Raw:=ExtractHubArgument(L,'pos');Whites:='';Blacks:='';
        for I:=2 to Length(Raw) do begin
          if Raw[I] in ['w','W'] then begin if Whites<>'' then Whites+=',';if Raw[I]='W' then Whites+='K';Whites+=IntToStr(I-1);end;
          if Raw[I] in ['b','B'] then begin if Blacks<>'' then Blacks+=',';if Raw[I]='B' then Blacks+='K';Blacks+=IntToStr(I-1);end;
        end;
        P.LoadFromFEN(Raw[1]+':W'+Whites+':B'+Blacks);Parts.Clear;
        Raw:=ExtractHubArgument(L,'moves');ExtractStrings([' '],[],PChar(Raw),Parts);
        for I:=0 to Parts.Count-1 do P.PlayMoveText(Parts[I]);
      end else if Copy(L,1,3)='go ' then begin
        Move:='';if P.LegalMoveCount>0 then Move:=P.LegalMove(0);
        if (Mode='uci') and P.IsLegal('f7g7') then Move:='f7g7';
        Active:=True;
        if Mode='uci' then WriteLn('info depth 8 score cp 42 pv '+Move)
        else WriteLn('info depth=8 score=0.42 pv="'+Move+'"');
        Flush(Output);
        if (Pos('analyze',L)=0) and (ParamStr(3)<>'hold') then begin
          Sleep(180);
          if Mode='uci' then WriteLn('bestmove '+Move) else WriteLn('done move='+Move);
          Active:=False;
        end;
      end else if L='stop' then begin
        if Active then begin if Mode='uci' then WriteLn('bestmove '+Move) else WriteLn('done move='+Move);Active:=False;end;
      end else if L='quit' then Break;
      Flush(Output);
    end;
  finally P.Free;Parts.Free;end;
end;


function ChildTry(const Name:string;const Mode:string='--lock-check'):Integer;
var P:TProcess;
begin
 P:=TProcess.Create(nil);
 try P.Executable:=ExpandFileName(ParamStr(0));P.Parameters.Add(Mode);P.Parameters.Add(Name);
  P.Options:=[poWaitOnExit];P.Execute;Result:=P.ExitStatus;
 finally P.Free;end;
end;
function HoldFile(const Name:string):TProcess;
var Marker:Char;Tick:QWord;
begin
 Result:=TProcess.Create(nil);
 try
  Result.Executable:=ExpandFileName(ParamStr(0));Result.Parameters.Add('--lock-hold');Result.Parameters.Add(Name);
  Result.Options:=[poUsePipes];Result.Execute;Tick:=GetTickCount64;
  while (Result.Output.NumBytesAvailable=0) and Result.Running and (GetTickCount64-Tick<5000) do Sleep(10);
  Check(Result.Output.NumBytesAvailable>0,'Holding child acquired destination');Result.Output.ReadBuffer(Marker,1);
 except Result.Free;raise;end;
end;
procedure Locks;
var A,B:TTournamentFileLocks;P:TProcess;Name,Other:string;Marker:Char;Tick:QWord;
begin
 Name:=Directory+'/shared.json';Other:=Directory+'/other.pdn';
 A:=TTournamentFileLocks.Create;B:=TTournamentFileLocks.Create;
 try
  A.Acquire(Name);A.Acquire(Other);B.Acquire(Name);
  Check(ChildTry(Name)=5,'Other process cannot acquire JSON');
  Check(ChildTry(Other)=5,'Other process cannot acquire publication');
  A.Free;A:=nil;Check(ChildTry(Name)=5,'Shared same-process lease stays held');
  B.Free;B:=nil;Check(ChildTry(Name)=0,'Closing final lease releases ownership');
  Check(ChildTry(Other)=0,'Publication lease released');
  P:=TProcess.Create(nil);
  try
   P.Executable:=ExpandFileName(ParamStr(0));P.Parameters.Add('--lock-hold');P.Parameters.Add(Name);
   P.Options:=[poUsePipes];P.Execute;Tick:=GetTickCount64;
   while (P.Output.NumBytesAvailable=0) and P.Running and (GetTickCount64-Tick<5000) do Sleep(10);
   Check(P.Output.NumBytesAvailable>0,'Holding child acquired lock');P.Output.ReadBuffer(Marker,1);
   Check(ChildTry(Name)=5,'Live child owns lease');P.Terminate(9);P.WaitOnExit;
   Check(ChildTry(Name)=0,'Crash releases OS lock despite remaining sidecar');
  finally P.Free;end;
 finally A.Free;B.Free;end;
end;
procedure RegisterPeers;
var L:TExternalEngineList;E:TExternalEngineDefinition;I:Integer;
begin
 L:=TExternalEngineList.Create;
 try
  for I:=0 to 3 do begin
   E:=TExternalEngineDefinition.Create;E.ExePath:=ExpandFileName(ParamStr(0));
   if I<2 then begin E.Kind:=eekUci;E.UciId:='CLI Chess '+IntToStr(I);E.Arguments:='--peer uci';end
   else begin E.Kind:=eekHub;E.HubId:='CLI Draughts '+IntToStr(I);E.Arguments:='--peer hub';end;
   E.Arguments:=E.Arguments+' '+IntToStr(I);L.Add(E);
  end;
  SaveExternalEngines(EnginesJsonFileName,L);
 finally L.Free;end;
end;
procedure ForVariant(V:TGameVariant);
var M:TMainForm;D:TTournamentDialog;Req:TStartupCommand;MessageText,Name,Before:string;
 I,Count:Integer;Tick:QWord;G:TRunningGame;L:TStringList;Raised:Boolean;Holder:TProcess;Pairings:TStringGrid;Bounds:TRect;
begin
 Name:=Directory+'/'+GameVariantId(V)+' Ö.json';D:=TTournamentDialog.Create(nil,V);
 try
  TButton(D.FindComponent('CreatePairing')).Click;
  D.SaveTournamentToFile(Name);
  Holder:=HoldFile(Name+'.other.json');
  try
   Raised:=False;try D.SaveTournamentToFile(Name+'.other.json');except on E:EInvalidOperation do Raised:=True;end;
   Check(Raised and (D.SaveFileName=Name),'Failed Save As retains source file identity');
   Check(ChildTry(Name)=5,'Failed Save As retains source lease');
   Check(not FileExists(Name+'.other.json'),'Failed Save As does not publish destination');
  finally Holder.Terminate(9);Holder.WaitOnExit;Holder.Free;end;
  D.SaveTournamentToFile(Name+'.other.json');
  Check(ChildTry(Name)=0,'Successful Save As releases old JSON');
  Check(ChildTry(Name+'.other.json')=5,'Successful Save As protects new JSON');
  Check(ChildTry(D.PublicationFileName)=5,'Successful Save As keeps publication protected');
  D.SaveTournamentToFile(Name);
 finally D.Free;end;
 M:=TMainForm.Create(nil);
 try
  Req:=Default(TStartupCommand);Req.Kind:=sckHelp;
  Check(M.ExecuteStartupCommand(Req,MessageText) and (M.TournamentHost=nil),'Help never creates a tournament');
  Req.Kind:=sckRunTournament;Req.FileName:=Name;
  M.QueueStartupCommand(Req,'');M.QueueStartupCommand(Req,'');
  for I:=1 to 10 do begin Application.ProcessMessages;Sleep(10);end;
  Check(M.TournamentHost<>nil,'Queued startup opens the shared host');
  Check(M.TournamentHost.Visible and (M.TournamentHost.Count=1),'Tournament is visible in one tab');
  D:=M.TournamentHost.Dialogs[0];Check(D.Variant=V,'Saved file selects game variant');
  Check(M.ActiveGameTree.Variant=V,'Foreground request selects matching main board');
  Check(ChildTry(Name,'--open-check')=5,'Second ZGUI cannot open active tournament snapshot');
  Count:=M.TestGameCount;Check(Count=1,'Shared MainForm runner starts one game');
  Check(M.ExecuteStartupCommand(Req,MessageText) and (M.TestGameCount=Count) and
    (M.TournamentHost.Count=1),'Already-running request selects without duplication');
  Tick:=GetTickCount64;G:=nil;
  repeat
   Application.ProcessMessages;M.TestDrainGuiEvents(True);G:=M.FindGameById(1);Sleep(10);
  until ((G<>nil) and (G.MainlineCount>0)) or (GetTickCount64-Tick>8000);
  Check((G<>nil) and (G.MainlineCount>0),'Live game snapshots contain moves');
  Pairings:=TStringGrid(D.FindComponent('TournamentPairings'));Bounds:=Pairings.CellRect(0,1);
  Pairings.OnMouseDown(Pairings,mbLeft,[],Bounds.Left+2,Bounds.Top+2);
  Check(M.ActiveGameTree=G.GameTree,'Selecting live row displays its existing game tree');
  TButton(D.FindComponent('TournamentStop')).Click;
  Tick:=GetTickCount64;
  while D.IsRunning and (GetTickCount64-Tick<8000) do begin Application.ProcessMessages;M.TestDrainGuiEvents(True);Sleep(10);end;
  Check(not D.IsRunning,'GUI Stop drains CLI-started game');
  L:=TStringList.Create;
  try L.LoadFromFile(Name);Before:=L.Text;finally L.Free;end;
  Check(not M.ExecuteStartupCommand(Req,MessageText),'Stopped rows require explicit reschedule');
  L:=TStringList.Create;
  try L.LoadFromFile(Name);Check(L.Text=Before,'Non-start preserves saved results');finally L.Free;end;
  Req.FileName:=Directory+'/missing.json';Raised:=not M.ExecuteStartupCommand(Req,MessageText);
  Check(Raised and (MessageText<>''),'Missing file reports actionable error');
  Check(M.TournamentHost.Count=1,'Failed load adds no tab');
 finally M.Free;end;
end;
var Lease:TTournamentFileLocks;Line:string;Code:Integer;Errors:TErrors;Child:TMainForm;ChildRequest:TStartupCommand;ChildMessage:string;
begin
 if (ParamStr(1)='--lock-check') or (ParamStr(1)='--lock-hold') then begin
  Lease:=TTournamentFileLocks.Create;
  try
   Code:=0;try Lease.Acquire(ParamStr(2));except Code:=5;end;
   if (Code=0) and (ParamStr(1)='--lock-hold') then begin WriteLn('H');Flush(Output);ReadLn(Line);end;
  finally Lease.Free;end;
  Halt(Code);
 end;
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
 if ParamStr(1)='--peer' then begin
  try Peer;finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;Halt(0);
 end;
 if ParamStr(1)='--open-check' then begin
  RequireDerivedFormResource:=False;Application.Initialize;Child:=TMainForm.Create(nil);
  try
   ChildRequest:=Default(TStartupCommand);ChildRequest.Kind:=sckRunTournament;ChildRequest.FileName:=ParamStr(2);
   if Child.ExecuteStartupCommand(ChildRequest,ChildMessage) then Code:=0 else Code:=5;
  finally Child.Free;end;
  RegisterDefaultGameVariant(nil);ClearRegisteredGames;Halt(Code);
 end;
 RequireDerivedFormResource:=False;Application.Initialize;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 GuiTestConfirmationResult:=mrYes;
 Directory:=GetTempDir(False)+'zgui-startup-check-'+IntToStr(GetProcessID);ForceDirectories(Directory);
 try
  Locks;RegisterPeers;ForVariant(Chess);ForVariant(Draughts);
  WriteLn('Startup CLI GUI checks passed: ',Checks);
 finally Application.OnException:=nil;Errors.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
