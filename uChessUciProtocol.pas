unit uChessUciProtocol;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, uEngineParamsJson;
type
  TUciInfo=record
    PV,Score,Depth,TimeText: string;
    HasScore,Bounded: Boolean;
    MultiPV: Integer;
  end;
function ParseUciOption(const Line: string; out Param: TEngineParam): Boolean;
function ParseUciInfo(const Line: string; out Info: TUciInfo): Boolean;
procedure ValidateUciValue(const Param: TEngineParam; const Value: string);
procedure ValidateUciText(const Text: string);
implementation
uses Math;
procedure ValidateUciText(const Text: string);
begin
  if (Pos(#0,Text)>0) or (Pos(#10,Text)>0) or (Pos(#13,Text)>0) then
    raise EConvertError.Create('UCI names and values cannot contain line breaks or NUL');
end;
procedure Tokens(const Line: string; List: TStrings);
begin ExtractStrings([' ',#9],[],PChar(Line),List); end;
function Join(L: TStrings; A,B: Integer): string;
var I: Integer;
begin Result:=''; for I:=A to B do begin if I>A then Result+=' '; Result+=L[I]; end; end;
function ParseUciOption(const Line: string; out Param: TEngineParam): Boolean;
var L: TStringList; I,J,TypeAt: Integer; Key,Value: string;
begin
  Result:=False; Param:=Default(TEngineParam); L:=TStringList.Create;
  try
    Tokens(Line,L); if (L.Count<5) or (L[0]<>'option') or (L[1]<>'name') then Exit;
    TypeAt:=-1;
    for I:=2 to L.Count-2 do
      if (L[I]='type') and ((L[I+1]='spin') or (L[I+1]='check') or
        (L[I+1]='combo') or (L[I+1]='string') or (L[I+1]='button')) then begin TypeAt:=I; Break; end;
    if TypeAt<3 then Exit;
    Param.Name:=Join(L,2,TypeAt-1); Param.ParamType:=L[TypeAt+1]; I:=TypeAt+2;
    while I<L.Count do begin
      Key:=L[I]; Inc(I); J:=I;
      while (I<L.Count) and not ((L[I]='default') or (L[I]='min') or (L[I]='max') or (L[I]='var')) do Inc(I);
      Value:=Join(L,J,I-1); if Value='<empty>' then Value:='';
      if Key='default' then Param.DefaultValue:=Value
      else if Key='min' then Param.MinValue:=Value else if Key='max' then Param.MaxValue:=Value
      else if Key='var' then begin if Param.Choices<>'' then Param.Choices+=#10; Param.Choices+=Value; end;
    end;
    Param.Value:=Param.DefaultValue; ValidateUciText(Param.Name); Result:=True;
  finally L.Free; end;
end;
procedure ValidateUciValue(const Param: TEngineParam; const Value: string);
var N,Limit: Int64; Choices: TStringList;
begin
  ValidateUciText(Param.Name); ValidateUciText(Value);
  if Param.ParamType='spin' then begin
    if not TryStrToInt64(Value,N) then raise EConvertError.Create('Invalid integer for '+Param.Name);
    if TryStrToInt64(Param.MinValue,Limit) and (N<Limit) then raise EConvertError.Create('Below minimum: '+Param.Name);
    if TryStrToInt64(Param.MaxValue,Limit) and (N>Limit) then raise EConvertError.Create('Above maximum: '+Param.Name);
  end else if Param.ParamType='check' then begin
    if not (SameText(Value,'true') or SameText(Value,'false')) then raise EConvertError.Create('Expected true/false for '+Param.Name);
  end else if Param.ParamType='combo' then begin
    Choices:=TStringList.Create;
    try Choices.Text:=Param.Choices; Choices.CaseSensitive:=False;
      if Choices.IndexOf(Value)<0 then raise EConvertError.Create('Invalid choice for '+Param.Name);
    finally Choices.Free; end;
  end;
end;
function ParseUciInfo(const Line: string; out Info: TUciInfo): Boolean;
var L: TStringList; I,N: Integer; V: Int64;
begin
  Result:=False; Info:=Default(TUciInfo); Info.MultiPV:=1; L:=TStringList.Create;
  try
    Tokens(Line,L); if (L.Count<2) or (L[0]<>'info') or (L[1]='string') then Exit;
    I:=1;
    while I<L.Count do begin
      if L[I]='pv' then begin Info.PV:=Join(L,I+1,L.Count-1); Break; end;
      if (L[I]='lowerbound') or (L[I]='upperbound') then Info.Bounded:=True
      else if (L[I]='multipv') and (I+1<L.Count) then begin Inc(I); if not TryStrToInt(L[I],Info.MultiPV) then Exit; end
      else if (L[I]='depth') and (I+1<L.Count) then begin Inc(I); if TryStrToInt(L[I],N) and (N>=0) then Info.Depth:=IntToStr(N); end
      else if (L[I]='time') and (I+1<L.Count) then begin Inc(I); if TryStrToInt64(L[I],V) and (V>=0) then Info.TimeText:=IntToStr(V); end
      else if (L[I]='score') and (I+2<L.Count) then begin
        if not TryStrToInt64(L[I+2],V) or (V < -1000000000) or (V>1000000000) then Exit;
        if L[I+1]='cp' then Info.Score:=IntToStr(V)
        else if L[I+1]='mate' then Info.Score:='#'+IntToStr(V) else Exit;
        Info.HasScore:=True; Inc(I,2);
      end;
      Inc(I);
    end;
    Result:=True;
  finally L.Free; end;
end;
end.
