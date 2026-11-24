program interactive_cli_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} uEngineInstallationFixture, uCliProtocolOutput,Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,
 ExtCtrls,Grids,Dialogs,Menus,uEnginesDialog,FPJSON,JSONParser,uMainForm,uSprtPanel,uSprt,uTournamentDialog,uTournamentHostForm,
 uTournamentStorage,uGamePosition,uChessPosition,uDraughtsPosition,uGameGuiProfile,
 uEngineRegistry,uEngineParamsJson,uGameSetupTypes,uDraughtsHubEngine,uChessUciEngine,uGuiDialogs,
 uStartupCommand,uRunningGame,uGameTree,uAtomicFile,FileUtil,uTournamentGridModel,uTournamentBallot;
var Chess,Draughts:TGameVariant;Checks:Integer=0;Directory:string;Main:TMainForm;
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


procedure RegisterPeers;
var L:TExternalEngineList;E:TExternalEngineDefinition;I:Integer;
begin
 L:=TExternalEngineList.Create;
 try
  for I:=0 to 3 do begin
   E:=TExternalEngineDefinition.Create;E.ExePath:=InstallEngineFixture(ExpandFileName(ParamStr(0)),'peer-'+IntToStr(I));
   if I<2 then begin E.Kind:=eekUci;E.UciId:='CLI Chess '+IntToStr(I);E.Arguments:='--peer uci';end
   else begin E.Kind:=eekHub;E.HubId:='CLI Draughts '+IntToStr(I);E.Arguments:='--peer hub';end;
   E.Arguments:=E.Arguments+' '+IntToStr(I);L.Add(E);
  end;
  SaveExternalEngines(EnginesJsonFileName,L);
 finally L.Free;end;
end;

function Response(const Command,Prefix:string;const Code:string=''):TJSONObject;
var Text:string;
begin
 Text:=Main.InteractiveCommand(Command);
 Check(Copy(Text,1,Length(Prefix)+1)=Prefix+' ',Command+' returned '+Text);
 Result:=TJSONObject(GetJSON(Copy(Text,Length(Prefix)+2,MaxInt)));
 if Code<>'' then Check(Result.Get('code','')=Code,'Error code '+Code+' for '+Text);
end;
procedure Error(const Command,Code:string);
var J:TJSONObject;
begin J:=Response(Command,'ERROR',Code);J.Free;end;
procedure Pump;
begin Application.ProcessMessages;Main.TestDrainGuiEvents(True);Sleep(10);end;
procedure StopByCli(Id:Integer;D:TTournamentDialog);
var Tick:QWord;J:TJSONObject;Count:Integer;SavedName:string;
begin
 Count:=Main.TournamentHost.Count;SavedName:=D.SaveFileName;
 J:=Response('stop_tournament id='+IntToStr(Id),'OK');
 try Check(J.Get('tournament',0)=Id,'Stop acknowledges the same CLI tournament');finally J.Free;end;
 J:=Response('stop_tournament id='+IntToStr(Id),'OK');J.Free;
 Tick:=GetTickCount64;
 while D.IsRunning and (GetTickCount64-Tick<5000) do Pump;
 Check(not D.IsRunning,'Shared stop path drains match asynchronously');
 Check((Main.TournamentHost.Count=Count) and (D.SaveFileName=SavedName),'Stop preserves tournament tab and file identity');
 J:=Response('query_tournament id='+IntToStr(Id),'OK');
 try Check(J.Get('games_active',-1)=0,'Stopped tournament remains queryable with no active games');finally J.Free;end;
end;
procedure LocaleSettings;
var D:TTournamentDialog;Engines:TExternalEngineList;Settings:TTournamentMatchSettings;Old:Char;
begin
 Engines:=TExternalEngineList.Create;D:=nil;Old:=DefaultFormatSettings.DecimalSeparator;
 try
  LoadExternalEngines(EnginesJsonFileName,Engines);D:=TTournamentDialog.Create(nil,Chess);
  Settings:=Default(TTournamentMatchSettings);Settings.Engine1Key:=EngineIdentityKey(Engines[0]);Settings.Engine2Key:=EngineIdentityKey(Engines[1]);
  Settings.HasTime:=True;Settings.Seconds:=90.5;Settings.HasIncrement:=True;Settings.Increment:=0.25;
  DefaultFormatSettings.DecimalSeparator:=',';D.ConfigureNewTournament(Settings);
  Check(TEdit(D.FindComponent('TournamentMinutes')).Text='90,5','Typed CLI time uses local GUI number format');
  Check(TEdit(D.FindComponent('TournamentIncrement')).Text='0,25','Fractional increment survives decimal comma');
 finally
  DefaultFormatSettings.DecimalSeparator:=Old;
  if D<>nil then begin Check(D.AbandonUnpublished,'Locale setup remains unpublished');D.Free;end;
  Engines.Free;
 end;
end;
function RecoveryFiles:string;
var L:TStringList;
begin
 L:=TStringList.Create;
 try FindAllFiles(L,IncludeTrailingPathDelimiter(GetAppConfigDir(False))+'tournaments','*',True);
  L.Sort;Result:=L.Text;
 finally L.Free;end;
end;
procedure RelativeBallot;
var Launch,FileName,Before:string;L:TStringList;J:TJSONObject;OriginalMain:TMainForm;
begin
 OriginalMain:=Main;
 Launch:=GetCurrentDir;FileName:='cli-relative-'+IntToStr(GetProcessID)+'.fen';L:=TStringList.Create;
 try
  L.Add(Chess.DefaultStartingFEN);L.SaveToFile(FileName);Main:=TMainForm.Create(nil);SetCurrentDir(Directory);
  Before:=RecoveryFiles;
  J:=Response('run_tournament engine1="CLI Chess 0" engine2="CLI Chess 1" ballot='+FileName,'OK');
  try Check(J.Get('games_total',0)=2,'Relative ballot resolves from launch directory');finally J.Free;end;
  Main.TournamentHost.Dialogs[0].StopTournament;Pump;
 finally
  SetCurrentDir(Launch);if Main<>OriginalMain then Main.Free;Main:=OriginalMain;
  DeleteFile(FileName);L.Free;
 end;
end;
procedure ConfigurationChecks;
var L:TExternalEngineList;Params:TEngineParamArray;J:TJSONObject;Text:TStringList;
 RegistryBefore,ParamsBefore,ParamFile,ConfigFile,Args,Key:string;I,K:Integer;
 Item:TMenuItem;Popup:TPopupMenu;Tick:QWord;EngineDialog:TEnginesDialog;
begin
 L:=TExternalEngineList.Create;Text:=TStringList.Create;
 try
  LoadExternalEngines(EnginesJsonFileName,L);
  // Captured schemas are the same metadata saved after a GUI handshake.
  for I:=0 to 2 do begin
   Params:=nil;
   if I<2 then begin
    AddOrUpdateParam(Params,'Hash','spin','16',False);Params[0].MinValue:='1';Params[0].MaxValue:='128';
    AddOrUpdateParam(Params,'Ponder','check','false',False);
   end else AddOrUpdateParam(Params,'threads','int','1',False);
   SaveEngineDefinitionParams(L[I],Params);
  end;
  SaveExternalEngines(EnginesJsonFileName,L);Text.LoadFromFile(EnginesJsonFileName);RegistryBefore:=Text.Text;
  J:=Response('configure_engine engine_id=1','OK');
  try Check(not J.Get('changed',True),'Inspect has no writes');Check(TJSONObject(J.Find('options')).Get('Hash','')='16','Inspect exposes captured options');finally J.Free;end;
  J:=Response('configure_engine engine_id=1 options='' {"Hash":64,"Ponder":true} '' dry_run=true','OK');
  try Check(J.Get('dry_run',False) and not J.Get('changed',True),'Dry run validates without saving');finally J.Free;end;
  Text.LoadFromFile(EnginesJsonFileName);Check(Text.Text=RegistryBefore,'Dry run retains exact registry bytes');
  Error('configure_engine engine_id=1 options=''{"Hash":129}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 options=''{"Missing":1}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 options=''{"Hash":1,"hash":2}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 options=''{"Ponder":"maybe"}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 options=''{"gui-uci-id":"renamed"}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 environment=''{"INVALID-NAME":"x"}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 environment=''{"TEST":null}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 feature_flags=''{"no-pondering":true}''','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 dry_run=yes','BAD_ARGUMENT');
  Error('configure_engine engine_id=1 engine="CLI Chess 0"','BAD_ARGUMENT');
  Text.LoadFromFile(EnginesJsonFileName);Check(Text.Text=RegistryBefore,'Invalid patches preserve registry bytes');
  J:=Response('configure_engine engine_id=1 options=''{"Hash":64,"Ponder":true}'' feature_flags=''["NO-PONDERING"]''','OK');
  try Check(J.Get('changed',False),'UCI patch persisted');finally J.Free;end;
  LoadExternalEngines(EnginesJsonFileName,L);Params:=nil;LoadEngineDefinitionParams(L[0],'uci',Params);
  Check((EngineParamValue(Params,'Hash','')='64') and (EngineParamValue(Params,'Ponder','')='true'),'GUI loader reads CLI UCI changes');
  Check(EngineHasFeatureFlag(Params,'no-pondering'),'Feature flags canonicalized and saved');
  ParamFile:=EngineParamsFileName(L[2].ExePath);Text.LoadFromFile(ParamFile);ParamsBefore:=Text.Text;
  Error('configure_engine engine_id=3 options=''{"threads":"bad\nline"}''','BAD_ARGUMENT');
  Text.LoadFromFile(ParamFile);Check(Text.Text=ParamsBefore,'Invalid Hub patch retains parameter file');
  ConfigFile:=Directory+'/configuration.json';Text.Text:='{"options":{"threads":2},"feature_flags":["no-ponder-hit"]}';Text.SaveToFile(ConfigFile);
  J:=Response('configure_engine engine_id=3 file="'+ConfigFile+'"','OK');J.Free;
  LoadExternalEngines(EnginesJsonFileName,L);Params:=nil;LoadEngineDefinitionParams(L[2],'hub',Params);
  Check((EngineParamValue(Params,'threads','')='2') and EngineHasFeatureFlag(Params,'no-ponder-hit'),'Hub GUI loader reads file patch');
  Error('configure_engine engine_id=3 file="'+ConfigFile+'" options=''{}''','BAD_ARGUMENT');
  Text.Text:='{"unexpected":true}';Text.SaveToFile(ConfigFile);
  Error('configure_engine engine_id=3 file="'+ConfigFile+'"','BAD_ARGUMENT');
  DeleteFile(ConfigFile);
  // Environment changes configuration identity: use returned ID thereafter.
  Key:=EngineIdentityKey(L[0]);
  J:=Response('configure_engine engine="CLI Chess 0" environment=''{"ZGUI_TEST":"one","EMPTY":""}''','OK');
  try I:=J.Get('id',0);Check((I>4) and (J.Get('key','')<>Key),'Changed environment returns a fresh identity/ID');finally J.Free;end;
  Error('configure_engine engine_id=1','UNKNOWN_ENGINE');
  J:=Response('configure_engine engine_id='+IntToStr(I)+' environment=''{}''','OK');J.Free;
  // Return fixtures to their original defaults before match/identity assertions.
  for I:=0 to 2 do begin
   Args:='';if I<2 then Args:='options=''{"Hash":16,"Ponder":false}'' ';
   J:=Response('configure_engine engine="'+L[I].IdText+'" '+Args+'feature_flags=''[]''','OK');J.Free;
  end;
  for K:=0 to 1 do begin
   if K=0 then Main.SelectGameVariant(Chess) else Main.SelectGameVariant(Draughts);
   Item:=nil;for I:=0 to Main.ComponentCount-1 do if (Main.Components[I] is TMenuItem) and
    (TMenuItem(Main.Components[I]).Caption='Open Annotator') then Item:=TMenuItem(Main.Components[I]);
   Check(Item<>nil,'Annotator menu available');Popup:=TPopupMenu(Item.GetParentMenu);Popup.OnPopup(Popup);Item.Items[0].Click;
   Tick:=GetTickCount64;repeat Pump;until (Main.TestAnalyzerRunner<>nil) or (GetTickCount64-Tick>5000);
   Check(Main.TestAnalyzerRunner<>nil,'Real annotator started');
   if K=0 then Args:='CLI Chess 0' else Args:='CLI Draughts 2';
   Error('configure_engine engine="'+Args+'" feature_flags=''[]''','BUSY');
   J:=Response('configure_engine engine="'+Args+'"','OK');J.Free;
   Item:=nil;for I:=0 to Main.ComponentCount-1 do if (Main.Components[I] is TMenuItem) and
    (TMenuItem(Main.Components[I]).Caption='Close Annotator') then Item:=TMenuItem(Main.Components[I]);
   Check(Item<>nil,'Close annotator available');Popup.OnPopup(Popup);Item.Click;
   Tick:=GetTickCount64;repeat Pump;until (Main.TestAnalyzerRunner=nil) or (GetTickCount64-Tick>5000);
   Check(Main.TestAnalyzerRunner=nil,'Annotator stopped');
  end;
  Main.SelectGameVariant(Chess);
  for I:=0 to Main.ComponentCount-1 do if (Main.Components[I] is TButton) and
   (TButton(Main.Components[I]).Caption='Engines...') then TButton(Main.Components[I]).Click;
  EngineDialog:=nil;for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TEnginesDialog then EngineDialog:=TEnginesDialog(Main.Components[I]);
  Check((EngineDialog<>nil) and EngineDialog.Visible,'Engine settings window opened');
  Error('configure_engine engine_id=1 feature_flags=''[]''','BUSY');EngineDialog.Hide;
 finally L.Free;Text.Free;end;
end;

procedure RegistryChecks;
var Engines:TExternalEngineList;Clone:TExternalEngineDefinition;SavedArgs,Key:string;J:TJSONObject;
begin
 Engines:=TExternalEngineList.Create;
 try
  LoadExternalEngines(EnginesJsonFileName,Engines);SavedArgs:=Engines[0].Arguments;Key:=EngineIdentityKey(Engines[0]);
  Engines[0].Arguments:=SavedArgs+' changed';SaveExternalEngines(EnginesJsonFileName,Engines);
  J:=Response('run_tournament engine1_id=1 engine2_id=2','ERROR','UNKNOWN_ENGINE');
  try Check(J.Get('message','')='Engine registration no longer exists','Removed session ID retains precise message');finally J.Free;end;
  J:=Response('run_tournament engine1_key="'+Key+'" engine2_id=2','ERROR','UNKNOWN_ENGINE');
  try Check(J.Get('message','')='Engine registration no longer exists','Removed registration key retains precise message');finally J.Free;end;
  Engines[0].Arguments:=SavedArgs;SaveExternalEngines(EnginesJsonFileName,Engines);
  Clone:=TExternalEngineDefinition.Create;Clone.Assign(Engines[0]);Clone.Arguments:=SavedArgs+' clone';Engines.Add(Clone);
  SaveExternalEngines(EnginesJsonFileName,Engines);
  Error('run_tournament engine1="CLI Chess 0" engine2_id=2','AMBIGUOUS_ENGINE');
  Error('run_tournament engine1_id=1 engine2_id=2','CONFIGURE');
  Error('run_tournament engine1_id=1 engine2_id=2 allow_shared_executable=true','CONFIGURE');
  Error('run_tournament engine1="CLI Chess 0" engine1_id=1 engine2_id=2','BAD_ARGUMENT');
  Engines.Delete(Engines.Count-1);SaveExternalEngines(EnginesJsonFileName,Engines);
  J:=Response('run_tournament engine1_key="'+Key+'" engine2_id=2 time=0','ERROR','CONFIGURE');J.Free;
 finally Engines.Free;end;
end;
function PairEntry(J:TJSONObject;Index:Integer):TJSONObject;
begin Result:=TJSONArray(J.Find('pairs')).Objects[Index];end;
function PairScores(J:TJSONObject;Index:Integer):TJSONArray;
begin Result:=TJSONArray(PairEntry(J,Index).Find('results'));end;
procedure PairDetails(Id:Integer;D:TTournamentDialog;V:TGameVariant;const Engine1:string);
var J,Plain,Disabled:TJSONObject;Entries:TJSONArray;I:Integer;Grid:TStringGrid;Setup:TGameSetup;
 Base,Round2,Round4,OpeningFen:string;
 procedure SetLoss(Row:Integer);
 begin
  Grid.Row:=Row;D.GameSetupForRow(Row,Setup);
  if Setup.WhiteEngine.IdText=Engine1 then D.SetSelectedResult(V.ResultText(goBlackWins))
  else D.SetSelectedResult(V.ResultText(goWhiteWins));
 end;
begin
 Grid:=TStringGrid(D.FindComponent('TournamentPairings'));OpeningFen:=NormalizeBallotFEN(V,V.DefaultStartingFEN);
 Plain:=Response('query_tournament id='+IntToStr(Id),'OK');
 Disabled:=Response('query_tournament id='+IntToStr(Id)+' pairs=false sprt=false','OK');
 try
  Check((Plain.Find('sprt')=nil) and (Plain.Find('pairs')=nil) and (Plain.AsJSON=Disabled.AsJSON),'Omitted/false pairs preserve the existing response');
 finally Disabled.Free;Plain.Free;end;
 J:=Response('query_tournament id='+IntToStr(Id)+' sprt=TRUE','OK');
 try
  Check(TJSONObject(J.Find('sprt')).Get('available',False),'Optional SPRT report available');
  Check(TJSONObject(J.Find('sprt')).Get('model','')=SprtModel,'Explicit paired logistic GSPRT model');
  Check(Abs(TJSONObject(J.Find('sprt')).Get('llr',0.0)-TSprtPanel(D.FindComponent('TournamentSprt')).Report.LLR)<1e-12,'CLI and GUI share GSPRT result');
  Check(not TJSONObject(J.Find('sprt')).Get('automatic_stop',True),'GSPRT never automatically stops games');
 finally J.Free;end;
 J:=Response('query_tournament id='+IntToStr(Id)+' pairs=TRUE','OK');
 try
  Entries:=TJSONArray(J.Find('pairs'));Check(Entries.Count=13,'All opening occurrences, including duplicate FENs and incomplete pairs');
  for I:=0 to Entries.Count-1 do begin
   Check((Entries.Objects[I].Get('pair',0)=I+1) and (Entries.Objects[I].Get('fen','')=OpeningFen),'Pair number and normalized opening FEN');
   Check((TJSONArray(Entries.Objects[I].Find('games')).Integers[0]=2*I+1) and
     (TJSONArray(Entries.Objects[I].Find('games')).Integers[1]=2*I+2),'Scheduled game numbers accompany both scores');
  end;
  Check((PairScores(J,0).Floats[0]=1) and (PairScores(J,0).Floats[1]=0),'Both colours use engine1 perspective');
  Check((PairScores(J,1).Floats[0]=0.5) and (PairScores(J,1).Floats[1]=0.5),'Draw scores normalized to half a point for both games');
  Check((PairScores(J,12).Floats[0]=0.5) and (PairScores(J,12).Items[1].JSONType=jtNull),'Unfinished/unresolved score is JSON null');
  Base:=TJSONArray(J.Find('pairs')).AsJSON;
 finally J.Free;end;
 // W,L / D,D and W,D / D,L have identical aggregate WDL, but distinct pairs.
 Grid.Row:=2;D.SetSelectedResult(V.ResultText(goDraw));SetLoss(4);
 J:=Response('query_tournament id='+IntToStr(Id)+' pairs=true','OK');
 try
  Check((J.Get('wins',0)=1) and (J.Get('draws',0)=23) and (J.Get('losses',0)=1),'Alternative grouping keeps aggregate WDL');
  Check((PairScores(J,0).Floats[0]=1) and (PairScores(J,0).Floats[1]=0.5) and
    (PairScores(J,1).Floats[0]=0.5) and (PairScores(J,1).Floats[1]=0),'Pair evidence distinguishes equal aggregate WDL');
  Check(TJSONArray(J.Find('pairs')).AsJSON<>Base,'Pair snapshot changes when aggregate does not');
 finally J.Free;end;
 SetLoss(2);Grid.Row:=4;D.SetSelectedResult(V.ResultText(goDraw));
 // A valid interleaved schedule: pair 1 has rows 1/4; pair 2 rows 2/3.
 Round2:=Grid.Cells[TournamentColRound,2];Round4:=Grid.Cells[TournamentColRound,4];
 try
  Grid.Cells[TournamentColRound,2]:=Round4;Grid.Cells[TournamentColRound,4]:=Round2;
  J:=Response('query_tournament id='+IntToStr(Id)+' pairs=true','OK');
  try
   Check((TJSONArray(PairEntry(J,0).Find('games')).Integers[1]=4) and
     (TJSONArray(PairEntry(J,1).Find('games')).Integers[0]=2),'Saved opening number defines membership, not adjacency or equal FEN');
  finally J.Free;end;
 finally Grid.Cells[TournamentColRound,2]:=Round2;Grid.Cells[TournamentColRound,4]:=Round4;end;
 J:=Response('query_tournament id='+IntToStr(Id)+' pairs=true','OK');
 try Check(TJSONArray(J.Find('pairs')).AsJSON=Base,'Restored schedule has identical full snapshot');finally J.Free;end;
end;
procedure Match(V:TGameVariant;const A,B:string);
var J,Listed,Obj,Doc:TJSONObject;D:TTournamentDialog;Args,FenFile,Text,Before,Name,PairText:string;
 L:TStringList;I,Id,Count:Integer;Setup:TGameSetup;Grid:TStringGrid;Fens:TStringList;
begin
 Fens:=TStringList.Create;
 try
  FenFile:=Directory+'/'+GameVariantId(V)+'.fen';
  for I:=1 to 13 do Fens.Add(V.DefaultStartingFEN);Fens.SaveToFile(FenFile);
  Args:='engine1="'+A+'" engine2="'+B+'" ballot="'+FenFile+'" shuffle_opening_pairs=true time=600 moves=75 increment=0.25 concurrent=1';
  Count:=Main.TournamentHost.Count;

  J:=Response('run_tournament '+Args+' allow_shared_executable=true','OK');
  try Id:=J.Get('tournament',0);Check(J.Get('games_total',0)=26,'Ballot expands to 26 ordinary games');Check(J.Get('pairs_total',0)=13,'Duplicate FENs remain separate opening pairs');finally J.Free;end;
  D:=Main.TournamentHost.Dialogs[Main.TournamentHost.Count-1];
  Error('configure_engine engine="'+A+'" feature_flags=''[]''','BUSY');
  J:=Response('configure_engine engine="'+A+'" feature_flags=''[]'' dry_run=true','OK');J.Free;
  Check(TCheckBox(D.FindComponent('TournamentShuffleOpeningPairs')).Checked,'CLI shuffle uses shared GUI setting');
  Check(D.GameSetupForRow(1,Setup),'Shared game setup available');
  Check((Setup.TimeControl.MovesPerPeriod=75) and (Abs(Setup.TimeControl.MinutesPerPeriod-10)<0.00001) and
    (Abs(Setup.TimeControl.IncrementSeconds-0.25)<0.00001),'Typed settings use existing clock validator and locale conversion');
  Check(Main.TournamentHost.Visible,'CLI creates visible ordinary tournament tab');
  for I:=1 to 30 do Pump;StopByCli(Id,D);Grid:=TStringGrid(D.FindComponent('TournamentPairings'));
  for I:=1 to 25 do begin
    Grid.Row:=I;D.GameSetupForRow(I,Setup);
    if I<=2 then begin
      if (Setup.WhiteEngine.IdText=A)=(I=1) then Text:=V.ResultText(goWhiteWins) else Text:=V.ResultText(goBlackWins);
    end else Text:=V.ResultText(goDraw);
    D.SetSelectedResult(Text);
  end;
  L:=TStringList.Create;
  try
   Name:=D.SaveFileName;L.LoadFromFile(Name);Before:=L.Text;
   J:=Response('query_tournament id='+IntToStr(Id),'OK');
   try Check(J.Get('games_completed',0)=25,'25 resolved games');Check(J.Get('pairs_completed',0)=12,'Only 12 complete opening pairs');
    Check((J.Get('wins',0)=1) and (J.Get('draws',0)=23) and (J.Get('losses',0)=1),'Results follow engine1 perspective, including both colours and both formats');
   finally J.Free;end;
   L.LoadFromFile(Name);Check(L.Text=Before,'Query does not save/change document');
   J:=Response('stop_tournament id='+IntToStr(Id),'OK');J.Free;
   L.LoadFromFile(Name);Check(L.Text=Before,'Repeated Stop leaves stopped results and file unchanged');
   PairDetails(Id,D,V,A);
   Grid.Row:=1;D.RescheduleSelectedGame(nil);
   J:=Response('query_tournament id='+IntToStr(Id),'OK');
   try Check((J.Get('games_completed',0)=24) and (J.Get('pairs_completed',0)=11),'Counts decrease after GUI reschedule');finally J.Free;end;
   L.LoadFromFile(Name);Before:=L.Text;
   J:=Response('query_tournament id='+IntToStr(Id)+' pairs=true','OK');
   try
    Check((PairScores(J,0).Items[0].JSONType=jtNull) and
      (PairScores(J,1).Items[0].JSONType<>jtNull) and (PairEntry(J,1).Get('pair',0)=2),
      'Earlier incomplete pairs stay ahead of later completed pairs');
    PairText:=TJSONArray(J.Find('pairs')).AsJSON;
   finally J.Free;end;
   L.LoadFromFile(Name);Check(L.Text=Before,'Detailed query does not save/change file');
   D.LoadTournamentFromFile(Name);
   J:=Response('query_tournament id='+IntToStr(Id)+' pairs=true','OK');
   try Check(TJSONArray(J.Find('pairs')).AsJSON=PairText,'Reloading the same saved event reconstructs pair results');finally J.Free;end;
   Doc:=ReadTournamentDocument(Name,GameGuiProfileFor(V).FileFormat);
   try
    Obj:=TJSONObject(TJSONArray(Doc.Find('games')).Objects[0].Find('record'));
    Obj.Strings['capture_error']:='Injected capture failure';L.Text:=Doc.AsJSON;L.SaveToFile(Name);
   finally Doc.Free;end;
   D.LoadTournamentFromFile(Name);
   J:=Response('query_tournament id='+IntToStr(Id),'OK');
   try Check((J.Get('state','')='error') and (Pos('Injected',J.Get('reason',''))>0),'Query exposes capture error and reason');finally J.Free;end;
   Doc:=ReadTournamentDocument(Name,GameGuiProfileFor(V).FileFormat);
   try
     Obj:=TJSONObject(TJSONArray(Doc.Find('games')).Objects[0].Find('record'));
     Obj.Strings['black_engine_key']:=Obj.Get('white_engine_key','');L.Text:=Doc.AsJSON;L.SaveToFile(Name);
   finally Doc.Free;end;
   D.LoadTournamentFromFile(Name);Error('query_tournament id='+IntToStr(Id),'MATCH_CHANGED');
   Error('query_tournament id='+IntToStr(Id)+' pairs=true','MATCH_CHANGED');
   J:=Response('stop_tournament id='+IntToStr(Id),'OK');J.Free;
   D.ResetForVariant(V);Error('query_tournament id='+IntToStr(Id),'TOURNAMENT_REPLACED');
   Error('stop_tournament id='+IntToStr(Id),'TOURNAMENT_REPLACED');
  finally L.Free;end;
 finally Fens.Free;end;
end;
type TModalProbe=class
  Id:Integer;
  procedure Show(Sender:TObject);
  procedure Close(Data:PtrInt);
end;
procedure TModalProbe.Show(Sender:TObject);
begin
 Error('list_engines','BUSY');Error('run_tournament engine1_id=1 engine2_id=2','BUSY');
 Error('query_tournament id='+IntToStr(Id),'BUSY');Error('stop_tournament id='+IntToStr(Id),'BUSY');
 Application.QueueAsyncCall(@Close,PtrInt(Sender));
end;
procedure TModalProbe.Close(Data:PtrInt);
begin TForm(Data).ModalResult:=mrCancel;end;
type TSessionProbe=class
  Timer:TTimer;
  ReportName:string;
  Closing,Stopped,ChessViewed,DraughtsViewed,ModalSeen,ModalShowing,EngineNoticeSeen:Boolean;
  ModalDialog:TForm;
  ModalTimer:TTimer;
  Ticks:Integer;
  procedure ModalShown(Sender:TObject);
  procedure PollModalClose(Sender:TObject);
  procedure Tick(Sender:TObject);
end;
procedure TSessionProbe.ModalShown(Sender:TObject);
begin
 ModalDialog:=TForm(Sender);ModalTimer:=TTimer.Create(nil);ModalTimer.Interval:=25;ModalTimer.OnTimer:=@PollModalClose;
 WriteTextFileAtomically(ReportName+'.modal.ready','ready');
end;
procedure TSessionProbe.PollModalClose(Sender:TObject);
begin if FileExists(ReportName+'.modal.done') then ModalDialog.ModalResult:=mrOk;end;
procedure TSessionProbe.Tick(Sender:TObject);
var I,ChessPlies,DraughtsPlies:Integer;D:TTournamentDialog;G:TRunningGame;Grid:TStringGrid;Bounds:TRect;
 J:TJSONObject;
begin
 if Closing then Exit;
 if ModalShowing then begin
  if FileExists(ReportName+'.modal.done') and (ModalDialog<>nil) then ModalDialog.ModalResult:=mrOk;
  Exit;
 end;
 if FileExists(ReportName+'.modal') and not ModalSeen then begin
  ModalSeen:=True;ModalShowing:=True;GuiTestConfirmationOnShow:=@ModalShown;
  try ShowGuiOkDialog(Main,'CLI modal test','Pipe commands must return BUSY');
  finally GuiTestConfirmationOnShow:=nil;FreeAndNil(ModalTimer);ModalDialog:=nil;ModalShowing:=False;
    WriteTextFileAtomically(ReportName+'.modal.closed','closed');end;
 end;
 if FileExists(ReportName+'.engine-problem') and not EngineNoticeSeen then begin
  EngineNoticeSeen:=True;
  Main.TestReportEngineProblem('Chess engine failed','Injected UCI failure');
  Main.TestReportEngineProblem('Draughts engine failed','Injected Hub failure');
 end;
 Inc(Ticks);ChessPlies:=0;DraughtsPlies:=0;
 // Buffered diagnostics with no newline must never share the protocol stream.
 if Ticks mod 3=0 then begin Write(Output,'diagnostic-probe ');Flush(Output);end;
 if FileExists(ReportName+'.stop') and not Stopped then begin
  Stopped:=True;
  if Main.TournamentHost<>nil then for I:=0 to Main.TournamentHost.Count-1 do
    TButton(Main.TournamentHost.Dialogs[I].FindComponent('TournamentStop')).Click;
 end;
 for I:=1 to Main.TestGameCount do begin
  G:=Main.FindGameById(I);if G=nil then Continue;
  if G.GameTree.Variant=Chess then ChessPlies:=ChessPlies+G.MainlineCount else DraughtsPlies:=DraughtsPlies+G.MainlineCount;
 end;
 if Main.TournamentHost<>nil then for I:=0 to Main.TournamentHost.Count-1 do begin
  D:=Main.TournamentHost.Dialogs[I];
  if ((D.Variant=Chess) and (ChessPlies>0) and not ChessViewed) or
     ((D.Variant=Draughts) and (DraughtsPlies>0) and not DraughtsViewed) then begin
   Grid:=TStringGrid(D.FindComponent('TournamentPairings'));Bounds:=Grid.CellRect(0,1);
   Grid.OnMouseDown(Grid,mbLeft,[],Bounds.Left+2,Bounds.Top+2);
   if D.Variant=Chess then ChessViewed:=Main.ActiveGameTree.Variant=Chess
   else DraughtsViewed:=Main.ActiveGameTree.Variant=Draughts;
  end;
 end;
 J:=TJSONObject.Create;
 try
  J.Add('engine_notices',(Pos('Injected UCI failure',Main.TestAnalyzerLog.Text)>0) and
    (Pos('Injected Hub failure',Main.TestAnalyzerLog.Text)>0));
  if Main.TournamentHost<>nil then J.Add('tabs',Main.TournamentHost.Count) else J.Add('tabs',0);
  J.Add('ticks',Ticks);J.Add('games',Main.TestGameCount);J.Add('chess_plies',ChessPlies);J.Add('draughts_plies',DraughtsPlies);
  J.Add('chess_viewed',ChessViewed);J.Add('draughts_viewed',DraughtsViewed);J.Add('main_visible',Main.Visible);
  J.Add('host_visible',(Main.TournamentHost<>nil) and Main.TournamentHost.Visible);
  WriteTextFileAtomically(ReportName,J.AsJSON);
 finally J.Free;end;
 if FileExists(ReportName+'.close') or (Ticks>1200) then begin
  Closing:=True;Timer.Enabled:=False;Main.Close;
 end;
end;
procedure Session;
var Probe:TSessionProbe;Request:TStartupCommand;
begin
 Directory:=ExtractFilePath(ParamStr(2));RegisterPeers;
 Application.CreateForm(TMainForm,Main);Probe:=TSessionProbe.Create;
 try
  Probe.ReportName:=ParamStr(2);Probe.Timer:=TTimer.Create(nil);Probe.Timer.Interval:=25;Probe.Timer.OnTimer:=@Probe.Tick;
  GuiTestConfirmationResult:=mrNo;Request:=Default(TStartupCommand);Request.Kind:=sckInteractive;
  Main.QueueStartupCommand(Request,'');Application.Run;
 finally Probe.Timer.Free;Probe.Free;Main.Free;end;
end;
var J:TJSONObject;Probe:TModalProbe;I:Integer;NewButton:TButton;
begin
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
 if ParamStr(1)='--peer' then begin try Peer;finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;Halt(0);end;
 if ParamStr(1)='--session' then begin PrepareCliProtocolOutput;Write(Output,'early diagnostic-probe ');end;
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 if ParamStr(1)='--session' then begin Session;RegisterDefaultGameVariant(nil);ClearRegisteredGames;Halt(0);end;
 Directory:=GetTempDir+'zgui-interactive-'+IntToStr(GetProcessID);ForceDirectories(Directory);RegisterPeers;
 Main:=TMainForm.Create(nil);Probe:=TModalProbe.Create;
 try
  try
   J:=Response('list_engines','OK');try Check(TJSONArray(J.Find('engines')).Count=4,'List existing registrations');finally J.Free;end;
   J:=Response('run_tournament engine1="missing" engine2_id=2','ERROR','UNKNOWN_ENGINE');
   try Check(J.Get('message','')='No engine named "missing" (see list_engines)','Unknown name gives actionable message');finally J.Free;end;
   Error('run_tournament engine1_id=1 engine2_id=3','GAME_MISMATCH');
   Error('run_tournament engine1_id=1 engine2_id=1','BAD_ARGUMENT');
   Error('run_tournament engine1_id=1 engine2_id=2 time=nan','BAD_ARGUMENT');
   Error('run_tournament engine1_id=1 engine2_id=2 ballot=','BAD_ARGUMENT');
   Error('run_tournament engine1_id=1 engine2_id=2 shuffle_opening_pairs=maybe','BAD_ARGUMENT');
   Error('run_tournament engine1_id=1 engine2_id=2 shuffle_opening_pairs=','BAD_ARGUMENT');
   Error('run_tournament engine1_id=1 engine2_id=2 shuffle_opening_pairs=true','BAD_ARGUMENT');
   Error('run_tournament engine1_id=1 engine2_id=2 time=0','CONFIGURE');
   Error('run_tournament engine1_id=1 engine2_id=2 concurrent=0','CONFIGURE');
   Error('query_tournament id=999','UNKNOWN_TOURNAMENT');
   Error('query_tournament id=999 sprt=maybe','BAD_ARGUMENT');
   Error('query_tournament id=999 sprt=','BAD_ARGUMENT');
   Error('stop_tournament id=999 sprt=true','BAD_ARGUMENT');
   Error('query_tournament id=999 pairs=maybe','BAD_ARGUMENT');
   Error('query_tournament id=999 pairs=','BAD_ARGUMENT');
   Error('query_tournament id=999 pairs=true','UNKNOWN_TOURNAMENT');
   Error('stop_tournament id=999 pairs=true','BAD_ARGUMENT');
   Error('stop_tournament id=999','UNKNOWN_TOURNAMENT');
   Error('stop_tournament','BAD_ARGUMENT');
   Error('stop_tournament id=-1','BAD_ARGUMENT');
   Error('stop_tournament id=0','UNKNOWN_TOURNAMENT');
   Error('stop_tournament id=1 extra=true','BAD_ARGUMENT');
   Check(Main.TournamentHost.Count=0,'Invalid fresh setups leave no tabs');
   LocaleSettings;RelativeBallot;ConfigurationChecks;RegistryChecks;Check(Main.TournamentHost.Count=0,'Registry errors create no tabs');
   Match(Chess,'CLI Chess 0','CLI Chess 1');Match(Draughts,'CLI Draughts 2','CLI Draughts 3');
   GuiTestConfirmationOnShow:=@Probe.Show;
   try ShowGuiOkDialog(Main,'Modal test','Commands must return BUSY');finally GuiTestConfirmationOnShow:=nil;end;
   J:=Response('list_engines','OK');J.Free;
   GuiTestConfirmationResult:=mrNo;
   Check(Main.TournamentHost.PrepareCloseAll and Main.TournamentHost.FinishCloseAll,'Normal GUI close policy still works');
   Error('query_tournament id=1','UNKNOWN_TOURNAMENT');Error('stop_tournament id=1','UNKNOWN_TOURNAMENT');
   NewButton:=nil;for I:=0 to Main.TournamentHost.ComponentCount-1 do
     if (Main.TournamentHost.Components[I] is TButton) and
       (TButton(Main.TournamentHost.Components[I]).Caption='New tournament') then NewButton:=TButton(Main.TournamentHost.Components[I]);
   Check(NewButton<>nil,'Existing New tournament toolbar remains available');NewButton.Click;
   Check(Main.TournamentHost.Count=1,'New tournament still works after closing command-created tabs');
   WriteLn('Interactive CLI GUI checks passed: ',Checks);
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);DumpExceptionBackTrace(Output);Halt(1);end;end;
 finally Probe.Free;Main.Free;RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
