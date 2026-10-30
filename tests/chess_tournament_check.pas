program chess_tournament_check;
{$mode objfpc}{$H+}
{$IFNDEF GWDGUI_NONINTERACTIVE_TEST}{$FATAL Use the LPI}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Controls,Classes,SysUtils,StdCtrls,
 ExtCtrls,Grids,CheckLst,FPJSON,JSONParser,uChessPosition,uGamePosition,uGameGuiProfile,
 uEngineRegistry,uEngineParamsJson,uTournamentDialog,uTournamentGridModel,uTournamentResults,
 uTournamentStorage,uGameSetupTypes,uMainForm,uRunningGame,uGameOrchestrator,uChessUciEngine,
 uChessPgn,uGameFileReader,uGameTreePdn,uDraughtsPosition,uGuiDialogs;
type
 TErrors=class
  procedure Report(Sender:TObject;E:Exception);
 end;
 THost=class
  Main:TMainForm;
  Games:TList;
  Starts:Integer;
  procedure Start(Sender:TObject;const Setup:TGameSetup;const Title:string;out Game:TObject);
 end;
var Checks:Integer=0;V:TChessVariant;Directory,RegistrySaved,ParamsSaved,ParamsFile:string;
 HadRegistry,HadParams:Boolean;
procedure TErrors.Report(Sender:TObject;E:Exception);
begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Flush(Output);Halt(1);end;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
function Contents(const Name:string):string;
var L:TStringList;
begin L:=TStringList.Create;try L.LoadFromFile(Name);Result:=L.Text;finally L.Free;end;end;
procedure WriteFile(const Name,Text:string);
var L:TStringList;
begin L:=TStringList.Create;try L.Text:=Text;L.SaveToFile(Name);finally L.Free;end;end;
procedure THost.Start(Sender:TObject;const Setup:TGameSetup;const Title:string;out Game:TObject);
begin
 Check(Setup.ForcePonderOff,'Tournament setup enforces runtime ponder-off');
 Game:=Main.StartGameFromSetup(Setup,Title);Games.Add(Game);Inc(Starts);
end;
procedure Peer;
var Mode,Line,Fen,Move:string;Words:TStringList;P,Q:TChessPosition;F:TextFile;I,N:Integer;
begin
 Mode:=ParamStr(2);AssignFile(F,ParamStr(4));Rewrite(F);Words:=TStringList.Create;P:=TChessPosition.Create;
 try
  while not EOF(Input) do begin
   ReadLn(Line);WriteLn(F,Line);Flush(F);
   if Line='uci' then begin
    if Mode='init-stop' then Sleep(1200);
    WriteLn('id name Tournament Peer');WriteLn('option name Ponder type check default true');
    WriteLn('option name Threads type spin default 1 min 1 max 32');
    WriteLn('option name Hash type spin default 16 min 1 max 1024');WriteLn('uciok');
   end else if Line='isready' then WriteLn('readyok')
   else if Copy(Line,1,9)='position ' then begin
    Words.Clear;ExtractStrings([' '],[],PChar(Line),Words);N:=Words.IndexOf('moves');
    if Words[1]='startpos' then P.LoadFromFEN(ChessStartingFEN) else begin
     Fen:='';for I:=2 to 7 do begin if I>2 then Fen+=' ';Fen+=Words[I];end;P.LoadFromFEN(Fen);
    end;
    if N>=0 then for I:=N+1 to Words.Count-1 do P.PlayMove(Words[I]);
   end else if Copy(Line,1,3)='go ' then begin
    if Mode='crash' then Break;
    if Mode='silent' then Continue;
    if Mode='slow' then Sleep(1800);
    Move:=P.LegalMove(0);if P.IsLegal('g6g7') then Move:='g6g7';
    WriteLn('info depth 8 score cp 37 time 10 pv '+Move);
    Q:=TChessPosition(P.Clone);
    try Q.PlayMove(Move);if Q.LegalMoveCount>0 then WriteLn('bestmove '+Move+' ponder '+Q.LegalMove(0)) else WriteLn('bestmove '+Move);finally Q.Free;end;
   end else if Line='stop' then WriteLn('bestmove 0000') else if Line='quit' then Break;
   Flush(Output);
  end;
 finally P.Free;Words.Free;CloseFile(F);end;
end;
function Button(F:TForm;const Caption:string):TButton;
var I:Integer;
begin
 for I:=0 to F.ComponentCount-1 do if (F.Components[I] is TButton) and
  (TButton(F.Components[I]).Caption=Caption) then Exit(TButton(F.Components[I]));
 raise Exception.Create('Missing button '+Caption);
end;
function Timer(F:TForm):TTimer;
var I:Integer;
begin for I:=0 to F.ComponentCount-1 do if F.Components[I] is TTimer then Exit(TTimer(F.Components[I]));raise Exception.Create('Missing timer');end;
procedure Pump(H:THost;D:TTournamentDialog);
begin Application.ProcessMessages;H.Main.TestDrainGuiEvents(True);Timer(D).OnTimer(Timer(D));Sleep(10);end;
procedure RegisterPeers(Count:Integer;const Mode:string;Real:Boolean=False);
var List:TExternalEngineList;D:TExternalEngineDefinition;I:Integer;P:TEngineParamArray;
begin
 List:=TExternalEngineList.Create;
 try
  for I:=1 to Count do begin
   D:=TExternalEngineDefinition.Create;D.Kind:=eekUci;D.UciId:='Peer '+IntToStr(I);
   D.ExePath:=ExpandFileName(ParamStr(0));
   D.Arguments:='--peer '+Mode+' '+IntToStr(I)+' "'+Directory+'/peer-'+IntToStr(I)+'.trace"';
   if Real then begin
    D.ExePath:=ExpandFileName(ParamStr(I));
    D.ExecutableName:=ExtractFileName(D.ExePath);D.Arguments:='';
   end;
   List.Add(D);
  end;
  D:=TExternalEngineDefinition.Create;D.Kind:=eekHub;D.ExePath:=ExpandFileName(ParamStr(0));D.HubId:='Not chess';List.Add(D);
  SaveExternalEngines(EnginesJsonFileName,List);
  if not Real then begin
   P:=nil;AddOrUpdateParam(P,'Ponder','check','true',False);SaveEngineParamsToJson(ParamsFile,'uci',P);
  end;
 finally List.Free;end;
end;
procedure Configure(D:TTournamentDialog;Concurrency:Integer;const Root:string);
begin
 TEdit(D.FindComponent('TournamentStartingFEN')).Text:=Root;
 TEdit(D.FindComponent('TournamentMinutes')).Text:='0.2';
 TEdit(D.FindComponent('TournamentIncrement')).Text:='0.1';
 TEdit(D.FindComponent('TournamentConcurrentGames')).Text:=IntToStr(Concurrency);
 Button(D,'Create pairing').Click;
end;
procedure CheckTournament(Real:Boolean);
var H:THost;D,Reloaded:TTournamentDialog;Grid:TStringGrid;Keys:TStringList;Tick:QWord;
 I,MaxBusy,Expected:Integer;Data:TJSONObject;Reader:TChessPgnReader;Game:TRunningGame;
 Saved,Text,FileName:string;BeforeRows:Integer;Raised,CheckedLiveEdit:Boolean;Setup:TGameSetup;
begin
 if Real then begin RegisterPeers(2,'',True);Expected:=2;end else begin RegisterPeers(5,'slow');Expected:=10;end;
 H:=THost.Create;H.Games:=TList.Create;H.Main:=TMainForm.Create(nil);
 D:=TTournamentDialog.Create(H.Main,DefaultGameVariant);Reloaded:=nil;Keys:=TStringList.Create;
 try
  Check(TEdit(D.FindComponent('TournamentStartingFEN')).Text=ChessStartingFEN,'Chess FEN comes from profile');
  Check((TEdit(D.FindComponent('TournamentMoves')).Text='0') and
   (TEdit(D.FindComponent('TournamentIncrement')).Text='3'),'Profile chess clock defaults');
  Check(TCheckListBox(D.FindComponent('TournamentEngines')).Items.Count=2+3*Ord(not Real), 'Chess tournament filters protocols');
  D.OnStartGame:=@H.Start;
  if Real then for I:=0 to D.ComponentCount-1 do
   if D.Components[I] is TRadioGroup then TRadioGroup(D.Components[I]).ItemIndex:=1;
  Configure(D,2,'7k/8/5KQ1/8/8/8/8/8 w - - 0 1');
  Grid:=TStringGrid(D.FindComponent('TournamentPairings'));
  Check(Grid.RowCount=Expected+1,'Existing round-robin pairing count');
  FileName:=Directory+'/tournament-'+BoolToStr(Real,True)+'.json';D.SaveTournamentToFile(FileName);Saved:=Contents(FileName);
  BeforeRows:=Grid.RowCount;
  WriteFile(Directory+'/wrong.json','{"storage_version":2,"starting_fen":"W:W31-50:B1-20"}');
  Raised:=False;try D.LoadTournamentFromFile(Directory+'/wrong.json');except on E:Exception do Raised:=True;end;
  Check(Raised and (Grid.RowCount=BeforeRows) and (D.SaveFileName=FileName),'Wrong-variant load leaves UI and storage unchanged');
  TEdit(D.FindComponent('TournamentConcurrentGames')).Text:='0';
  Raised:=False;try D.SaveTournamentToFile(FileName);except on E:Exception do Raised:=True;end;
  Check(Raised and (Contents(FileName)=Saved),'Invalid concurrency cannot overwrite saved tournament');
  TEdit(D.FindComponent('TournamentConcurrentGames')).Text:='2';
  Raised:=D.GameSetupForRow(1,Setup);
  Check(Raised and Setup.ForcePonderOff,'Existing row setup passes chess validation and runtime policy: '+
    Grid.Cells[TournamentColReason,1]+'; policy='+BoolToStr(Setup.ForcePonderOff,True));
  GuiTestConfirmationResult:=mrYes;
  try Button(D,'Play').Click;finally GuiTestConfirmationResult:=0;end;
  if not Real then Check(Pos('same executable',GuiTestLastConfirmationText)>0,'D6 shared-options warning is shown once at Start');
  Tick:=GetTickCount64;MaxBusy:=0;CheckedLiveEdit:=False;
  repeat
   Pump(H,D);H.Main.CollectBusyEngineKeys(Keys);if Keys.Count>MaxBusy then MaxBusy:=Keys.Count;
   if not Real and (Keys.Count=4) and not CheckedLiveEdit then begin
    TEdit(D.FindComponent('TournamentConcurrentGames')).Text:='invalid';Pump(H,D);
    Check(D.StorageError<>'','Invalid runtime concurrency pauses scheduling without repeated exceptions');
    TEdit(D.FindComponent('TournamentConcurrentGames')).Text:='2';
    GuiTestConfirmationResult:=mrYes;try Button(D,'Play').Click;finally GuiTestConfirmationResult:=0;end;
    CheckedLiveEdit:=True;
   end;
  until not D.IsRunning or (GetTickCount64-Tick>45000);
  Check(not D.IsRunning and (H.Starts=Expected),'Existing scheduler completes all chess rows');
  if not Real then Check(MaxBusy=4,'Two disjoint games use four reservations with five engines');
  H.Main.CollectBusyEngineKeys(Keys);Check(Keys.Count=0,'Completed workers release engine reservations');
  for I:=1 to Expected do Check(Grid.Cells[TournamentColResult,I]='1-0','Chess result reaches standings');
  Check(ExtractFileExt(D.PdnFileName)='.pgn','Existing projection path uses PGN extension');
  Data:=ReadTournamentDocument(FileName,gffPgn);
  try
   Check((Data.Get('storage_version',0)=3) and (Data.Get('notation_format','')='pgn'),'Explicit chess storage format/version');
   Check(Data.Get('force_ponder_off',False) and (Data.Find('pdn_file_name')<>nil) and
    (Data.Find('game_file_name')=nil),'D5 persisted; reviewed existing JSON keys retained');
  finally Data.Free;end;
  Reader:=TChessPgnReader.Create(V);
  try
   Reader.OpenFile(D.PdnFileName);Check(Reader.Entries.Count=Expected,'Projection contains one actual game per pairing');
   for I:=0 to Reader.Entries.Count-1 do begin TGameFileEntry(Reader.Entries[I]).Validate;Check(TGameFileEntry(Reader.Entries[I]).ErrorText='','Tournament PGN validates through existing chess parser');end;
  finally Reader.Free;end;
  Text:=Contents(D.PdnFileName);Game:=TRunningGame(H.Games[0]);
  Check(Pos('[Date "'+FormatDateTime('yyyy.mm.dd',Game.StartedAt)+'"]',Text)>0,'P12 start date survives completed-game capture');
  Check(PgnTournamentFileMatchesId(D.PdnFileName,'')=False,'Ownership rejects an empty requested identity');
  Reloaded:=TTournamentDialog.Create(H.Main,DefaultGameVariant);Reloaded.LoadTournamentFromFile(FileName);
  Check((TStringGrid(Reloaded.FindComponent('TournamentPairings')).RowCount=Expected+1) and not Reloaded.IsRunning,'Reload retains completed rows without launching');
  if not Real then begin
   for I:=1 to 5 do begin
    Text:=Contents(Directory+'/peer-'+IntToStr(I)+'.trace');
    Check((Pos('setoption name Ponder value false',Text)>0) and (Pos('setoption name Ponder value true',Text)=0),'Tournament runtime overrides saved Ponder=true');
    Check((Pos('go ponder',Text)=0) and (Pos('ponderhit',Text)=0),'No speculative search in tournament');
   end;
   Text:=Contents(ParamsFile);Check(Pos('true',Text)>0,'Saved per-executable Ponder option remains unchanged');
  end;
  // External companion edits are preserved rather than overwritten.
  FileName:=D.PdnFileName;Saved:=Contents(FileName)+'; external edit'+LineEnding;WriteFile(FileName,Saved);
  D.SetSelectedResult('1/2-1/2');
  Check((D.PdnFileName<>FileName) and (Contents(FileName)=Saved),'Externally edited PGN survives publication');
 finally Reloaded.Free;D.Free;H.Main.Free;H.Games.Free;H.Free;Keys.Free;end;
end;
procedure CheckSwissAndValidation;
var D,Reloaded:TTournamentDialog;Grid:TStringGrid;I,J,Byes:Integer;P:TRadioGroup;
 Before,Name:string;Raised:Boolean;Data:TJSONObject;
begin
 RegisterPeers(5,'fast');D:=TTournamentDialog.Create(nil,DefaultGameVariant);Reloaded:=nil;
 try
  P:=nil;for I:=0 to D.ComponentCount-1 do if D.Components[I] is TRadioGroup then P:=TRadioGroup(D.Components[I]);
  Check(P<>nil,'Existing pairing radio group');P.ItemIndex:=2;
  Button(D,'Create pairing').Click;Grid:=TStringGrid(D.FindComponent('TournamentPairings'));
  Check(Grid.RowCount=4,'Existing Swiss pairing produces two games and a BYE');Byes:=0;
  for I:=1 to Grid.RowCount-1 do if Grid.Cells[TournamentColBlack,I]='BYE' then begin
   Inc(Byes);Check(Grid.Cells[TournamentColResult,I]='1-0','Swiss BYE has chess result spelling');
  end;
  Check(Byes=1,'One Swiss BYE');
  Name:=Directory+'/swiss.json';D.SaveTournamentToFile(Name);
  GuiTestConfirmationResult:=mrOk;
  try Button(D,'Create pairing').Click;finally GuiTestConfirmationResult:=0;end;
  Check(Grid.RowCount=4,'Unknown chess results block Swiss advancement');
  for I:=1 to Grid.RowCount-1 do if Grid.Cells[TournamentColBlack,I]<>'BYE' then begin
   Grid.Row:=I;D.SetSelectedResult('1/2-1/2');
  end;
  GuiTestConfirmationResult:=mrNo;
  try Button(D,'Clear pairing').Click;finally GuiTestConfirmationResult:=0;end;
  Check((Pos('Start a new tournament',GuiTestLastConfirmationText)>0) and
   (Grid.RowCount=4),'T4 Clear pairing confirms before discarding chess results');
  Before:=Contents(D.PdnFileName);
  Check(Pos('[Black "BYE"]',Before)=0,'BYE never becomes an invented played PGN');
  GuiTestConfirmationResult:=mrYes;try Button(D,'Create pairing').Click;finally GuiTestConfirmationResult:=0;end;
  Check(Grid.RowCount=7,'Existing Swiss algorithm advances using chess results');
  Before:=Contents(Name);TEdit(D.FindComponent('TournamentMinutes')).Text:='not a number';Raised:=False;
  try D.SaveTournamentToFile(Name);except on E:Exception do Raised:=True;end;
  Check(Raised and (Contents(Name)=Before),'Bad numbers cannot silently replace saved time controls');
  TEdit(D.FindComponent('TournamentMinutes')).Text:='5';
  Data:=ReadTournamentDocument(Name,gffPgn);
  try Data.Strings['starting_fen']:='invalid FEN';WriteFile(Directory+'/bad-fen.json',Data.AsJSON);finally Data.Free;end;
  Raised:=False;try D.LoadTournamentFromFile(Directory+'/bad-fen.json');except on E:Exception do Raised:=True;end;
  Check(Raised and (Grid.RowCount=7),'Invalid loaded root is rejected before changing the dialog');
  Reloaded:=TTournamentDialog.Create(nil,DefaultGameVariant);Reloaded.LoadTournamentFromFile(Name);
  Check(TStringGrid(Reloaded.FindComponent('TournamentPairings')).RowCount=7,'Swiss rounds survive JSON reload');
 finally Reloaded.Free;D.Free;end;
end;
procedure CheckStopAndFailure(const Mode:string);
var H:THost;D:TTournamentDialog;Grid:TStringGrid;Tick:QWord;Keys:TStringList;I:Integer;
 FileName:string;Data,Rec:TJSONObject;
begin
 RegisterPeers(2,Mode);H:=THost.Create;H.Games:=TList.Create;H.Main:=TMainForm.Create(nil);
 D:=TTournamentDialog.Create(H.Main,DefaultGameVariant);Keys:=TStringList.Create;
 try
  D.OnStartGame:=@H.Start;Configure(D,1,ChessStartingFEN);Grid:=TStringGrid(D.FindComponent('TournamentPairings'));
  FileName:=Directory+'/'+Mode+'.json';D.SaveTournamentToFile(FileName);
  GuiTestConfirmationResult:=mrYes;try Button(D,'Play').Click;finally GuiTestConfirmationResult:=0;end;
  if Mode<>'crash' then begin
   Tick:=GetTickCount64;
   repeat
    Pump(H,D);H.Main.CollectBusyEngineKeys(Keys);
    if Mode='init-stop' then begin if Keys.Count=2 then Break;end
    else if (Keys.Count=2) and FileExists(Directory+'/peer-1.trace') and
      (Pos('go wtime ',Contents(Directory+'/peer-1.trace'))>0) then Break;
   until GetTickCount64-Tick>5000;
   Check(Keys.Count=2,'Both engines reserved before Stop');Button(D,'Stop').Click;
  end;
  Tick:=GetTickCount64;repeat Pump(H,D);until not D.IsRunning or (GetTickCount64-Tick>8000);
  Check(not D.IsRunning and (H.Starts=1),'Stop/error finishes existing runner without automatic retry');
  Check(Grid.Cells[TournamentColResult,1]='*','Stop/error does not fabricate a forfeit');
  if Mode='crash' then Check(Pos('process exited',Grid.Cells[TournamentColReason,1])>0,'Crash has an explicit row error')
  else if Mode='silent' then Check(Grid.Cells[TournamentColReason,1]='Stopped','Stop has an explicit unfinished row reason: '+Grid.Cells[TournamentColReason,1])
  else Check(Grid.Cells[TournamentColReason,1]<>'','Early shutdown retains an explicit unfinished-row reason');
  for I:=1 to 20 do Pump(H,D);Check(H.Starts=1,'Repeated timer ticks never retry a failed attempt');
  H.Main.CollectBusyEngineKeys(Keys);Check(Keys.Count=0,'Stopped/failed workers release reservations');
  D.SetSelectedResult('1/2-1/2');D.SaveTournamentToFile(FileName);
  Data:=ReadTournamentDocument(FileName,gffPgn);
  try
   Rec:=TJSONObject(TJSONObject(TJSONArray(Data.Find('games'))[0]).Find('record'));
   Check(Rec.Get('manual_result','')='1/2-1/2','Manual result remains durable after failure');
  finally Data.Free;end;
  D.RescheduleSelectedGame(nil);Data:=ReadTournamentDocument(FileName,gffPgn);
  try
   Rec:=TJSONObject(TJSONObject(TJSONArray(Data.Find('games'))[0]).Find('record'));
   Check((Rec.Get('attempt',0)=2) and (TJSONArray(Rec.Find('history')).Count=1),'Reschedule keeps failed attempt history');
  finally Data.Free;end;
  Check((Grid.Cells[TournamentColResult,1]='*') and (Grid.Cells[TournamentColReason,1]=''),'Explicit reschedule clears the row for another attempt');
 finally D.Free;H.Main.Free;Keys.Free;H.Games.Free;H.Free;end;
end;

var Search:TSearchRec;Errors:TErrors;
begin
 if ParamStr(1)='--peer' then begin Peer;Halt;end;
 RequireDerivedFormResource:=False;Application.Initialize;Application.ShowMainForm:=False;
 Errors:=TErrors.Create;Application.OnException:=@Errors.Report;
 V:=TChessVariant.Create;RegisterDefaultGameVariant(V);RegisterGameGuiProfile(V,ChessGuiProfile);
 Directory:=GetTempFileName(GetTempDir(False),'ctour');DeleteFile(Directory);CreateDir(Directory);
 ParamsFile:=EngineParamsFileName(ExpandFileName(ParamStr(0)));
 HadRegistry:=FileExists(EnginesJsonFileName);if HadRegistry then RegistrySaved:=Contents(EnginesJsonFileName);
 HadParams:=FileExists(ParamsFile);if HadParams then ParamsSaved:=Contents(ParamsFile);
 try
  WriteLn('Chess Swiss/settings checks');Flush(Output);CheckSwissAndValidation;
  WriteLn('Chess Stop/error checks');Flush(Output);CheckStopAndFailure('silent');CheckStopAndFailure('init-stop');CheckStopAndFailure('crash');
  WriteLn('Chess concurrent round robin');Flush(Output);CheckTournament(False);
  if ParamCount>=2 then begin
   WriteLn('Stockfish/Arasan double round robin');Flush(Output);CheckTournament(True);
  end;
  WriteLn('Chess tournament GUI checks passed (',Checks,' checks)');
 finally
  if HadRegistry then WriteFile(EnginesJsonFileName,RegistrySaved) else DeleteFile(EnginesJsonFileName);
  if HadParams then WriteFile(ParamsFile,ParamsSaved) else DeleteFile(ParamsFile);
  RegisterDefaultGameVariant(nil);V.Free;Errors.Free;
  if FindFirst(Directory+'/*',faAnyFile,Search)=0 then begin
   repeat if (Search.Name<>'.') and (Search.Name<>'..') then DeleteFile(Directory+'/'+Search.Name);until FindNext(Search)<>0;FindClose(Search);
  end;RemoveDir(Directory);
 end;
end.
