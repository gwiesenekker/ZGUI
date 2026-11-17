program tournament_ballot_check;
{$mode objfpc}{$H+}
uses Classes,SysUtils,FPJSON,uGamePosition,uChessPosition,uDraughtsPosition,
 uTournamentBallot,uTournamentPairing,uTournamentGameRecord;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure ForVariant(V:TGameVariant);
var P:TGamePosition;Fens,Lines,Engines:TStringList;Name,First,Second,Before:string;
 R:TTournamentPairingRound;I:Integer;Failed:Boolean;A,B:TTournamentGameRecord;J,Wrapper:TJSONObject;
begin
 Fens:=TStringList.Create;Lines:=TStringList.Create;Engines:=TStringList.Create;
 P:=V.CreatePosition;A:=TTournamentGameRecord.Create;B:=TTournamentGameRecord.Create;
 Name:=GetTempFileName(GetTempDir,'ballot');
 try
  if V is TChessVariant then P.LoadFromFEN('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 17 42')
  else P.LoadFromFEN(V.DefaultStartingFEN);
  First:=P.ToFEN;P.PlayMove(P.LegalMove(0));Second:=P.ToFEN;
  Lines.Text:=#$EF#$BB#$BF+'# opening set'+LineEnding+LineEnding+First+LineEnding+'; comment'+LineEnding+'// comment'+LineEnding+Second;
  Lines.SaveToFile(Name);LoadOpeningBallot(Name,V,Fens);
  Check((Fens.Count=2) and (Fens[0]=First) and (Fens[1]=Second),'Complete positions, BOM, comments and side-to-move preserved');
  Engines.Add('GWD');Engines.Add('Kingsrow');R:=BuildBallotPairingRound(Engines,Fens);
  Check(Length(R.Pairings)=4,'Two games per position');
  for I:=0 to 1 do begin
   Check((R.Pairings[2*I].StartingFEN=Fens[I]) and (R.Pairings[2*I+1].StartingFEN=Fens[I]),'Both colours use the identical FEN');
   Check((R.Pairings[2*I].White=R.Pairings[2*I+1].Black) and (R.Pairings[2*I].Black=R.Pairings[2*I+1].White),'Engine colours reversed');
   Check((R.Pairings[2*I].RoundNumber=I+1) and (R.Pairings[2*I+1].RoundNumber=I+1),'Round identifies ballot entry');
  end;
  Engines.Add('Third');R:=BuildBallotPairingRound(Engines,Fens);
  Check(Length(R.Pairings)=12,'Every selected engine pair plays every entry twice');
  Fens.Add(First);R:=BuildBallotPairingRound(Engines,Fens);
  Check(Length(R.Pairings)=18,'Repeated ballot entries retain their original frequency');
  Before:=Fens.Text;Lines.Text:=First+LineEnding+'not a fen';Lines.SaveToFile(Name);Failed:=False;
  try LoadOpeningBallot(Name,V,Fens);except on E:EConvertError do begin Failed:=True;Check(Pos('line 2',E.Message)>0,'Invalid input reports source line');end;end;
  Check(Failed and (Fens.Text=Before),'Invalid ballot load is atomic');
  Lines.Text:='# empty';Lines.SaveToFile(Name);Failed:=False;
  try LoadOpeningBallot(Name,V,Fens);except on E:EConvertError do Failed:=True;end;
  Check(Failed and (Fens.Text=Before),'Empty ballot rejected without replacing current positions');
  A.StartingFEN:=Second;A.RecordPlayedGame('','*');A.Reschedule;
  Check(A.StartingFEN=Second,'Replay retains starting position');
  J:=A.ToJson;Wrapper:=TJSONObject.Create;
  try Wrapper.Add('record',J);B.LoadFromJson(Wrapper);Check(B.StartingFEN=Second,'Per-game FEN survives saved record and attempt history');finally Wrapper.Free;end;
 finally A.Free;B.Free;P.Free;Engines.Free;Lines.Free;Fens.Free;DeleteFile(Name);end;
end;
procedure ShuffleChecks;
var Positions,Original,Sorted,Engines:TStringList;R:TTournamentPairingRound;I:Integer;
begin
 Positions:=TStringList.Create;Original:=TStringList.Create;Sorted:=TStringList.Create;Engines:=TStringList.Create;
 try
  ShuffleOpeningPairs(Positions);Check(Positions.Count=0,'Empty shuffle is harmless');
  Positions.Add('single');ShuffleOpeningPairs(Positions);Check(Positions[0]='single','Single opening unchanged');
  Positions.Clear;for I:=1 to 20 do Positions.Add('opening '+IntToStr(I));Positions.Add(Positions[3]);Original.Assign(Positions);
  RandSeed:=20261117;ShuffleOpeningPairs(Positions);
  Check(Positions.Text<>Original.Text,'Fixed-seed fixture changes the schedule');
  Sorted.Assign(Positions);Sorted.Sort;Original.Sort;Check(Sorted.Text=Original.Text,'Shuffle preserves every entry including duplicate frequency');
  Engines.Add('A');Engines.Add('B');Engines.Add('C');R:=BuildBallotPairingRound(Engines,Positions);
  Check(Length(R.Pairings)=6*Positions.Count,'Shuffled multi-engine schedule keeps every matchup');
  for I:=0 to Length(R.Pairings) div 2-1 do begin
   Check((R.Pairings[2*I].StartingFEN=Positions[I div 3]) and
    (R.Pairings[2*I+1].StartingFEN=Positions[I div 3]),'Shuffled games use their scheduled opening');
   Check((R.Pairings[2*I].White=R.Pairings[2*I+1].Black) and
    (R.Pairings[2*I].Black=R.Pairings[2*I+1].White),'Shuffled multi-engine pair keeps colours reversed');
   Check((R.Pairings[2*I].RoundNumber=I div 3+1) and
    (R.Pairings[2*I+1].RoundNumber=I div 3+1),'Opening identity follows scheduled order');
  end;
 finally Engines.Free;Sorted.Free;Original.Free;Positions.Free;end;
end;
var Chess:TChessVariant;Draughts:TDraughtsVariant;Fens,Engines:TStringList;R:TTournamentPairingRound;
begin
 Chess:=TChessVariant.Create;Draughts:=TDraughtsVariant.Create;
 try
  ForVariant(Chess);ForVariant(Draughts);ShuffleChecks;
  if ParamCount>0 then begin
   Fens:=TStringList.Create;Engines:=TStringList.Create;
   try
    LoadOpeningBallot(ParamStr(1),Draughts,Fens);Engines.Add('GWD');Engines.Add('Kingsrow');
    R:=BuildBallotPairingRound(Engines,Fens);
    Check(Length(R.Pairings)=2*Fens.Count,'Real ballot produces twice its position count');
    WriteLn('Real ballot: ',Fens.Count,' positions, ',Length(R.Pairings),' games');
   finally Fens.Free;Engines.Free;end;
  end;
 finally Chess.Free;Draughts.Free;end;
 WriteLn('Tournament ballot checks passed (',Checks,' checks)');
end.
