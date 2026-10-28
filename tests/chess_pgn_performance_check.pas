program chess_pgn_performance_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, uChessPosition, uChessPgn,
  uGameFileReader, uGameTree, uGameTreeActor;
function CountNodes(N: TGameTreePlyNode): Integer;
var I: Integer;
begin Result:=0; for I:=0 to N.ChildCount-1 do Inc(Result,1+CountNodes(N.Children[I])); end;
var Name,Chunk,Root: string; V: TChessVariant; R: TChessPgnReader;
  A: TGameTreeActor; F: TFileStream; I,Games: Integer; Tick: QWord; Size: Int64;
begin
  Root:=GetEnvironmentVariable('GWDGUI_ROOT'); if Root='' then Root:=GetCurrentDir;
  Games:=StrToIntDef(ParamStr(1),1000); Name:=GetTempFileName(GetTempDir,'zpf');
  V:=TChessVariant.Create; R:=TChessPgnReader.Create(V); A:=TGameTreeActor.Create(TGameTree.Create(V),True);
  try
    Chunk:='[Event "listing"]'+#10+'[White "W"]'+#10+'[Black "B"]'+#10+'1.e4 {'+StringOfChar('x',6800)+'} e5 *'+#10;
    F:=TFileStream.Create(Name,fmCreate);
    try for I:=1 to Games do F.WriteBuffer(Chunk[1],Length(Chunk)); Size:=F.Size; finally F.Free; end;
    Tick:=GetTickCount64; R.OpenFile(Name);
    if R.Entries.Count<>Games then raise Exception.Create('Listing count');
    WriteLn('Listing: ',Size,' bytes, ',Games,' games, ',GetTickCount64-Tick,' ms');
    R.OpenFile(IncludeTrailingPathDelimiter(Root)+'tests/fixtures/chess-long-variations.pgn');
    Tick:=GetTickCount64; TGameFileEntry(R.Entries[0]).Validate;
    if TGameFileEntry(R.Entries[0]).ErrorText<>'' then raise Exception.Create(TGameFileEntry(R.Entries[0]).ErrorText);
    TGameFileEntry(R.Entries[0]).ImportInto(A);
    WriteLn('Validate + cached-entry replay: ',A.GameTree.MainlineCount,' plies, ',CountNodes(A.GameTree.Root),' nodes, ',GetTickCount64-Tick,' ms');
    if (A.GameTree.MainlineCount<>200) or (CountNodes(A.GameTree.Root)<600) then raise Exception.Create('Annotated benchmark shape');
  finally A.Free; R.Free; V.Free; DeleteFile(Name); end;
end.
