unit uChessPgnAnnotations;
{$mode objfpc}{$H+}
{ PGN embedded commands. Unknown or malformed commands remain literal prose. }
interface
uses SysUtils, uGamePosition, uGameTreeNodeData;
procedure ReadPgnComment(const Text: string; Side: TGameSide;
  var Data: TGameTreeNodeData; BeforeMove: Boolean=False);
function PgnNodeComment(const Data: TGameTreeNodeData; Side: TGameSide;
  ShowScore, ShowClocks, Lossless: Boolean): string;
function PgnBraceComment(const Text: string): string;
implementation
uses Classes, Math, StrUtils;
function PgnBraceComment(const Text: string): string;
var S: string; I: Integer;
begin
  // PGN braces cannot be escaped. Semicolon comments safely retain literal
  // closing braces; all other comments use the usual brace spelling.
  if Text='' then Exit('');
  if Pos('}',Text)>0 then begin
    S:=StringReplace(Text,#13#10,#10,[rfReplaceAll]);
    S:=StringReplace(S,#13,#10,[rfReplaceAll]);
    Result:=';'+StringReplace(S,#10,LineEnding+';',[rfReplaceAll])+LineEnding;
  end
  else begin
    S:=StringReplace(Text,#13#10,#10,[rfReplaceAll]); S:=StringReplace(S,#13,#10,[rfReplaceAll]);
    Result:='{';
    for I:=1 to Length(S) do begin
      Result+=S[I];
      if (S[I]=#10) and (I<Length(S)) and (S[I+1] in ['[','%']) then Result+=' ';
    end;
    Result+='}';
  end;
end;
function Duration(const Text: string; out Seconds: Double): Boolean;
var P: TStringList; H,M: Integer; S: Double; FS: TFormatSettings;
begin
  Result:=False; FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
  P:=TStringList.Create;
  try
    P.StrictDelimiter:=True; P.Delimiter:=':'; P.DelimitedText:=Text;
    if P.Count<>3 then Exit;
    if not TryStrToInt(P[0],H) or not TryStrToInt(P[1],M) or
      not TryStrToFloat(P[2],S,FS) then Exit;
    if (H<0) or (H>1000000) or (M<0) or (M>59) or IsNan(S) or IsInfinite(S) or (S<0) or (S>=60) then Exit;
    Seconds:=Double(H)*3600+M*60+S; Result:=True;
  finally P.Free; end;
end;
function ClockText(Seconds: Double): string;
var H,M: Int64; FS: TFormatSettings;
begin
  if IsNan(Seconds) or IsInfinite(Seconds) or (Seconds<0) or (Seconds>3600000000) then
    raise EConvertError.Create('Invalid PGN clock');
  FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
  Seconds:=Round(Seconds*1000)/1000;
  H:=Trunc(Seconds/3600); Seconds-=H*3600; M:=Trunc(Seconds/60); Seconds-=M*60;
  Result:=IntToStr(H)+':'+Format('%.2d',[M])+':'+FormatFloat('00.###',Seconds,FS);
end;
function EvalText(const Text: string; out Score,Depth: string): Boolean;
var N,P: Integer; V: Double; FS: TFormatSettings; S: string;
begin
  Result:=False; S:=Trim(Text); Depth:=''; FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
  P:=Pos(',',S);
  if P>0 then begin
    Depth:=Trim(Copy(S,P+1,MaxInt));
    if not TryStrToInt(Depth,N) or (N<0) then Exit;
    S:=Trim(Copy(S,1,P-1));
  end;
  if Copy(S,1,1)='#' then begin
    if not TryStrToInt(Copy(S,2,MaxInt),N) then Exit;
    Score:='#'+IntToStr(N);
  end else begin
    if not TryStrToFloat(S,V,FS) or IsNan(V) or IsInfinite(V) then Exit;
    if Abs(V)<0.005 then V:=0;
    Score:=FormatFloat('0.00',V,FS);
  end;
  Result:=True;
end;
procedure AppendText(var Dest: string; const Text: string);
begin if Text='' then Exit; if Dest<>'' then Dest+=#10; Dest+=Text; end;
procedure ReadPgnComment(const Text: string; Side: TGameSide;
  var Data: TGameTreeNodeData; BeforeMove: Boolean);
var I,J,K: Integer; Body,Key,Value,Literal,Score,Depth,Projection: string;
  Seconds: Double; Recognized,Edited: Boolean; Full: TGameTreeNodeData;
begin
  if BeforeMove then begin AppendText(Data.BeforeCommentText,Text); Exit; end;
  // Optional lossless envelopes use the existing typed codec, never the
  // draughts free-text score recognizer. Preserve unknown envelopes verbatim.
  if IsNodeDataEnvelope(Text) and DecodeNodeDataComment(Text,Data.CommentText,Full,Edited) and not Edited then
  begin Data:=CopyGameTreeNodeData(Full); Exit; end;
  Literal:=''; I:=1;
  while I<=Length(Text) do begin
    if Copy(Text,I,2)<>'[%' then begin Literal+=Text[I]; Inc(I); Continue; end;
    J:=PosEx(']',Text,I+2); if J=0 then begin Literal+=Copy(Text,I,MaxInt); Break; end;
    Body:=Trim(Copy(Text,I+2,J-I-2)); K:=1;
    while (K<=Length(Body)) and not (Body[K] in [' ',#9,#10,#13]) do Inc(K);
    if K>Length(Body) then K:=0;
    Key:=Copy(Body,1,K-1); Value:=Trim(Copy(Body,K+1,MaxInt)); Recognized:=False;
    if (K>0) and (Key='eval') and EvalText(Value,Score,Depth) then begin
      Data.EngineScore:=Score; Data.EnginePVDepth:=Depth; Recognized:=True;
    end;
    if (K>0) and ((Key='clk') or (Key='emt')) and Duration(Value,Seconds) then begin
      if Key='emt' then begin Data.HasMoveTime:=True; Data.SecondsUsed:=Seconds; end
      else begin
        Data.HasClockInfo:=True;
        if Side=gsWhite then Data.WhiteRemainingSeconds:=Seconds else Data.BlackRemainingSeconds:=Seconds;
      end;
      Recognized:=True;
    end;
    if not Recognized then Literal+=Copy(Text,I,J-I+1);
    I:=J+1;
  end;
  Projection:=Trim(Literal);
  if BeforeMove then AppendText(Data.BeforeCommentText,Projection)
  else AppendText(Data.CommentText,Projection);
end;
function PgnNodeComment(const Data: TGameTreeNodeData; Side: TGameSide;
  ShowScore, ShowClocks, Lossless: Boolean): string;
var Text,RawScore,Score,Depth,Encoded,StoredDepth: string; N: Integer;
  procedure Add(const S: string);
  begin if Text<>'' then Text+=' '; Text+=S; end;
begin
  Text:=Data.CommentText;
  if ShowScore then begin
    RawScore:=Data.EngineScore; StoredDepth:=Data.EnginePVDepth;
    if RawScore='' then begin RawScore:=Data.AnnotatorScore; StoredDepth:=Data.AnnotatorPVDepth; end;
    if EvalText(RawScore,Score,Depth) then begin
      if TryStrToInt(StoredDepth,N) and (N>=0) then Score+=','+IntToStr(N);
      Add('[%eval '+Score+']');
    end;
  end;
  if ShowClocks then begin
    if Data.HasClockInfo then
      if Side=gsWhite then Add('[%clk '+ClockText(Data.WhiteRemainingSeconds)+']')
      else Add('[%clk '+ClockText(Data.BlackRemainingSeconds)+']');
    if Data.HasMoveTime then Add('[%emt '+ClockText(Data.SecondsUsed)+']');
  end;
  Result:=PgnBraceComment(Text);
  if Lossless then begin
    Encoded:=EncodeNodeData(Data,Data.CommentText);
    if Encoded<>'' then begin
      if Result<>'' then Result+=' ';
      Result+=PgnBraceComment(Encoded);
    end;
  end;
end;
end.
