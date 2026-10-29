program chess_database_recovery_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,SQLite3Conn,SQLDB,
 uGameDatabase,uGameTreePdn,uChessPosition;
procedure Check(B:Boolean;const Text:string);
begin if not B then raise Exception.Create(Text);end;
procedure Raw(const Name,Sql:string);
var C:TSQLite3Connection;T:TSQLTransaction;
begin
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);
 try C.Transaction:=T;C.DatabaseName:=Name;C.Open;C.ExecuteDirect(Sql);T.Commit;C.Close;
 finally T.Free;C.Free;end;
end;
function Scalar(const Name,Sql:string):Integer;
var C:TSQLite3Connection;T:TSQLTransaction;Q:TSQLQuery;
begin
 C:=TSQLite3Connection.Create(nil);T:=TSQLTransaction.Create(nil);Q:=TSQLQuery.Create(nil);
 try C.Transaction:=T;C.DatabaseName:=Name;C.Open;Q.Database:=C;Q.Transaction:=T;Q.SQL.Text:=Sql;Q.Open;
  Result:=Q.Fields[0].AsInteger;Q.Close;T.Rollback;C.Close;
 finally Q.Free;T.Free;C.Free;end;
end;
function ReadText(const Name:string):string;
var Text:TStringList;
begin Text:=TStringList.Create;try Text.LoadFromFile(Name);Result:=Text.Text;finally Text.Free;end;end;
type TCancel=class
 procedure Progress(Bytes,Total:Int64;Imported,Duplicates,Errors:Integer;var Cancel:Boolean);
end;
procedure TCancel.Progress(Bytes,Total:Int64;Imported,Duplicates,Errors:Integer;var Cancel:Boolean);
begin Cancel:=Imported>=1;end;
var Name,Pgn,Root,LogName,LogText:string;Db:TGameDatabase;Text:TStringList;Games:TList;P:TChessPosition;
 Cancel:TCancel;I,D,E,J:Integer;Raised:Boolean;
procedure Clear;
var J:Integer;
begin for J:=0 to Games.Count-1 do TObject(Games[J]).Free;Games.Clear;end;
begin
 Pgn:=GetTempFileName(GetTempDir,'zrecover');Name:=Pgn+'.db';LogName:=Pgn+'.log';Db:=TGameDatabase.Create(gffPgn);
 Text:=TStringList.Create;Games:=TList.Create;P:=TChessPosition.Create;Cancel:=TCancel.Create;
 try
  Db.CreateDatabase(Name);Text.Text:='[Event "one"] 1.e4 e5 *';Text.SaveToFile(Pgn);
  Db.Close;Raw(Name,'create trigger fail_positions before insert on positions when new.ply=1 begin select raise(abort,''injected position failure''); end');Db.OpenDatabase(Name);
  Raised:=False;try Db.ImportFile(Pgn,I,D,E,nil,LogName);except on X:ESQLDatabaseError do Raised:=True;end;
  Check(Raised,'SQL insert failure propagates');Db.LoadGames(Games);Check(Games.Count=0,'Failed game row rolled back');Clear;
  LogText:=ReadText(LogName);
  Check((Pos('injected position failure',LogText)>0) and (Pos('----- PGN -----',LogText)>0) and
    (Pos('[Event "one"]',LogText)>0),'Fatal SQL failure logs the failing complete PGN');
  Check((Pos('game=1',LogText)>0) and (Pos('byte_end=',LogText)>0) and
    (Pos('source_bytes=',LogText)>0) and (Pos('errors=1',LogText)>0),'Fatal error counted once with source location');
  Check(Pos('PDN',LogText)=0,'Chess errors use PGN labels');
  Check(Scalar(Name,'select count(*) from positions')=0,'No orphan positions after failure');
  Check(Scalar(Name,'select count(*) from sqlite_master where type=''index'' and name in (''idx_positions_search'',''idx_positions_game'')')=2,'Indexes available after recovery');
  Db.Close;Raw(Name,'drop trigger fail_positions');Db.OpenDatabase(Name);Db.ImportFile(Pgn,I,D,E);Check(I=1,'Import succeeds after failure removed');
  Db.ImportFile(Pgn,I,D,E,nil,LogName);LogText:=ReadText(LogName);
  Check((I=0) and (D=1) and (E=0) and (Pos('----- DUPLICATE PGN -----',LogText)>0) and
    (Pos('[Event "one"]',LogText)>0) and (Pos('game=1',LogText)>0),'Duplicate log identifies and delimits complete PGN');
  Db.Close;Raw(Name,'create trigger fail_summary before insert on continuations begin select raise(abort,''injected summary failure''); end');Db.OpenDatabase(Name);
  Text.Text:='[Event "two"] 1.d4 d5 *';Text.SaveToFile(Pgn);
  Raised:=False;try Db.ImportFile(Pgn,I,D,E);except on X:ESQLDatabaseError do Raised:=True;end;
  Check(Raised,'Summary failure propagates');Check(Scalar(Name,'select summary_dirty from database_state where id=1')=1,'Failed rebuild stays dirty');
  Db.SearchPosition(P,Games);Check(Games.Count=2,'Direct query remains usable after failed summary');Clear;
  Db.Close;Raw(Name,'drop trigger fail_summary');Db.OpenDatabase(Name);Db.RebuildContinuationSummary;
  Check(Scalar(Name,'select summary_dirty from database_state where id=1')=0,'Repair publishes clean summary');
  Db.Close;Db.OpenDatabase(Name);Db.SearchPosition(P,Games);Check(Games.Count=2,'Reopen sees repaired summary');Clear;
  Text.Clear;for J:=1 to 5000 do Text.Add('[Event "cancel '+IntToStr(J)+'"] 1.Nf3 Nf6 *');Text.SaveToFile(Pgn);
  Db.ImportFile(Pgn,I,D,E,@Cancel.Progress);Check((I>0) and (I<5000) and (E=0),'Cancel stops at completed games');
  Check(Scalar(Name,'select count(*) from positions')=(I+2)*3,'Cancelled batch has complete position rows');
  Check(Scalar(Name,'select count(*) from positions p left join games g on g.id=p.game_id where g.id is null')=0,'No cancelled orphan positions');
  Check(Scalar(Name,'select summary_dirty from database_state where id=1')=0,'Cancelled import rebuilds summary');
  Root:=GetEnvironmentVariable('GWDGUI_ROOT');if Root='' then Root:=GetCurrentDir;
  Db.ImportFile(IncludeTrailingPathDelimiter(Root)+'tests/fixtures/chess-unclosed-comment.pgn',I,D,E,nil,LogName);
  Check((I=5) and (D=0) and (E=1),'Malformed comment rejects one game and imports following games');
  LogText:=ReadText(LogName);
  Check((Pos('game=2',LogText)>0) and (Pos('byte_end=',LogText)>0) and (Pos('errors=1',LogText)>0),
    'Recoverable syntax error logs record location and counts once');
  Check(Scalar(Name,'select count(*) from games where event=''g2''')=0,'Malformed comment game is not stored');
  Check(Scalar(Name,'select count(*) from games where event=''g3'' and moves_text=''c2c4 e7e5''')=1,'Following game keeps its own identity and moves');
  Db.ImportFile(IncludeTrailingPathDelimiter(Root)+'tests/fixtures/chess-unclosed-variation.pgn',I,D,E);
  Check((I=1) and (D=2) and (E=1),'Malformed variation preserves valid games including changed annotations');
  WriteLn('Chess database recovery checks passed');
 finally Clear;Cancel.Free;P.Free;Games.Free;Text.Free;Db.Free;DeleteFile(Pgn);DeleteFile(Name);DeleteFile(LogName);end;
end.
