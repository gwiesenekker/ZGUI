program chess_database_benchmark;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,uGameDatabase,uGameTreePdn;
type TProgress=class
 Limit,Last:Integer;Started:QWord;
 procedure Report(Bytes,Total:Int64;Imported,Duplicates,Errors:Integer;var Cancel:Boolean);
end;
procedure TProgress.Report(Bytes,Total:Int64;Imported,Duplicates,Errors:Integer;var Cancel:Boolean);
begin
 if Imported+Duplicates>=Last+10000 then begin Last:=Imported+Duplicates;WriteLn(StdErr,'Games ',Last,' at ',GetTickCount64-Started,' ms');Flush(StdErr);end;
 if Bytes>=Total then begin WriteLn(StdErr,'Records complete at ',GetTickCount64-Started,' ms');Flush(StdErr);end;
 Cancel:=(Limit>0) and (Imported+Duplicates>=Limit);
end;
var Db:TGameDatabase;Progress:TProgress;I,D,E:Integer;Tick:QWord;
begin
 if ParamCount<2 then raise Exception.Create('Usage: benchmark input.pgn database.db [limit] [existing] [log]');
 Progress:=TProgress.Create;Progress.Limit:=StrToIntDef(ParamStr(3),0);Db:=TGameDatabase.Create(gffPgn);
 try
  if ParamStr(4)='existing' then Db.OpenDatabase(ParamStr(2)) else Db.CreateDatabase(ParamStr(2));
  Tick:=GetTickCount64;Progress.Started:=Tick;
  Db.ImportFile(ParamStr(1),I,D,E,@Progress.Report,ParamStr(5));
  Tick:=GetTickCount64-Tick;if Tick=0 then Tick:=1;
  WriteLn('games,duplicates,errors,ms,games_per_second');
  WriteLn(I,',',D,',',E,',',Tick,',',FormatFloat('0.00',(I+D)*1000.0/Tick));
 finally Db.Free;Progress.Free;end;
end.
