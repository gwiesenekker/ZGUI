program chess_pgn_oracle_probe;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Classes, SysUtils, uChessPosition, uGameTree,
  uGameTreeActor, uGameTreePdn, uChessPgn;
var V: TChessVariant; A: TGameTreeActor; F: TFileStream; S: string;
  O: TGameTreePdnRenderOptions;
begin
  if ParamCount<>2 then raise Exception.Create('Usage: probe input.pgn output.pgn');
  V:=TChessVariant.Create; A:=TGameTreeActor.Create(TGameTree.Create(V),True);
  try
    F:=TFileStream.Create(ParamStr(1),fmOpenRead);
    try SetLength(S,F.Size); if S<>'' then F.ReadBuffer(S[1],Length(S)); finally F.Free; end;
    ImportChessPgn(S,A,nil); O:=DefaultGameTreePdnRenderOptions; O.FileFormat:=gffPgn;
    S:=GameTreeToPdnTextEx(A.GameTree,O);
    F:=TFileStream.Create(ParamStr(2),fmCreate);
    try if S<>'' then F.WriteBuffer(S[1],Length(S)); finally F.Free; end;
  finally A.Free; V.Free; end;
end.
