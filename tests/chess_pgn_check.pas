program chess_pgn_check;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils, Classes, uChessPosition, uGameTree, uGameTreeActor, uGameTreeBuilder,
  uGameTreeNodeData, uGameFileMetadata, uGameTreePdn, uChessPgn, uGameFileReader,
  uGameOrchestrator;
var Checks: Integer=0; V: TChessVariant; A,B: TGameTreeActor; W: TStringList;
procedure Check(OK: Boolean; const Msg: string);
begin Inc(Checks); if not OK then raise Exception.Create(Msg); end;
procedure Execute(C: TGameTreeCommand);
begin try A.ExecuteCommand(C); Check(C.Accepted,C.ErrorText); finally C.Free; end; end;
function Export(Actor: TGameTreeActor; Lossless: Boolean=False): string;
var O: TGameTreePdnRenderOptions;
begin O:=DefaultGameTreePdnRenderOptions; O.FileFormat:=gffPgn; O.LosslessPgn:=Lossless;
  Result:=GameTreeToPdnTextEx(Actor.GameTree,O); end;
procedure RoundTrip(const S: string; Lossless: Boolean=False);
var Text,Text2: string;
begin
  W.Clear; ImportChessPgn(S,A,W); Text:=Export(A,Lossless);
  ImportChessPgn(Text,B,nil); Text2:=Export(B,Lossless);
  Check(Text=Text2,'Stable export differs:'#10+Text+#10+'SECOND:'#10+Text2);
end;
procedure Bad(const S,MessagePart: string);
var Before: string; Raised: Boolean; RootId: Int64;
begin
  Before:=Export(A,True); RootId:=A.GameTree.Root.NodeId; Raised:=False;
  try ImportChessPgn(S,A,nil); except on E:Exception do begin Raised:=True;
    Check(Pos(MessagePart,E.Message)>0,'Error '+E.Message+' expected '+MessagePart); end; end;
  Check(Raised,'Invalid input accepted'); Check(Export(A,True)=Before,'Invalid import changed tree');
  Check(A.GameTree.Root.NodeId=RootId,'Invalid import changed root identity');
end;
procedure Tests;
var D,E: TGameTreeNodeData; Tags: TGameFileTags; Header: TGameTreeHeaderInput;
  C: TGameTreeCommand; Text,Name: string; Reader: TChessPgnReader;
  Start: QWord; Edited: Boolean; I: Integer; Saved: TStringList; O: TGameTreePdnRenderOptions;
begin
  RoundTrip('[Event "Escaped \"event\" \\ club"] [Site "Amsterdam"] [Date "2026.10.28"] '+
    '[Round "3"] [White "José"] [Black "文字"] [Result "1-0"] [X_Custom "kept"] '+
    '{root engine: Stockfish 16} 1.e4! {score 2-1 in the match} '+
    '( {before} 1.d4 $146 {engine: literal} d5 (1...Nf6 {nested}) 2.c4) '+
    '(1.d4 $146 $5 {second comment} Nf6) e5 2.Nf3 Nc6 1-0');
  Check(W.Count>0,'Repeated variation warning');
  Check(A.GameTree.Root.ChildCount=2,'Repeated move merged');
  D:=A.GameTree.Root.Children[1].NodeData;
  Check(D.BeforeCommentText='before','Leading variation comment');
  Check(D.CommentText='engine: literal'+#10+'second comment','Comments merged in order literally');
  Check((Length(D.Nags)=2) and (D.Nags[0]=146) and (D.Nags[1]=5),'NAG union in order');
  Check(A.GameTree.Root.Children[1].ChildCount=2,'Merged continuations');
  Check(A.GameTree.MainlineNode[1].CommentText='score 2-1 in the match','Score prose retained');
  Check(A.GameTree.MainlineNode[1].EngineScore='','Prose is not analysis');
  Tags:=A.GameTree.ExtraTags; Tags[0].Value:='mutated';
  Check(A.GameTree.ExtraTags[0].Value='Amsterdam','Header array isolation');
  D:=A.GameTree.Root.Children[1].NodeData; D.Nags[0]:=0;
  Check(A.GameTree.Root.Children[1].NodeData.Nags[0]=146,'Node getter isolation');
  C:=A.CreateRestoreNodeDataCommand(A.GameTree.Root.Children[1].NodeId,D); D.Nags[0]:=8;
  Execute(C); Check(A.GameTree.Root.Children[1].NodeData.Nags[0]=0,'Command owns NAG array');
  RoundTrip('[Result "0-1"] 1.f3 e5 2.g4 Qh4# 0-1');
  RoundTrip('[Result "1/2-1/2"] 1.Nf3 Nf6 1/2-1/2');
  RoundTrip('[SetUp "1"] [FEN "4k3/8/8/8/8/8/8/R3K3 b - - 0 37"] '+
    '{initial} 37... Kf7 {black} 38.Ra7+ Ke6 *');
  Check(Pos('[SetUp "1"]',Export(A))>0,'Custom root FEN exported');
  RoundTrip('1.e4 a6 2.e5 d5 3.exd6 e.p. *');
  RoundTrip('[SetUp "1"] [FEN "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"] 1.a8=Q+ *');
  RoundTrip('1.Nf3 Nf6 2.g3 g6 3.Bg2 Bg7 4.O-O O-O *');
  Check(Pos('[FEN ',Export(A))=0,'Default FEN omitted');
  RoundTrip('1.e4 {[%eval -0.0001] [%clk 0:00:59.9999]} *');
  RoundTrip('1.e4 {[%eval'+#10+'0.25]} *');
  RoundTrip('1.e4 {[%eval 0.25] [%clk 0:03:00] [%emt 0:00:05] [%unknown keep]} '+
    'e5 {[%eval #-3] [%clk 0:02:59.5]} *');
  D:=A.GameTree.MainlineNode[1].NodeData;
  Check((D.EngineScore='0.25') and D.HasClockInfo and (D.WhiteRemainingSeconds=180) and
    D.HasMoveTime and (D.SecondsUsed=5),'Typed embedded commands');
  Check(D.CommentText='[%unknown keep]','Unknown embedded command literal');
  D.EnginePV:='e7e5 g1f3'; D.EnginePVDepth:='18'; D.AnnotatorScore:='0.31'; D.BeforeCommentText:='before';
  Execute(A.CreateRestoreNodeDataCommand(A.GameTree.MainlineNode[1].NodeId,D));
  Text:=Export(A,True); ImportChessPgn(Text,B,nil);
  E:=B.GameTree.MainlineNode[1].NodeData;
  Check((E.EnginePV=D.EnginePV) and (E.EnginePVDepth='18') and (E.AnnotatorScore='0.31'),'Opt-in lossless metadata');
  Check(Text=Export(B,True),'Lossless export stability'+#10+Text+#10+'SECOND'+#10+Export(B,True));
  O:=DefaultGameTreePdnRenderOptions; O.FileFormat:=gffPgn; O.ShowEngineScore:=False;
  Text:=GameTreeToPdnTextEx(A.GameTree,O);
  Check((Pos('[%eval 0.31]',Text)>0) and (Pos('[%eval 0.25]',Text)=0),'PGN score export filters');
  O.LosslessPgn:=True; O.ShowClocks:=False; O.ShowEngineFullPV:=False; O.ShowEnginePVMove:=False;
  ImportChessPgn(GameTreeToPdnTextEx(A.GameTree,O),B,nil); E:=B.GameTree.MainlineNode[1].NodeData;
  Check((E.EnginePV='') and not E.HasClockInfo,'Lossless mode respects export filters');
  Check(Pos('(1... e5',Export(A))=0,'PV not a real variation');
  Bad('1.e4 e5 2.Ke5 *','illegal'); Bad('1.e4 (1.d4 *','unterminated');
  Bad('1.e4','termination'); Bad('[Result "1-0"] 1.e4 0-1','disagree');
  Bad('[Event "x"] [Event "y"] *','duplicate'); Bad('[SetUp "1"] *','FEN');
  Bad('1.e4 -- *','null moves'); Bad('1.e4 Z0 *','null moves'); Bad('1.e4 e.p. *','en passant');
  RoundTrip('[White "M'+#$FC+'ller"] 1.e4'+#$A0+'e5 *');
  Check(A.GameTree.WhiteName='M'+#$C3#$BC+'ller','CP1252 conversion got '+A.GameTree.WhiteName); Check(W.Count=1,'Encoding warning');
  RoundTrip('1.e4 ( {start} 1.d4 {branch} d5) e5 *',True);
  RoundTrip('{a literal } 1.e4 {line'+#13#10+'two} e5 *');
  RoundTrip('1.e4 ;closing } brace retained'+#10+'e5 *');
  Text:='Nf3 '; for I:=1 to 129 do Text+='(Nf3 ';
  Bad(Text+StringOfChar(')',129)+'*','nesting exceeds');
  // The collection browser indexes one bounded game at a time and defers SAN.
  Name:=GetTempFileName(GetTempDir,'zpg'); Reader:=TChessPgnReader.Create(V); Saved:=TStringList.Create;
  try
    Saved.Text:=#$EF#$BB#$BF+'% ignored * result'+#10+'[Event "first"] 1.e4 e5 *'+#10+'[Event "bad"] 1.Ke5 *'+#10+
      '[White "M'+#$FC+'ller"] 1.d4'+#$A0+'d5 1/2-1/2 {trailing comment}'; Saved.SaveToFile(Name);
    Reader.OpenFile(Name); Check(Reader.Entries.Count=3,'Multi-game index');
    Check(TGameFileEntry(Reader.Entries[1]).Deferred,'Other games stay deferred');
    TGameFileEntry(Reader.Entries[0]).Validate;
    Check(not TGameFileEntry(Reader.Entries[0]).Deferred,'Selected game validates');
    TGameFileEntry(Reader.Entries[1]).Validate;
    Check(Pos('illegal',TGameFileEntry(Reader.Entries[1]).ErrorText)>0,'Deferred bad SAN reported');
    TGameFileEntry(Reader.Entries[2]).ImportInto(A);
    Check((A.GameTree.MainlineCount=2) and (A.GameTree.MainlineNode[1].MoveText='d2d4'),'Selected game offset import');
    Check(Pos('CP1252',TGameFileEntry(Reader.Entries[2]).WarningsText)>0,'Collection encoding warning');
  finally Saved.Free; Reader.Free; DeleteFile(Name); end;
  // Two-pass timing includes the existing actor's validation, not a bypass.
  Text:=''; for I:=1 to 50 do Text+='Nf3 Nf6 Ng1 Ng8 ';
  Start:=GetTickCount64; ImportChessPgn(Text+'*',A,nil);
  WriteLn('Two-pass import: ',A.GameTree.MainlineCount,' plies in ',GetTickCount64-Start,' ms');
  Check(A.GameTree.MainlineCount=200,'Long game replay');
  Header:=GameTreeHeaderInput('tags-only','?','White','Black','*',V.DefaultStartingFEN,False,DefaultTimeControl);
  SetLength(Header.ExtraTags,1); Header.ExtraTags[0].Name:='Site'; Header.ExtraTags[0].Value:='kept';
  C:=A.CreateRebuildFromInputsCommand(Header,GameTreeMainlineInput(nil,nil,False,0,0,0,0),
    GameTreePvInput(False,0,'',''),GameTreePvInput(False,0,'',''));
  Header.ExtraTags[0].Value:='aliased'; Execute(C);
  Check(A.GameTree.ExtraTags[0].Value='kept','Header command isolation');
  Check(GameTreeHasContent(A.GameTree),'Tag-only tree protected');
  Execute(A.CreateRebuildFromInputsCommand(GameTreeHeaderInput('cleared','?','White','Black','*',V.DefaultStartingFEN,False,DefaultTimeControl),
    GameTreeMainlineInput(nil,nil,False,0,0,0,0),GameTreePvInput(False,0,'',''),GameTreePvInput(False,0,'','')));
  Check(Length(A.GameTree.ExtraTags)=0,'Reset clears extra tags');
  Bad(StringOfChar(' ',MaxPgnGameBytes+1),'16 MiB');
  // Codec defaults and new metadata use the existing codec.
  D:=Default(TGameTreeNodeData); D.BeforeCommentText:='lead'; SetLength(D.Nags,2); D.Nags[0]:=0; D.Nags[1]:=255;
  Text:=EncodeNodeData(D,''); Check(DecodeNodeDataComment(Text,'',E,Edited),'New node-data codec');
  Check((E.BeforeCommentText='lead') and (Length(E.Nags)=2) and (E.Nags[1]=255),'New metadata decoded');
end;
begin
  V:=TChessVariant.Create; W:=TStringList.Create;
  A:=TGameTreeActor.Create(TGameTree.Create(V),True); B:=TGameTreeActor.Create(TGameTree.Create(V),True);
  try Tests; WriteLn('Chess PGN checks passed (',Checks,' checks)'); finally B.Free; A.Free; W.Free; V.Free; end;
end.
