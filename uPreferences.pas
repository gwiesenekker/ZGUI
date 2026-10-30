unit uPreferences;

{$mode objfpc}{$H+}

interface

uses
  Graphics, uNotationStyles;

type
  TScoreScale = (ssLinear, ssLogarithmic);

  TScoreHistoryColor = (shcEngineNonnegative, shcEngineNegative,
    shcAnnotatorNonnegative, shcAnnotatorNegative, shcEngineMissing,
    shcAnnotatorMissing, shcBothMissing, shcSelectedPly);
  TScoreHistoryColors = array[TScoreHistoryColor] of TColor;

  TGuiPreferences = record
    ScoreHistoryColors: TScoreHistoryColors;
    NotationStyles: TNotationStyles;
    NotationFontName: string;
    NotationFontSize: Integer;
    MainBoardLightColor: TColor;
    MainBoardDarkColor: TColor;
    AnalysisBoardLightColor: TColor;
    AnalysisBoardDarkColor: TColor;
    TargetSquareColor: TColor;
    LastMoveColor: TColor;
    PvMoveColor: TColor;
    HintMoveColor: TColor;
    EvaluationMaxScore: Double;
    EvaluationScale: TScoreScale;
  end;

function DefaultScoreHistoryColors: TScoreHistoryColors;
function PreferencesJsonFileName: string;
function DefaultGuiPreferences: TGuiPreferences;
procedure LoadGuiPreferences(var APrefs: TGuiPreferences;const GameId:string='');
procedure SaveGuiPreferences(const APrefs: TGuiPreferences;const GameId:string='');
type
  TGamePreferencesEdit = record
    GameId: string;
    Preferences: TGuiPreferences;
  end;
  TGamePreferencesEdits = array of TGamePreferencesEdit;
function SameGuiPreferences(const A,B:TGuiPreferences):Boolean;
procedure SaveGamePreferences(const Edits: TGamePreferencesEdits);
function LastGamePreference:string;
procedure RememberGamePreference(const GameId:string);

implementation

uses
  Classes, FPJSON, JSONParser, SysUtils, uAtomicFile;

const ScoreColorKeys: array[TScoreHistoryColor] of string = (
  'score_history_engine_nonnegative', 'score_history_engine_negative',
  'score_history_annotator_nonnegative', 'score_history_annotator_negative',
  'score_history_engine_missing', 'score_history_annotator_missing',
  'score_history_both_missing', 'score_history_selected_ply');
function DefaultScoreHistoryColors: TScoreHistoryColors;
begin
  Result[shcEngineNonnegative]:=RGBToColor(54,150,79);
  Result[shcEngineNegative]:=RGBToColor(190,64,64);
  Result[shcAnnotatorNonnegative]:=RGBToColor(140,210,155);
  Result[shcAnnotatorNegative]:=RGBToColor(230,145,145);
  Result[shcEngineMissing]:=RGBToColor(28,74,132);
  Result[shcAnnotatorMissing]:=RGBToColor(102,169,220);
  Result[shcBothMissing]:=RGBToColor(145,165,188);
  Result[shcSelectedPly]:=clGray;
end;

function PreferencesJsonFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'prefs.json';
end;

function DefaultGuiPreferences: TGuiPreferences;
begin
  Result.ScoreHistoryColors:=DefaultScoreHistoryColors;
  Result.NotationStyles := DefaultNotationStyles;
  Result.NotationFontName := DefaultNotationFontName;
  Result.NotationFontSize := DefaultNotationFontSize;
  Result.MainBoardLightColor := RGBToColor(228, 207, 176);
  Result.MainBoardDarkColor := RGBToColor(98, 73, 53);
  Result.AnalysisBoardLightColor := RGBToColor(206, 228, 246);
  Result.AnalysisBoardDarkColor := RGBToColor(54, 95, 139);
  Result.TargetSquareColor := clLime;
  Result.LastMoveColor := clYellow;
  Result.PvMoveColor := RGBToColor(255, 165, 0);
  Result.HintMoveColor := clRed;
  Result.EvaluationMaxScore := 10.0;
  Result.EvaluationScale := ssLogarithmic;
end;

procedure ReadPreferenceLines(Lines:TStrings);
var Stream:TFileStream;
begin
  // Atomic publication provides a complete version. Use a shared read lock,
  // compatible with handles inherited by a concurrently starting engine.
  Stream:=TFileStream.Create(PreferencesJsonFileName,fmOpenRead or fmShareDenyNone);
  try Lines.LoadFromStream(Stream);finally Stream.Free;end;
end;

function ReadPreferenceObject:TJSONObject;
var Lines:TStringList;Value:TJSONData;
begin
  Result:=TJSONObject.Create;if not FileExists(PreferencesJsonFileName) then Exit;
  Lines:=TStringList.Create;Value:=nil;
  try
    try ReadPreferenceLines(Lines);Value:=GetJSON(Lines.Text);
    except on E:Exception do Exit;end;
    if Value.JSONType=jtObject then begin Result.Free;Result:=TJSONObject(Value);Value:=nil;end;
  finally Value.Free;Lines.Free;end;
end;
function LastGamePreference:string;
var Data:TJSONObject;
begin Data:=ReadPreferenceObject;try
  Result:='chess';if (Data.Find('last_game')<>nil) and (Data.Find('last_game').JSONType=jtString) then
    Result:=Data.Get('last_game','chess');
finally Data.Free;end;end;
procedure RememberGamePreference(const GameId:string);
var Data:TJSONObject;Lines:TStringList;
begin
  Data:=ReadPreferenceObject;Lines:=TStringList.Create;
  try Data.Delete('last_game');Data.Add('last_game',GameId);Lines.Text:=Data.FormatJSON([],2);
    WriteTextFileAtomically(PreferencesJsonFileName,Lines.Text);
  finally Lines.Free;Data.Free;end;
end;

function ColorToJsonText(AColor: TColor): string;
var
  C: TColor;
begin
  C := ColorToRGB(AColor);
  Result := Format('#%.2x%.2x%.2x', [
    C and $FF,
    (C shr 8) and $FF,
    (C shr 16) and $FF
  ]);
end;

function TryJsonTextToColor(const AText: string; out AColor: TColor): Boolean;
var
  Code: Integer;
  HexText: string;
  Value: Integer;
begin
  Result := False;
  HexText := Trim(AText);
  if (Length(HexText) = 7) and (HexText[1] = '#') then
    Delete(HexText, 1, 1);
  if Length(HexText) <> 6 then
    Exit;

  Val('$' + HexText, Value, Code);
  if Code <> 0 then
    Exit;

  AColor := RGBToColor((Value shr 16) and $FF, (Value shr 8) and $FF,
    Value and $FF);
  Result := True;
end;

procedure LoadColor(AObject: TJSONObject; const AName: string;
  var AColor: TColor);
var
  NewColor: TColor;
begin
  if (AObject <> nil) and TryJsonTextToColor(AObject.Get(AName, ''), NewColor) then
    AColor := NewColor;
end;

procedure LoadBoolean(AObject: TJSONObject; const AName: string; var AValue: Boolean);
var Data: TJSONData;
begin
  Data := AObject.Find(AName);
  if (Data <> nil) and (Data.JSONType = jtBoolean) then AValue := Data.AsBoolean;
end;

procedure LoadGuiPreferences(var APrefs: TGuiPreferences;const GameId:string);
var
  Data: TJSONData;
  FileName: string;
  Lines: TStringList;
  C: TScoreHistoryColor;
  S: TNotationStyle; Key: string; Defaults: TNotationStyles;
  Value: TJSONData; FontSize: Integer;Layer:TJSONObject;
begin
  APrefs := DefaultGuiPreferences;
  Defaults := DefaultNotationStyles;
  FileName := PreferencesJsonFileName;
  if not FileExists(FileName) then
    Exit;

  Lines := TStringList.Create;
  try
    ReadPreferenceLines(Lines);
    Data := GetJSON(Lines.Text);
  finally
    Lines.Free;
  end;

  try
    if Data.JSONType = jtObject then
    begin
      Value := TJSONObject(Data).Find('notation_font_name');
      if (Value <> nil) and (Value.JSONType = jtString) and (Trim(Value.AsString) <> '') then
        APrefs.NotationFontName := Trim(Value.AsString);
      Value := TJSONObject(Data).Find('notation_font_size');
      if (Value <> nil) and (Value.JSONType = jtNumber) and
        TryStrToInt(Value.AsJSON, FontSize) and (FontSize > 0) then APrefs.NotationFontSize := FontSize;
      for S := Low(S) to High(S) do
      begin
        // Keep customised legacy shared-PV styles; otherwise use distinct defaults.
        if (S in [nsEnginePV, nsAnnotatorPV]) and
          ((APrefs.NotationStyles[nsAnalysis].Color <> Defaults[nsAnalysis].Color) or
           (APrefs.NotationStyles[nsAnalysis].Bold <> Defaults[nsAnalysis].Bold) or
           (APrefs.NotationStyles[nsAnalysis].Italic <> Defaults[nsAnalysis].Italic)) then
          APrefs.NotationStyles[S] := APrefs.NotationStyles[nsAnalysis];
        Key := 'notation_' + IntToStr(Ord(S));
        LoadColor(TJSONObject(Data), Key + '_color', APrefs.NotationStyles[S].Color);
        LoadBoolean(TJSONObject(Data), Key+'_bold', APrefs.NotationStyles[S].Bold);
        LoadBoolean(TJSONObject(Data), Key+'_italic', APrefs.NotationStyles[S].Italic);
      end;
      for C:=Low(C) to High(C) do
        LoadColor(TJSONObject(Data),ScoreColorKeys[C],APrefs.ScoreHistoryColors[C]);
      LoadColor(TJSONObject(Data), 'main_board_light', APrefs.MainBoardLightColor);
      LoadColor(TJSONObject(Data), 'main_board_dark', APrefs.MainBoardDarkColor);
      LoadColor(TJSONObject(Data), 'analysis_board_light',
        APrefs.AnalysisBoardLightColor);
      LoadColor(TJSONObject(Data), 'analysis_board_dark',
        APrefs.AnalysisBoardDarkColor);
      LoadColor(TJSONObject(Data), 'target_square', APrefs.TargetSquareColor);
      LoadColor(TJSONObject(Data), 'last_move', APrefs.LastMoveColor);
      LoadColor(TJSONObject(Data), 'pv_move', APrefs.PvMoveColor);
      LoadColor(TJSONObject(Data), 'hint_move', APrefs.HintMoveColor);
      APrefs.EvaluationMaxScore := TJSONObject(Data).Get(
        'evaluation_max_score', APrefs.EvaluationMaxScore);
      if SameText(TJSONObject(Data).Get('evaluation_scale', 'logarithmic'),
        'linear') then
        APrefs.EvaluationScale := ssLinear
      else
        APrefs.EvaluationScale := ssLogarithmic;
      if GameId<>'' then begin
        Value:=TJSONObject(Data).Find('game_preferences');
        if (Value<>nil) and (Value.JSONType=jtObject) then begin
          Value:=TJSONObject(Value).Find(GameId);
          if (Value<>nil) and (Value.JSONType=jtObject) then begin
            Layer:=TJSONObject(Value);
            Value := Layer.Find('notation_font_name');
            if (Value<>nil) and (Value.JSONType=jtString) and (Trim(Value.AsString)<>'') then
              APrefs.NotationFontName:=Trim(Value.AsString);
            Value:=Layer.Find('notation_font_size');
            if (Value<>nil) and (Value.JSONType=jtNumber) and
              TryStrToInt(Value.AsJSON,FontSize) and (FontSize>0) then APrefs.NotationFontSize:=FontSize;
            for S:=Low(S) to High(S) do begin
              Key:='notation_'+IntToStr(Ord(S));
              LoadColor(Layer,Key+'_color',APrefs.NotationStyles[S].Color);
              LoadBoolean(Layer,Key+'_bold',APrefs.NotationStyles[S].Bold);
              LoadBoolean(Layer,Key+'_italic',APrefs.NotationStyles[S].Italic);
            end;
            for C:=Low(C) to High(C) do
              LoadColor(Layer,ScoreColorKeys[C],APrefs.ScoreHistoryColors[C]);
            LoadColor(Layer,'main_board_light',APrefs.MainBoardLightColor);
            LoadColor(Layer,'main_board_dark',APrefs.MainBoardDarkColor);
            LoadColor(Layer,'analysis_board_light',APrefs.AnalysisBoardLightColor);
            LoadColor(Layer,'analysis_board_dark',APrefs.AnalysisBoardDarkColor);
            LoadColor(Layer,'target_square',APrefs.TargetSquareColor);
            LoadColor(Layer,'last_move',APrefs.LastMoveColor);
            LoadColor(Layer,'pv_move',APrefs.PvMoveColor);
            LoadColor(Layer,'hint_move',APrefs.HintMoveColor);
            APrefs.EvaluationMaxScore:=Layer.Get('evaluation_max_score',APrefs.EvaluationMaxScore);
            if Layer.Find('evaluation_scale')<>nil then begin
              if SameText(Layer.Get('evaluation_scale','logarithmic'),'linear') then APrefs.EvaluationScale:=ssLinear
              else APrefs.EvaluationScale:=ssLogarithmic;
            end;
          end;
        end;
      end;
    end;
  finally
    Data.Free;
  end;
end;

function PreferencesObject(const P:TGuiPreferences):TJSONObject;
var S:TNotationStyle;C:TScoreHistoryColor;Key:string;
begin
  Result:=TJSONObject.Create;
  for S:=Low(S) to High(S) do begin
    Key:='notation_'+IntToStr(Ord(S));
    Result.Add(Key+'_color',ColorToJsonText(P.NotationStyles[S].Color));
    Result.Add(Key+'_bold',P.NotationStyles[S].Bold);
    Result.Add(Key+'_italic',P.NotationStyles[S].Italic);
  end;
  Result.Add('notation_font_name',P.NotationFontName);
  Result.Add('notation_font_size',P.NotationFontSize);
  for C:=Low(C) to High(C) do Result.Add(ScoreColorKeys[C],ColorToJsonText(P.ScoreHistoryColors[C]));
  Result.Add('main_board_light',ColorToJsonText(P.MainBoardLightColor));
  Result.Add('main_board_dark',ColorToJsonText(P.MainBoardDarkColor));
  Result.Add('analysis_board_light',ColorToJsonText(P.AnalysisBoardLightColor));
  Result.Add('analysis_board_dark',ColorToJsonText(P.AnalysisBoardDarkColor));
  Result.Add('target_square',ColorToJsonText(P.TargetSquareColor));
  Result.Add('last_move',ColorToJsonText(P.LastMoveColor));
  Result.Add('pv_move',ColorToJsonText(P.PvMoveColor));
  Result.Add('hint_move',ColorToJsonText(P.HintMoveColor));
  Result.Add('evaluation_max_score',P.EvaluationMaxScore);
  if P.EvaluationScale=ssLinear then Result.Add('evaluation_scale','linear')
  else Result.Add('evaluation_scale','logarithmic');
end;

function SameGuiPreferences(const A,B:TGuiPreferences):Boolean;
var X,Y:TJSONObject;
begin
  X:=PreferencesObject(A);Y:=PreferencesObject(B);
  try Result:=X.AsJSON=Y.AsJSON;finally X.Free;Y.Free;end;
end;

procedure MergePreferences(Target:TJSONObject;const P:TGuiPreferences);
var Values:TJSONObject;I:Integer;Key:string;
begin
  Values:=PreferencesObject(P);
  try
    for I:=0 to Values.Count-1 do begin
      Key:=Values.Names[I];Target.Delete(Key);Target.Add(Key,Values.Items[I].Clone);
    end;
  finally Values.Free;end;
end;

procedure SaveGamePreferences(const Edits:TGamePreferencesEdits);
var Data,Games,Layer:TJSONObject;Value:TJSONData;I:Integer;
begin
  if Length(Edits)=0 then Exit;
  Data:=ReadPreferenceObject;
  try
    Value:=Data.Find('game_preferences');
    if (Value<>nil) and (Value.JSONType=jtObject) then Games:=TJSONObject(Value)
    else begin Data.Delete('game_preferences');Games:=TJSONObject.Create;Data.Add('game_preferences',Games);end;
    for I:=0 to High(Edits) do begin
      if Trim(Edits[I].GameId)='' then raise EConvertError.Create('Missing preferences game identity');
      Value:=Games.Find(Edits[I].GameId);
      if (Value<>nil) and (Value.JSONType=jtObject) then Layer:=TJSONObject(Value)
      else begin Games.Delete(Edits[I].GameId);Layer:=TJSONObject.Create;Games.Add(Edits[I].GameId,Layer);end;
      MergePreferences(Layer,Edits[I].Preferences);
    end;
    WriteTextFileAtomically(PreferencesJsonFileName,Data.FormatJSON([],2));
  finally Data.Free;end;
end;

procedure SaveGuiPreferences(const APrefs:TGuiPreferences;const GameId:string);
var Edits:TGamePreferencesEdits;Data:TJSONObject;
begin
  if GameId<>'' then begin
    SetLength(Edits,1);Edits[0].GameId:=GameId;Edits[0].Preferences:=APrefs;
    SaveGamePreferences(Edits);
  end else begin
    Data:=ReadPreferenceObject;
    try MergePreferences(Data,APrefs);
      WriteTextFileAtomically(PreferencesJsonFileName,Data.FormatJSON([],2));
    finally Data.Free;end;
  end;
end;

end.
