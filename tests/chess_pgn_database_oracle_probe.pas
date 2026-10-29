program chess_pgn_database_oracle_probe;
{$mode objfpc}{$H+}
uses Classes,SysUtils,uChessPosition,uChessPgn;
var V:TChessVariant;G:TChessPgnDatabaseGame;F:TFileStream;Text:string;
begin
 if ParamCount<>2 then raise Exception.Create('Usage: probe input.pgn output.pgn');
 V:=TChessVariant.Create;
 try
  F:=TFileStream.Create(ParamStr(1),fmOpenRead);
  try SetLength(Text,F.Size);if Text<>'' then F.ReadBuffer(Text[1],Length(Text));finally F.Free;end;
  G:=ReadChessPgnDatabaseGame(Text,V);
  try
   F:=TFileStream.Create(ParamStr(2),fmCreate);
   try F.WriteBuffer(G.CompletePgn[1],Length(G.CompletePgn));finally F.Free;end;
  finally G.Free;end;
 finally V.Free;end;
end.
