program chess_oracle_probe;
{$mode objfpc}{$H+}
{ Line-oriented test adapter for chess_differential_check.py. No GUI/protocol. }
uses SysUtils, uGamePosition, uChessPosition;
var P,Q: TChessPosition; FEN,M: string; I: Integer;
begin
  P := TChessPosition.Create; Q := TChessPosition.Create;
  try
    while not EOF(Input) do
    begin
      ReadLn(FEN);
      P.LoadFromFEN(FEN);
      WriteLn(P.ToFEN,#9,P.PositionKey,#9,Ord(P.InCheck),#9,
        Ord(P.HasInsufficientMatingMaterial(gsWhite)),#9,
        Ord(P.HasInsufficientMatingMaterial(gsBlack)));
      for I := 0 to P.LegalMoveCount-1 do
      begin
        M := P.LegalMove(I); Q.AssignFrom(P); Q.PlayTrustedMove(M);
        WriteLn(M,#9,P.MoveNotation(M),#9,Q.ToFEN);
      end;
      WriteLn('.'); Flush(Output);
    end;
  finally Q.Free; P.Free; end;
end.
