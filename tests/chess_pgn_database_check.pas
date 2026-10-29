program chess_pgn_database_check;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,uChessPosition,uChessPgn,uChessPgnLexer,
 uGamePosition,uGameTree,uGameTreeActor,uGameTreePdn,uGameFileMetadata,uDraughtsPosition;
var Checks:Integer=0;V:TChessVariant;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
function Export(A:TGameTreeActor):string;
var O:TGameTreePdnRenderOptions;
begin O:=DefaultGameTreePdnRenderOptions;O.FileFormat:=gffPgn;O.LosslessPgn:=True;
 Result:=GameTreeToPdnTextEx(A.GameTree,O);end;
procedure RoundTrip(const Text:string);
var G,H:TChessPgnDatabaseGame;P:TGamePosition;A,B:TGameTreeActor;I:Integer;
 W:TStringList;
begin
 W:=TStringList.Create;G:=ReadChessPgnDatabaseGame(Text,V,W);
 try
  H:=ReadChessPgnDatabaseGame(G.CompletePgn,V);
  try
   Check(G.CompletePgn=H.CompletePgn,'Canonical token output is idempotent');
   Check(GameFileTagsEqual(G.Tags,H.Tags),'All tags preserved');
  finally H.Free;end;
  Check(G.PositionKeys.Count=G.Moves.Count+1,'Initial through terminal keys');
  A:=TGameTreeActor.Create(TGameTree.Create(V),True);
  B:=TGameTreeActor.Create(TGameTree.Create(V),True);P:=V.CreatePositionFromFEN(G.StartingFEN);
  try
   ImportChessPgn(Text,A,nil);ImportChessPgn(G.CompletePgn,B,nil);
   Check(Export(A)=Export(B),'GUI lossless export preserves tags, annotations and variations'+#10+Export(A)+#10+'SECOND'+#10+Export(B));
   Check(A.GameTree.MainlineCount=G.Moves.Count,'Only mainline moves indexed');
   for I:=0 to G.Moves.Count-1 do begin
    Check(G.PositionKeys[I]=P.PositionKey,'Position key before move');
    Check(G.Moves[I]=A.GameTree.MainlineNode[I+1].MoveText,'Canonical mainline UCI');
    P.PlayMove(G.Moves[I]);
   end;
   Check(G.PositionKeys[G.Moves.Count]=P.PositionKey,'Terminal key');
   Check(G.ResultText=A.GameTree.ResultText,'Result preserved');
  finally P.Free;B.Free;A.Free;end;
 finally G.Free;W.Free;end;
end;
procedure Bad(const Text,Reason:string);
var G:TChessPgnDatabaseGame;Rejected:Boolean;
begin
 Rejected:=False;
 try G:=ReadChessPgnDatabaseGame(Text,V);G.Free;
 except on E:EPgnSyntaxError do begin Rejected:=True;Check(Pos(Reason,E.Message)>0,E.Message);end;end;
 Check(Rejected,'Database mode rejected invalid grammar/rules: '+Copy(Text,1,80));
end;
type TScanner=class
 Count,Errors,ProgressCalls,CancelAfter:Integer;
 LastBytes,Total:Int64;
 CancelAtStart,CancelOnBlock:Boolean;
 procedure Game(const Text,ErrorText:string;BytesRead,TotalBytes:Int64;var Cancel:Boolean);
 procedure Progress(BytesRead,TotalBytes:Int64;var Cancel:Boolean);
end;
procedure TScanner.Game(const Text,ErrorText:string;BytesRead,TotalBytes:Int64;var Cancel:Boolean);
var G:TChessPgnDatabaseGame;
begin
 Inc(Count);Check(BytesRead>=LastBytes,'Game progress monotonic');LastBytes:=BytesRead;
 if ErrorText<>'' then Inc(Errors)
 else try G:=ReadChessPgnDatabaseGame(Text,V);G.Free;
 except on E:EPgnSyntaxError do Inc(Errors);end;
 Cancel:=(CancelAfter>0) and (Count>=CancelAfter);
end;
procedure TScanner.Progress(BytesRead,TotalBytes:Int64;var Cancel:Boolean);
begin
 Inc(ProgressCalls);Total:=TotalBytes;
 Check(BytesRead>=LastBytes,'Scanner progress monotonic');LastBytes:=BytesRead;
 Cancel:=CancelAtStart or (CancelOnBlock and (BytesRead>=65536));
end;
procedure Scanning;
var S:TScanner;R:TChessPgnReader;Name,Text:string;F:TStringStream;I:Integer;
 procedure Save(const Text:string);
 begin F:=TStringStream.Create(Text);try F.SaveToFile(Name);finally F.Free;end;end;
 procedure Run(Expected,Errors:Integer);
 begin
  S.Count:=0;S.Errors:=0;S.LastBytes:=0;S.ProgressCalls:=0;
  R.ScanFile(Name,@S.Game,@S.Progress);
  Check(S.Count=Expected,'Streaming entry count: '+IntToStr(S.Count));
  Check(S.Errors=Errors,'Streaming error count');
  Check(R.Entries.Count=0,'Streaming retains no entry list');
 end;
begin
 S:=TScanner.Create;R:=TChessPgnReader.Create(V);Name:=GetTempFileName(GetTempDir,'zps');
 try
  Save(#$EF#$BB#$BF+'% escaped *'+#10+'[Event "one"] 1.e4 e5 *'+#10+
   '[Event "bad"] 1.Ke5 *'+#10+'[Event "three"] 1.d4 d5 1/2-1/2');
  Run(3,1);Check(S.ProgressCalls>=2,'Start/end progress');
  S.CancelAfter:=1;Run(1,0);S.CancelAfter:=0;
  S.CancelAtStart:=True;Run(0,0);S.CancelAtStart:=False;
  Save('[Event "one"] 1.e4 {unfinished'+#10+'[Event "two"] 1.d4 *');Run(1,1);
  Save('[Event "one"] 1.e4 (1.d4'+#10+'[Event "two"] 1.c4 *');Run(1,1);
  Save('[Event "one"] 1.e4 {literal'+#10+'[Event "not a header"]'+#10+'} e5 *');Run(1,0);
  Save('1.e4 ;closing } brace'+#10+'e5 *'+#10+'1.d4 d5 *');Run(2,0);
  // Cancellation is checked before dispatching any part of a long game.
  S.CancelOnBlock:=True;
  Save('1.e4 {'+StringOfChar('x',200000)+'} e5 *');Run(0,0);S.CancelOnBlock:=False;
  // An oversized game reports once, without loading its text; then continue.
  Save('1.e4 {'+StringOfChar('x',MaxPgnGameBytes)+'} *'+#10+'1.d4 d5 *');Run(2,1);
  Text:='';for I:=1 to 2000 do Text+='1.Nf3 Nf6 *'+#10;
  Save(Text);Run(2000,0);
 finally DeleteFile(Name);R.Free;S.Free;end;
end;
var I:Integer;Text,Root:string;F:TStringList;G:TChessPgnDatabaseGame;W:TStringList;Rejected:Boolean;
begin
 V:=TChessVariant.Create;
 try
  Rejected:=False;
  try G:=ReadChessPgnDatabaseGame('*',DraughtsVariant);G.Free;
  except on E:EArgumentException do Rejected:=True;end;
  Check(Rejected,'Database chess mode rejects a draughts variant');
  RoundTrip('[Event "Escaped \"quote\" \\ path"] [White "José"] [Black "文字"] '+
   '[Date "2026.??.??"] [ECO "A00"] [WhiteElo "?"] [X_Custom "retained"] '+
   '{root} 1.e4! {[%eval 0.25] [%clk 0:03:00] [%emt 0:00:05]} '+
   '( {before} 1.d4 $146 {branch} d5 (1... Nf6 {nested}) 2.c4) e5 2.Nf3 Nc6 *');
  RoundTrip('1.e4 (1.d4 d5) (1.d4 Nf6) e5 *');
  RoundTrip('[SetUp "1"] [FEN "4k3/8/8/8/8/8/8/R3K3 b - - 0 37"] 37... Kf7 38.Ra7+ Ke6 *');
  RoundTrip('[SetUp "1"] [FEN "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"] 1.a8=Q+ *');
  RoundTrip('1.e4 a6 2.e5 d5 3.exd6 e.p. *');
  RoundTrip('1.Nf3 Nf6 2.g3 g6 3.Bg2 Bg7 4.0-0 0-0 *');
  RoundTrip('1.e4 ;literal } closing brace'+#10+'e5 *');RoundTrip('{} 1.e4 {} *');
  RoundTrip('1.e4 {literal'+#10+'[square brackets]'+#10+'%percent} e5 *');
  RoundTrip('[Result "0-1"] 1.f3 e5 2.g4 Qh4# 0-1');RoundTrip('*');
  W:=TStringList.Create;
  try G:=ReadChessPgnDatabaseGame('[White "M'+#$FC+'ller"] 1.e4'+#$A0+'e5 *',V,W);
   try Check(W.Count=1,'Per-game CP1252 conversion warning');Check(GameFileTagValue(G.Tags,'White','')='M'+#$C3#$BC+'ller','UTF-8 tag');finally G.Free;end;
  finally W.Free;end;
  Bad('1.e4 (1.Ke5) e5 *','illegal');Bad('1.e4 (1.d4 *','unterminated');
  Bad('1.e4 () *','empty variation');Bad('$1 1.e4 *','NAG without');Bad('(*) *','variation without');
  Bad('[Event "a"] [Event "b"] *','duplicate');Bad('[SetUp "1"] *','FEN');
  Bad('[Result "1-0"] 1.e4 0-1','disagree');Bad('1.e4','termination');
  Bad('1.e4 e.p. *','en passant');Bad('1.Z0 *','null moves');Bad('1.e4 $256 *','NAG');
  Text:='Nf3 ';for I:=1 to 129 do Text+='(Nf3 ';Bad(Text+StringOfChar(')',129)+'*','nesting exceeds');
  // The final record newline also belongs to the stored-text size cap.
  Text:='';for I:=1 to 16 do Text+='{'+StringOfChar('x',1048570)+'} ';
  Text+='{'+StringOfChar('x',44)+'} *';
  Check(Length(Text)=MaxPgnGameBytes,'Canonical size-boundary fixture');
  Bad(Text,'canonical PGN exceeds');
  Root:=GetEnvironmentVariable('GWDGUI_ROOT');if Root='' then Root:=GetCurrentDir;
  F:=TStringList.Create;
  try F.LoadFromFile(IncludeTrailingPathDelimiter(Root)+'tests/fixtures/chess-long-variations.pgn');RoundTrip(F.Text);finally F.Free;end;
  Scanning;
  WriteLn('Chess PGN database output checks passed (',Checks,' checks)');
 finally V.Free;end;
end.
