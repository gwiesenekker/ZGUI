program sprt_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,StdCtrls,ExtCtrls,Grids,Graphics,CheckLst,Controls,FPJSON,JSONParser,
 uTournamentDialog,uTournamentGridModel,uTournamentStorage,uSprt,uSprtPanel,uGamePosition,uChessPosition,uDraughtsPosition,
 uGameGuiProfile,uEngineRegistry,uGameSetupTypes,uGuiDialogs,Dialogs;
type TGraphAccess=class(TSprtGraph)
 public procedure Hover(X,Y:Integer);
 end;
procedure TGraphAccess.Hover(X,Y:Integer);
begin MouseMove([],X,Y);end;
var Checks:Integer=0;Chess,Draughts:TGameVariant;Directory:string;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure RegisterEngines;
var E:TExternalEngineDefinition;L:TExternalEngineList;I:Integer;
begin
 L:=TExternalEngineList.Create;
 try
  for I:=0 to 5 do begin
   E:=TExternalEngineDefinition.Create;E.ExePath:=ExpandFileName(ParamStr(0));E.Arguments:='unused '+IntToStr(I);
   if I<3 then begin E.Kind:=eekUci;E.UciId:='SPRT UCI '+IntToStr(I);end
   else begin E.Kind:=eekHub;E.HubId:='SPRT Hub '+IntToStr(I);end;L.Add(E);
  end;
  SaveExternalEngines(EnginesJsonFileName,L);
 finally L.Free;end;
end;
procedure VariantCheck(V:TGameVariant);
var D,Loaded:TTournamentDialog;P,LoadedPanel:TSprtPanel;C,Old:TSprtConfig;Defs:TExternalEngineList;G:TStringGrid;
 S:TGameSetup;MessageText,Name,Before,GamesText,Identity:string;
 Lines,Ballot:TStringList;J,Doc:TJSONObject;I,AIndex,BIndex,FontSize:Integer;Failed:Boolean;Graph:TSprtGraph;Preview:TSprtReport;Y,PointIndex:Integer;Image:TBitmap;Png:TPortableNetworkGraphic;Status:TLabel;
 procedure WinRow(Row:Integer);
 begin
  G.Row:=Row;Check(D.GameSetupForRow(Row,S),'Existing row setup');
  if EngineIdentityKey(S.WhiteEngine)=C.CandidateKey then D.SetSelectedResult(V.ResultText(goWhiteWins))
  else D.SetSelectedResult(V.ResultText(goBlackWins));
 end;
 procedure Query;
 begin if J<>nil then J.Free;J:=D.SprtSnapshot;Check(J.Get('available',False),'Shared SPRT snapshot available: '+J.Get('reason',''));end;
begin
 D:=TTournamentDialog.Create(nil,V);Defs:=TExternalEngineList.Create;Lines:=TStringList.Create;Ballot:=TStringList.Create;J:=nil;
 try
  D.Show;Application.ProcessMessages;
  P:=TSprtPanel(D.FindComponent('TournamentSprt'));Check((P<>nil) and not P.Expanded,'SPRT starts collapsed');
  Status:=TLabel(P.FindComponent('SprtStatus'));Check((Status<>nil) and not Status.WordWrap and not Status.ShowHint and not Status.ParentShowHint,'SPRT has a single-line status without hover text');
  LoadExternalEngines(EnginesJsonFileName,Defs);if V=Chess then AIndex:=0 else AIndex:=3;BIndex:=AIndex+1;
  C:=DefaultSprtConfig;C.CandidateKey:=EngineIdentityKey(Defs[AIndex]);C.BaselineKey:=EngineIdentityKey(Defs[BIndex]);C.Elo1:=400;
  P.ApplyConfig(C);C:=P.Config;Check(C.BeforePlay and C.Stored and not C.HasStarted,'Explicit pre-play settings recorded');
  for I:=1 to 6 do Ballot.Add(V.DefaultStartingFEN);
  Name:=Directory+'/'+GameVariantId(V)+'.fen';Ballot.SaveToFile(Name);D.LoadBallotFromFile(Name);
  Check(D.CreatePairing(MessageText,True),'Use existing multi-engine ballot pairing: '+MessageText);
  G:=TStringGrid(D.FindComponent('TournamentPairings'));Check(G.RowCount=37,'Three engines, six openings, ordinary game rows');
  Query;Check((J.Get('pairs_total',0)=6) and (J.Get('mode','')='configured_before_play'),'Plan survives pair creation');
  // Complete later pairs first, leaving opening one unfinished.
  for I:=1 to G.RowCount-1 do begin
   D.GameSetupForRow(I,S);
   if ((EngineIdentityKey(S.WhiteEngine)=C.CandidateKey) and (EngineIdentityKey(S.BlackEngine)=C.BaselineKey)) or
      ((EngineIdentityKey(S.WhiteEngine)=C.BaselineKey) and (EngineIdentityKey(S.BlackEngine)=C.CandidateKey)) then
     if StrToInt(G.Cells[TournamentColRound,I])>1 then WinRow(I);
  end;
  Query;Check((J.Get('pairs_complete',0)=5) and (J.Get('pairs_included',-1)=0) and (J.Get('waiting_at_pair',0)=1),'Wait for earliest missing pair');
  Check(Pos('SPRT incomplete',Status.Caption)=1,'Idle incomplete tournament is not described as still collecting');
  P.ShowReport(P.Report,'',True);
  Check(Pos('SPRT waiting for opening pair 1',Status.Caption)=1,'Running comparison identifies an out-of-order blocking pair');
  Preview:=P.Report;Preview.Complete:=0;Preview.PrefixComplete:=0;
  P.ShowReport(Preview,'',True);
  Check(Pos('SPRT inconclusive so far',Status.Caption)=1,'Running without a blocked completed pair shows progress');
  Query;

  for I:=1 to G.RowCount-1 do begin
   D.GameSetupForRow(I,S);
   if (((EngineIdentityKey(S.WhiteEngine)=C.CandidateKey) and (EngineIdentityKey(S.BlackEngine)=C.BaselineKey)) or
      ((EngineIdentityKey(S.WhiteEngine)=C.BaselineKey) and (EngineIdentityKey(S.BlackEngine)=C.CandidateKey))) and
      (StrToInt(G.Cells[TournamentColRound,I])=1) then WinRow(I);
  end;
  Query;Check((J.Get('decision','')='h1') and (J.Get('decision_pair',0)=5) and
    (J.Get('pairs_included',0)=5) and (J.Get('later_complete',0)=1),'First crossing frozen during full fixed match');
  Check(J.Get('mode','')='amended','Referee results distinguished from untouched planned evidence');
  Check((Pos('SPRT favours H1 (+400 Elo)',Status.Caption)=1) and (Pos('after 5 opening pairs',Status.Caption)>0),'Boundary status names the hypothesis, Elo and evidence sample');
  Check(Abs(J.Get('llr',0.0)-P.Report.LLR)<1e-12,'GUI and CLI use exactly the same report');
  Old:=P.Config;P.ApplyConfig(Old);Check(P.Config.BeforePlay=Old.BeforePlay,'Unchanged Apply preserves declaration');
  C:=P.Config;C.Elo1:=500;P.ApplyConfig(C);Check(not P.Config.BeforePlay,'Changing hypotheses after play is exploratory');
  Lines.LoadFromFile(D.SaveFileName);Doc:=TJSONObject(GetJSON(Lines.Text));
  try GamesText:=Doc.Find('games').AsJSON;finally Doc.Free;end;
  // The existing standings checkboxes must not redefine the comparison.
  with TCheckListBox(D.FindComponent('TournamentEngines')) do begin Checked[0]:=False;Checked[1]:=False;end;
  Query;Check((P.Config.CandidateKey=C.CandidateKey) and (J.Get('pairs_total',0)=6),'Roster/table filtering preserves selected head-to-head');
  TButton(P.FindComponent('SprtSwap')).Click;Query;
  Check((J.Get('decision','')='h0') and (J.Get('decision_pair',0)=2),'Swap reverses candidate perspective');
  Check(G.RowCount=37,'SPRT changes never change the schedule');
  Lines.LoadFromFile(D.SaveFileName);Doc:=TJSONObject(GetJSON(Lines.Text));
  try Check(Doc.Find('games').AsJSON=GamesText,'Role/settings changes leave game records unchanged');finally Doc.Free;end;
  TButton(P.FindComponent('SprtToggle')).Click;Check(P.Expanded,'Pane expands');
  Application.ProcessMessages;Graph:=TSprtGraph(P.FindComponent('SprtGraph'));Graph.Repaint;PointIndex:=-1;
  for Y:=0 to Graph.Height-1 do begin
   PointIndex:=Graph.PointAt(Graph.Width-12,Y);
   if PointIndex>=0 then begin TGraphAccess(Graph).Hover(Graph.Width-12,Y);Break;end;
  end;
  Check((PointIndex>=0) and (Pos('Opening pair 2',Graph.Hint)>0) and (Pos('LLR:',Graph.Hint)>0) and
    (Pos('First H0 crossing',Graph.Hint)>0) and (Pos('Estimated Elo: -infinity',Graph.Hint)>0),'Graph points expose pair, value and first crossing');
  Preview:=Default(TSprtReport);SetLength(Preview.Trace,1);Preview.Trace[0].Opening:=1;Preview.Trace[0].MeanScore:=0.75;Preview.Included:=1;
  Graph.SetReport(Preview);Check(Pos('Estimated Elo: +190.8',Graph.PointHint(0))>0,'Finite prefix score converts to logistic Elo');Graph.SetReport(P.Report);
  Preview:=Default(TSprtReport);Preview.Decision:='continue';Preview.Total:=79;Preview.Complete:=79;Preview.Included:=79;Preview.PrefixComplete:=79;
  P.ShowReport(Preview,'',False);
  Check(Status.Caption='SPRT inconclusive — all 79 opening pairs included.','Finished complete match does not ask for more evidence');
  Check((Pos(LineEnding,Status.Caption)=0) and not Status.WordWrap,'Descriptive status stays on one physical line');
  Query;

  for FontSize:=10 to 16 do if FontSize in [10,16] then begin
   D.Font.Size:=FontSize;D.SetBounds(0,0,1250,900);D.RefreshLayout;Application.ProcessMessages;
   Check(TStringGrid(P.FindComponent('SprtCounts')).Height>=6*TStringGrid(P.FindComponent('SprtCounts')).DefaultRowHeight,'All count rows measured');
   Check(P.Height<D.ClientHeight,'Expanded pane remains within tournament');
   if GetEnvironmentVariable('ZGUI_SPRT_CAPTURE')<>'' then begin
    D.Repaint;Application.ProcessMessages;Image:=D.GetFormImage;Png:=TPortableNetworkGraphic.Create;
    try Png.Assign(Image);Png.SaveToFile(GetEnvironmentVariable('ZGUI_SPRT_CAPTURE')+'-'+GameVariantId(V)+'-'+IntToStr(FontSize)+'.png');finally Png.Free;Image.Free;end;
   end;
   P.Width:=360;P.RefreshMeasurements;Application.ProcessMessages;
  end;
  TButton(P.FindComponent('SprtToggle')).Click;D.SetBounds(0,0,1000,700);D.RefreshLayout;Application.ProcessMessages;
  Check(not P.Expanded and (P.Height<80),'Collapsed pane remains compact after font changes');
  Name:=Directory+'/'+GameVariantId(V)+'.json';D.SaveTournamentToFile(Name);Identity:=D.TournamentIdentity;
  Lines.LoadFromFile(Name);Before:=Lines.Text;
  Loaded:=TTournamentDialog.Create(nil,V);
  try
   Loaded.Show;Application.ProcessMessages;Loaded.LoadTournamentFromFile(Name);
   LoadedPanel:=TSprtPanel(Loaded.FindComponent('TournamentSprt'));
   Check((LoadedPanel.Report.Decision='h0') and (LoadedPanel.Report.DecisionPair=2),'Fresh load updates visible comparison without a query');
   TButton(LoadedPanel.FindComponent('SprtToggle')).Click;
   Check((LoadedPanel.Config.CandidateKey=P.Config.CandidateKey) and (LoadedPanel.Report.Included=2),'Opening loaded pane shows restored selection and evidence immediately');
  finally Loaded.Free;end;
  D.ResetForVariant(V);Check(P.Report.Total=0,'Reset clears the previous visible evidence');
  D.LoadTournamentFromFile(Name);
  Check((P.Report.Decision='h0') and (P.Report.DecisionPair=2),'Reload refreshes visible report before query');Query;
  Check((D.TournamentIdentity=Identity) and (J.Get('decision','')='h0') and (J.Get('decision_pair',0)=2),'Save/load replays same configured decision');
  Lines.LoadFromFile(Name);Check(Lines.Text=Before,'Reading SPRT leaves saved file unchanged');
  Doc:=TJSONObject(GetJSON(Before));try TJSONObject(Doc.Find('sprt_view')).Floats['alpha']:=0;Lines.Text:=Doc.AsJSON;Lines.SaveToFile(Name);finally Doc.Free;end;
  Failed:=False;try D.LoadTournamentFromFile(Name);except on E:EConvertError do Failed:=True;end;
  Check(Failed and (D.TournamentIdentity=Identity),'Malformed SPRT metadata refuses before replacing tournament');
  Lines.Text:=Before;Lines.SaveToFile(Name);
 finally J.Free;D.Free;Defs.Free;Lines.Free;Ballot.Free;end;
end;
procedure LegacyLoadCheck(V:TGameVariant);
var D,Loaded:TTournamentDialog;Defs:TExternalEngineList;Settings:TTournamentMatchSettings;
 P:TSprtPanel;G:TStringGrid;Lines:TStringList;Doc:TJSONObject;Base,I:Integer;MessageText,FileName,Before:string;
begin
 D:=TTournamentDialog.Create(nil,V);Loaded:=nil;Defs:=TExternalEngineList.Create;Lines:=TStringList.Create;
 try
  LoadExternalEngines(EnginesJsonFileName,Defs);if V=Chess then Base:=0 else Base:=3;
  Settings:=Default(TTournamentMatchSettings);Settings.Engine1Key:=EngineIdentityKey(Defs[Base]);Settings.Engine2Key:=EngineIdentityKey(Defs[Base+1]);
  D.ConfigureNewTournament(Settings);Check(D.CreatePairing(MessageText,True),'Existing two-engine pairing');
  G:=TStringGrid(D.FindComponent('TournamentPairings'));
  for I:=1 to 2 do begin G.Row:=I;D.SetSelectedResult(V.ResultText(goDraw));end;
  FileName:=Directory+'/'+GameVariantId(V)+'-legacy.json';D.SaveTournamentToFile(FileName);Lines.LoadFromFile(FileName);Before:=Lines.Text;
  Doc:=TJSONObject(GetJSON(Before));try Check(Doc.Find('sprt_view')=nil,'Legacy fixture has no saved SPRT design');finally Doc.Free;end;
  Loaded:=TTournamentDialog.Create(nil,V);Loaded.Show;Application.ProcessMessages;
  P:=TSprtPanel(Loaded.FindComponent('TournamentSprt'));
  for I:=1 to 2 do begin
   Loaded.LoadTournamentFromFile(FileName);
   Check((P.Config.CandidateKey<>'') and (P.Config.BaselineKey<>''),'Initial/repeated legacy load initializes underlying engine keys');
   Check((TComboBox(P.FindComponent('SprtCandidate')).ItemIndex>=0) and
    (TComboBox(P.FindComponent('SprtBaseline')).ItemIndex>=0),'Displayed selections match underlying legacy design');
   Check((P.Report.Total=1) and (P.Report.Included=1) and (P.Report.Counts[2]=1),'Initial/repeated legacy load immediately shows paired draw evidence');
   Check(TLabel(P.FindComponent('SprtStatus')).Caption='SPRT inconclusive — the opening pair is complete.','Finished draw-only event has a clear final inconclusive status');
   Application.ProcessMessages;
   Check(not P.Config.Stored and not P.Config.BeforePlay,'Automatic legacy selection stays exploratory after native events');
  end;
  Lines.LoadFromFile(FileName);Check(Lines.Text=Before,'Legacy display refresh does not write SPRT metadata');
 finally Loaded.Free;D.Free;Defs.Free;Lines.Free;end;
end;

begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 RegisterGame(Chess,ChessGuiProfile);RegisterGame(Draughts,DraughtsGuiProfile);RegisterDefaultGameVariant(Chess);
 Directory:=GetTempDir+'zgui-sprt-gui-'+IntToStr(GetProcessID);ForceDirectories(Directory);RegisterEngines;
 try
  VariantCheck(Chess);VariantCheck(Draughts);LegacyLoadCheck(Chess);LegacyLoadCheck(Draughts);WriteLn('SPRT GUI checks passed: ',Checks);
 finally RegisterDefaultGameVariant(nil);ClearRegisteredGames;end;
end.
