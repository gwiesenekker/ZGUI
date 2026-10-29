program chess_tournament_record_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,FPJSON,JSONParser,uTournamentResults,
 uTournamentModel,uTournamentPairing,uTournamentStorage,uTournamentGameRecord,
 uGameTreePdn,uChessPosition,uChessPgn,uGameTree,uGameTreeActor;
var Checks:Integer=0;FileName,Projection:string;V:TChessVariant;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure WriteFile(const S:string);
var L:TStringList;
begin L:=TStringList.Create;try L.Text:=S;L.SaveToFile(FileName);finally L.Free;end;end;
procedure ResultsAndPairings;
var Engines,W,B,R,Rounds:TStringList;Table:TTournamentCrossTable;Pair:TTournamentPairingRound;
 I:Integer;
begin
 Check(ParseTournamentResult('1-0')=trUnknown,'Legacy results reject chess spellings');
 Check(ParseTournamentResult('2-0',gffPgn)=trUnknown,'Chess results reject draughts spellings');
 Check(ParseTournamentResult('1-0',gffPgn)=trWhiteWin,'Chess win');
 Check(ParseTournamentResult('1/2-1/2',gffPgn)=trDraw,'Chess draw');
 Check(ParseTournamentResult('0-1',gffPgn)=trBlackWin,'Chess loss');
 Engines:=TStringList.Create;W:=TStringList.Create;B:=TStringList.Create;
 R:=TStringList.Create;Rounds:=TStringList.Create;
 try
  Engines.Add('A');Engines.Add('B');Engines.Add('C');Engines.Add('D');Engines.Add('E');
  Pair:=BuildTournamentPairingRound(False,False,Engines,W,B,R,Rounds,gffPgn);
  Check(Length(Pair.Pairings)=10,'Five-player single round robin keeps existing pairings');
  Pair:=BuildTournamentPairingRound(False,True,Engines,W,B,R,Rounds,gffPgn);
  Check(Length(Pair.Pairings)=20,'Five-player double round robin');
  W.Add('A');B.Add('B');R.Add('1-0');Rounds.Add('1');
  W.Add('B');B.Add('C');R.Add('1/2-1/2');Rounds.Add('1');
  BuildTournamentCrossTable(Engines,W,B,R,Table,gffPgn);
  Check((Table.Points[0]=2) and (Table.Points[1]=1) and (Table.Points[2]=1),'Internal half-point arithmetic stays intact');
  Check(FormatTournamentSB(Table.Points[1],gffPgn)='0.5','Chess point display');
  Check((Table.SB[0]=1) and (FormatTournamentSB(Table.SB[0],gffPgn)='0.5'),'Chess SB scales by two, not four');
  Check(FormatTournamentSB(Table.SB[1],gffPgn)='0.25','Chess SB retains quarter-point precision');
  Check((Table.Matrix[0,1]='1W') and (Table.Matrix[1,2]='0.5W'),'Chess matrix display');
  Check(TournamentAllResultsKnown(W,B,R,gffPgn) and not TournamentAllResultsKnown(W,B,R),'All-result check uses document format');
  R[1]:='*';Check(not TournamentAllResultsKnown(W,B,R,gffPgn),'Unknown result blocks Swiss advancement');
  W.Clear;B.Clear;R.Clear;Rounds.Clear;
  Pair:=BuildTournamentPairingRound(True,False,Engines,W,B,R,Rounds,gffPgn);
  I:=0;while (I<Length(Pair.Pairings)) and (Pair.Pairings[I].Black<>'BYE') do Inc(I);
  Check(I<Length(Pair.Pairings),'Odd-player Swiss retains its existing BYE');
 finally Rounds.Free;R.Free;B.Free;W.Free;Engines.Free;end;
end;
procedure Records;
var Rec:TTournamentGameRecord;J:TJSONObject;Actor:TGameTreeActor;W:TStringList;Text,S:string;I,P:Integer;
const Names:array[0..6]of string=('Event','Site','Date','Round','White','Black','Result');
begin
 Rec:=TTournamentGameRecord.Create;Actor:=TGameTreeActor.Create(TGameTree.Create(V),True);W:=TStringList.Create;
 try
  Text:='[Event "Captured"]'+LineEnding+'[Site "Test"]'+LineEnding+'[Date "????.??.??"]'+LineEnding+
   '[Round "?"]'+LineEnding+'[White "White"]'+LineEnding+'[Black "Black"]'+LineEnding+'[Result "*"]'+LineEnding+LineEnding+
   '1. e4 {a comment [%clk 0:01:00]} (1. d4 d5) e5 *';
  ImportChessPgn(Text,Actor,W);
  Rec.StartDate:='2026.10.29';Rec.RecordPlayedGame(Text,'*');
  S:=Rec.RenderGame(gffPgn,'id','Event "quoted"'+LineEnding+'next','1','2','W','B',ChessStartingFEN);
  P:=0;for I:=0 to High(Names) do begin
   Check(Pos('['+Names[I]+' ',S)>P,'Seven Tag Roster order');P:=Pos('['+Names[I]+' ',S);
  end;
  Check(Pos('[Date "2026.10.29"]',S)>0,'Start date replaces unknown roster date');
  Check(Pos('e4 {a comment [%clk 0:01:00]} (1. d4 d5) e5',S)>0,'Movetext/comments/RAV preserved without replay');
  Check(Pos('[Event "Event \"quoted\" next"]',S)>0,'Tournament tag values escape quotes and line breaks');
  ImportChessPgn(S,Actor,W);Check(Actor.GameTree.Root.ChildCount=2,'Existing importer reads tournament variations');
  Rec.OverrideResult('1/2-1/2');Projection:=Rec.RenderGame(gffPgn,'id','Event','1','2','W','B',ChessStartingFEN);
  Check(Pos('[PlayedResult "*"]',Projection)>0,'Manual result retains played provenance');
  ImportChessPgn(Projection,Actor,W);Check(Actor.GameTree.ResultText='1/2-1/2','Tag and final marker agree after override');
  J:=Rec.ToJson;try Check((J.Get('pdn','')=Text) and (J.Find('game_text')=nil),'Existing JSON key and captured text retained');finally J.Free;end;
  WriteFile(Projection);Check(PgnTournamentFileMatchesId(FileName,'id'),'Published PGN header ownership');
  WriteFile(Projection+StringReplace(Projection,'[TournamentId "id"]','[TournamentId "other"]',[]));
  Check(not PgnTournamentFileMatchesId(FileName,'id'),'Mixed identity is unowned');
  WriteFile(StringReplace(Projection,'[TournamentId "id"]','[TournamentId "id"]'+LineEnding+'[TournamentId "id"]',[]));
  Check(not PgnTournamentFileMatchesId(FileName,'id'),'Duplicate header is unowned');
  WriteFile(StringReplace(Projection,'[TournamentId "id"]','[TournamentId "id"',[]));
  Check(not PgnTournamentFileMatchesId(FileName,'id'),'Malformed identity header is unowned');
  WriteFile('');Check(not PgnTournamentFileMatchesId(FileName,'id'),'Empty PGN is unowned');
  Rec.OverrideResult('*');Rec.Reschedule;J:=Rec.ToJson;
  try Check((J.Get('attempt',0)=2) and (TJSONArray(J.Find('history')).Count=1) and
   (J.Get('start_date','')=''),'Attempt history retains prior record and clears start date');finally J.Free;end;
  Rec.OverrideResult('0-1');S:=Rec.RenderGame(gffPgn,'id','Manual','2','3','W','B','4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
  ImportChessPgn(S,Actor,W);Check((Actor.GameTree.ResultText='0-1') and
   (Pos('[SetUp "1"]',S)>0) and (Pos('0 37',S)>0),'Standings-only PGN uses existing exporter and custom root');
 finally W.Free;Actor.Free;Rec.Free;end;
end;
procedure Storage;
var J,Loaded:TJSONObject;Raised:Boolean;X:TJSONData;
 procedure Reject(Format:TGameFileFormat;const Msg:string);
 begin
  Raised:=False;try Loaded:=ReadTournamentDocument(FileName,Format);Loaded.Free;except on E:Exception do Raised:=True;end;
  Check(Raised,Msg);
 end;
begin
 J:=TJSONObject.Create;
 try
  J.Add('storage_version',3);J.Add('game_variant','chess');J.Add('notation_format','pgn');J.Add('force_ponder_off',True);
  J.Add('games',TJSONArray.Create);WriteFile(J.AsJSON);
  Loaded:=ReadTournamentDocument(FileName,gffPgn);Loaded.Free;Check(True,'Chess v3 accepted');
  Reject(gffPdn,'Draughts composition rejects chess v3');
  J.Booleans['force_ponder_off']:=False;WriteFile(J.AsJSON);Reject(gffPgn,'Unsupported ponder policy rejected');
  WriteFile('{"storage_version":2,"games":[{"result":"1-0","record":{"played_result":"1-0"}}]}');
  Reject(gffPdn,'T2 legacy document rejects chess result alias');
  Reject(gffPgn,'Chess composition rejects legacy draughts document');
  J.Booleans['force_ponder_off']:=True;X:=TJSONArray(J.Find('games'));
  TJSONArray(X).Add(TJSONObject.Create(['result','2-0','record',TJSONObject.Create(['played_result','2-0'])]));
  WriteFile(J.AsJSON);Reject(gffPgn,'Chess document rejects draughts result alias');
 finally J.Free;end;
end;
begin
 FileName:=GetTempFileName(GetTempDir(False),'chess-tour');V:=TChessVariant.Create;
 try ResultsAndPairings;Records;Storage;
  if ParamStr(1)<>'' then begin
   with TStringList.Create do try Text:=Projection;SaveToFile(ParamStr(1));finally Free;end;
  end;
  WriteLn('Chess tournament records passed (',Checks,' checks)');
 finally V.Free;DeleteFile(FileName);end;
end.
