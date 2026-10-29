program chess_database_check;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,SQLite3Conn,SQLDB,uGameDatabase,
 uGameTreePdn,uChessPosition,uDraughtsPosition,uGamePosition,uGameFileReader,uGameTree,uGameTreeActor;
var Checks:Integer=0;Base,Name,Pgn,Draughts,Text,Before:string;
 Db,Other:TGameDatabase;P:TChessPosition;List:TList;Imported,Duplicates,Errors,Total,I:Integer;
 C:TSQLite3Connection;T:TSQLTransaction;Q:TSQLQuery;Entry:TGameFileEntry;V:TChessVariant;Actor:TGameTreeActor;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure Clear;
var I:Integer;
begin for I:=0 to List.Count-1 do TObject(List[I]).Free;List.Clear;end;
procedure Save(const Text:string);
var F:TStringStream;
begin F:=TStringStream.Create(Text);try F.SaveToFile(Pgn);finally F.Free;end;end;
function Bytes(const Name:string):string;
var F:TFileStream;
begin F:=TFileStream.Create(Name,fmOpenRead);try SetLength(Result,F.Size);if Result<>'' then F.ReadBuffer(Result[1],F.Size);finally F.Free;end;end;
procedure Rejected(Database:TGameDatabase;const FileName:string);
var B:Boolean;Content,Current:string;
begin
 Content:=Bytes(FileName);Current:=Database.FileName;B:=False;
 try Database.OpenDatabase(FileName);except on E:EInvalidOperation do B:=True;end;
 Check(B,'Wrong format rejected');Check(Bytes(FileName)=Content,'Rejected file unchanged');Check(Database.FileName=Current,'Current database retained');
end;
procedure Stats;
var R:TDatabaseSearchResult;
begin
 Clear;Db.SearchPosition(P,List);Check(List.Count=1,'One initial continuation');R:=TDatabaseSearchResult(List[0]);
 Check(R.MoveText='g1f3','Canonical UCI continuation');Check(R.GameCount=5,'Occurrence count includes repetition');
 Check((R.Wins=1) and (R.Draws=1) and (R.Losses=1),'White WDL excludes unknown results');
 Clear;Db.LoadGamesForPosition(P,List,10,Total);Check((Total=4) and (List.Count=4),'Position game count is distinct');
 Check(Db.GamesForPositionExceedLimit(P,3,Total) and (Total=4),'Distinct game limit probe');
 P.PlayMove('g1f3');Clear;Db.SearchPosition(P,List);Check(List.Count=2,'Black has two continuations');
 for I:=0 to List.Count-1 do begin R:=TDatabaseSearchResult(List[I]);
  if R.MoveText='g8f6' then Check((R.GameCount=3) and (R.Wins=0) and (R.Draws=0) and (R.Losses=1),'Black perspective Nf6')
  else Check((R.MoveText='d7d5') and (R.GameCount=2) and (R.Wins=1) and (R.Draws=1),'Black perspective d5');
 end;P.LoadFromFEN(ChessStartingFEN);
end;
begin
 Base:=GetTempFileName(GetTempDir,'zdb');DeleteFile(Base);Name:=Base+'.chess';Draughts:=Base+'.draughts';Pgn:=Base+'.pgn';
 Db:=TGameDatabase.Create(gffPgn);Other:=TGameDatabase.Create;P:=TChessPosition.Create;List:=TList.Create;
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);Q:=TSQLQuery.Create(nil);
 V:=TChessVariant.Create;Actor:=TGameTreeActor.Create(TGameTree.Create(V),True);
 try
  Db.CreateDatabase(Name);Other.CreateDatabase(Draughts);
  Rejected(Db,Draughts);Rejected(Other,Name);Db.Close;Db.OpenDatabase(Name);
  Text:='[White "José"] [Black "棋手"] [Date "2026.??.??"] [ECO "A00"] [WhiteElo "2100"] [BlackElo "?"] '+
   '1.Nf3 {note [%eval 0.25]} (1.d4 d5) Nf6 2.Ng1 Ng8 3.Nf3 Nf6 *'+#10+
   '[Result "1-0"] 1.Nf3 Nf6 1-0'+#10+'[Result "1/2-1/2"] 1.Nf3 d5 1/2-1/2'+#10+
   '[Result "0-1"] 1.Nf3 d5 0-1'+#10+'1.e4 (1.Ke5) *';
  Save(Text);Db.ImportFile(Pgn,Imported,Duplicates,Errors);
  Check((Imported=4) and (Duplicates=0) and (Errors=1),'Import valid games, reject invalid RAV');Stats;
  Entry:=Db.LoadFileGameById(1);
  try Entry.Validate;Check(Entry.ErrorText='','Stored PGN validates');Entry.ImportInto(Actor);
   Check(Actor.GameTree.MainlineCount=6,'Selected full PGN mainline');
   Check(Actor.GameTree.Root.ChildCount=2,'Selected full PGN keeps RAV');
   Check(Pos('note',Actor.GameTree.MainlineNode[1].CommentText)>0,'Selected full PGN keeps comments');
  finally Entry.Free;end;
  Db.ImportFile(Pgn,Imported,Duplicates,Errors);Check((Imported=0) and (Duplicates=4) and (Errors=1),'Duplicate full records');
  C.DatabaseName:=Name;C.Transaction:=T;C.Open;Q.Database:=C;Q.Transaction:=T;
  Q.SQL.Text:='select date,eco,white_elo,black_elo from games where id=1';Q.Open;
  Check(Q.FieldByName('date').AsString='2026.??.??','Date metadata');Check(Q.FieldByName('eco').AsString='A00','ECO metadata');
  Check(Q.FieldByName('white_elo').AsInteger=2100,'Integer Elo');Check(Q.FieldByName('black_elo').IsNull,'Unknown Elo is NULL');Q.Close;T.Rollback;
  C.ExecuteDirect('update database_state set summary_dirty=1');T.Commit;Stats;
  Db.RebuildContinuationSummary;Stats;
  Db.Close;Db.OpenDatabase(Name);Stats;
  Save(StringReplace(Text,'note [%eval','changed [%eval',[]));Db.ImportFile(Pgn,Imported,Duplicates,Errors);
  Check((Imported=1) and (Duplicates=3) and (Errors=1),'Changed annotation is distinct');
  C.Close;C.Open;
  // Missing metadata and future versions must reject before changing either file.
  C.ExecuteDirect('update database_metadata set value=''bad'' where name=''position_key_format''');T.Commit;
  Rejected(Db,Name);
  C.ExecuteDirect('update database_metadata set value=''chess-position-key-v1-fnv128'' where name=''position_key_format''');T.Commit;
  C.ExecuteDirect('pragma user_version=9');T.Commit;Rejected(Db,Name);Rejected(Other,Name);
  C.ExecuteDirect('pragma user_version=8');T.Commit;C.Close;Db.OpenDatabase(Name);
  // Counter-only changes must find the same stored position.
  P.LoadFromFEN('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 19 37');
  Clear;Db.SearchPosition(P,List);Check(List.Count=1,'Position counters excluded from database identity');
  P.LoadFromFEN('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1');
  Clear;Db.SearchPosition(P,List);Check(List.Count=0,'Castling rights distinguish database positions');
  // Complete text must be checked even when the unique game hash matches.
  C.Open;Q.SQL.Text:='select full_pdn from games where id=1';Q.Open;Before:=Q.Fields[0].AsString;Q.Close;T.Rollback;
  C.ExecuteDirect('update games set full_pdn=''1.a3 *'' where id=1');T.Commit;
  Save(Text);Db.ImportFile(Pgn,Imported,Duplicates,Errors);
  Check((Imported=0) and (Duplicates=3) and (Errors=2),'Hash conflict fails only that game and continues');
  C.Close;C.Open;
  Q.SQL.Text:='update games set full_pdn=:text where id=1';Q.ParamByName('text').AsString:=Before;Q.ExecSQL;T.Commit;
  // Optional malformed metadata does not reject a valid game or alter its PGN tags.
  Save('[Date "2026.13.01"] [ECO "Z99"] [WhiteElo "2147483648"] [BlackElo "-1"] 1.a3 *');
  Db.ImportFile(Pgn,Imported,Duplicates,Errors);Check((Imported=1) and (Errors=0),'Malformed optional metadata accepted as NULL');
  C.Close;C.Open;
  Q.SQL.Text:='select date,eco,white_elo,black_elo from games order by id desc limit 1';Q.Open;
  for I:=0 to 3 do Check(Q.Fields[I].IsNull,'Malformed metadata column is NULL');Q.Close;T.Rollback;
  C.Close;
  Save('');Rejected(Db,Pgn);
  Save('1.Nf3 d5 2.d4 Nf6 3.c4 e6 *'+#10+'1.d4 Nf6 2.Nf3 d5 3.c4 e6 *');
  Db.ImportFile(Pgn,Imported,Duplicates,Errors);
  Check((Imported=2) and (Errors=0),'Import transposed mainlines');
  P.LoadFromFEN(ChessStartingFEN);P.PlayMove('d2d4');P.PlayMove('d7d5');
  P.PlayMove('g1f3');P.PlayMove('g8f6');P.PlayMove('c2c4');
  Clear;Db.SearchPosition(P,List);
  Check((List.Count=1) and (TDatabaseSearchResult(List[0]).MoveText='e7e6') and
    (TDatabaseSearchResult(List[0]).GameCount=2),'Transpositions share hashed continuation identity');
  P.PlayMove('e7e6');Clear;Db.SearchPosition(P,List);
  Check(List.Count=0,'Terminal positions have no continuation');
  Db.LoadGamesForPosition(P,List,10,Total);Check(Total=2,'Terminal positions retain distinct matching games');
  Save('[SetUp "1"] [FEN "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"] 2.exd6 *'+#10+
    '[SetUp "1"] [FEN "4k3/8/8/3pP3/8/8/8/4K3 w - - 0 2"] 2.e6 *'+#10+
    '[SetUp "1"] [FEN "4k3/8/8/3p4/8/8/8/4K3 w - d6 0 2"] 2.Ke2 *');
  Db.ImportFile(Pgn,Imported,Duplicates,Errors);
  Check((Imported=3) and (Errors=0),'Import en-passant key fixtures');
  P.LoadFromFEN('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2');Clear;Db.SearchPosition(P,List);
  Check((List.Count=1) and (TDatabaseSearchResult(List[0]).MoveText='e5d6'),'Legal en passant has its own stored key');
  P.LoadFromFEN('4k3/8/8/3pP3/8/8/8/4K3 w - - 0 2');Clear;Db.SearchPosition(P,List);
  Check((List.Count=1) and (TDatabaseSearchResult(List[0]).MoveText='e5e6'),'Missing en passant does not match legal en passant');
  P.LoadFromFEN('4k3/8/8/3p4/8/8/8/4K3 w - - 0 2');Clear;Db.SearchPosition(P,List);
  Check((List.Count=1) and (TDatabaseSearchResult(List[0]).MoveText='e1e2'),'Unusable en passant target does not split identity');
  P.LoadFromFEN('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1');
  Clear;Db.SearchPosition(P,List);Check(List.Count=0,'Side to move separates stored keys');
  // Canonical aliases share v8 identity while source annotations stay intact.
  Save('[Event "Aliases"] 1.e4+ e5# 2.Ngf3 (2.Bf1c4) nc6 *'+#10+
    '[Event "Aliases"] 1.e4 e5 2.Nf3 (2.Bc4) Nc6 *');
  Db.ImportFile(Pgn,Imported,Duplicates,Errors);
  Check((Imported=1) and (Duplicates=1) and (Errors=0),'Schema 8 aliases deduplicate across mainline and RAV');
  C.Open;Q.SQL.Text:='pragma user_version';Q.Open;
  Check(Q.Fields[0].AsInteger=8,'New chess databases use schema 8');Q.Close;T.Rollback;
  Q.SQL.Text:='select distinct hash_version from games';Q.Open;
  Check(Q.Fields[0].AsInteger=8,'Schema 8 hash version');Q.Next;
  Check(Q.EOF,'One identity policy per database');Q.Close;T.Rollback;
  C.ExecuteDirect('update games set hash_version=7 where id=1');T.Commit;
  Rejected(Db,Name);
  C.ExecuteDirect('update games set hash_version=8 where id=1');T.Commit;C.Close;
  Db.Close;
  WriteLn('Chess database checks passed (',Checks,' checks)');
 finally Q.Free;T.Free;C.Free;Actor.Free;V.Free;Clear;List.Free;P.Free;Other.Free;Db.Free;
  DeleteFile(Name);DeleteFile(Draughts);DeleteFile(Pgn);end;
end.
