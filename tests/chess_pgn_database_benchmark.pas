program chess_pgn_database_benchmark;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes,SysUtils,uChessPosition,uChessPgn;
type TBenchmark=class
  Variant:TChessVariant;
  Games,Warnings,Limit,NextReport:Int64;
  Plies,Keys,OutputBytes,BytesRead,TotalBytes,AllReadBytes:Int64;
  ScanOnly:Boolean;
  procedure Game(const Text,ErrorText:string;ReadBytes,Total:Int64;var Cancel:Boolean);
end;
procedure TBenchmark.Game(const Text,ErrorText:string;ReadBytes,Total:Int64;var Cancel:Boolean);
var G:TChessPgnDatabaseGame;W:TStringList;
begin
 if ErrorText<>'' then raise Exception.Create(ErrorText);
 if ScanOnly then Inc(Games)
 else begin
 W:=TStringList.Create;
 try
  G:=ReadChessPgnDatabaseGame(Text,Variant,W);
  try
   Inc(Games);Inc(Plies,G.Moves.Count);Inc(Keys,G.PositionKeys.Count);
   Inc(OutputBytes,Length(G.CompletePgn));Inc(Warnings,W.Count);
  finally G.Free;end;
 finally W.Free;end;
 end;
 BytesRead:=ReadBytes;TotalBytes:=Total;
 if Games>=NextReport then begin
  WriteLn(StdErr,'Parsed ',Games,' games / ',Plies,' plies');Flush(StdErr);Inc(NextReport,10000);
 end;
 Cancel:=(Limit>0) and (Games>=Limit);
end;
var B:TBenchmark;R:TChessPgnReader;Tick,Elapsed:QWord;I,Repeats:Integer;
begin
 if ParamCount<1 then raise Exception.Create('Usage: benchmark input.pgn [game limit; 0=all] [repeats] [scan-only]');
 B:=TBenchmark.Create;B.Variant:=TChessVariant.Create;B.Limit:=StrToInt64Def(ParamStr(2),0);
 B.NextReport:=10000;R:=TChessPgnReader.Create(B.Variant);Repeats:=StrToIntDef(ParamStr(3),1);
 B.ScanOnly:=ParamStr(4)='scan-only';
 if Repeats<1 then raise Exception.Create('Repeats must be positive');
 try
  Tick:=GetTickCount64;
  for I:=1 to Repeats do begin
   if (B.Limit>0) and (B.Games>=B.Limit) then Break;
   R.ScanFile(ParamStr(1),@B.Game);Inc(B.AllReadBytes,B.BytesRead);
  end;
  Elapsed:=GetTickCount64-Tick;if Elapsed=0 then Elapsed:=1;
  if R.Entries.Count<>0 then raise Exception.Create('Streaming retained entries');
  WriteLn('games,plies,keys,source_bytes,total_file_bytes,stored_bytes,warnings,ms,games_per_second');
  WriteLn(B.Games,',',B.Plies,',',B.Keys,',',B.AllReadBytes,',',B.TotalBytes,',',
   B.OutputBytes,',',B.Warnings,',',Elapsed,',',FormatFloat('0.00',B.Games*1000.0/Elapsed));
 finally R.Free;B.Variant.Free;B.Free;end;
end.
