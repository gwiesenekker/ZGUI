program engine_ini_viewport_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,StdCtrls,
  uEngineEditForm,uGamePosition,uDraughtsPosition,uChessPosition,uGameGuiProfile;
var F:TEngineEditForm;V:TGameVariant;M:TMemo;C:TComboBox;Lines:TStringList;I,J,K,H:Integer;
const Heights:array[0..2] of Integer=(620,480,900);
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 V:=TDraughtsVariant.Create;RegisterGame(V,DraughtsGuiProfile);
 V:=TChessVariant.Create;RegisterGame(V,ChessGuiProfile);
 Lines:=TStringList.Create;
 try
  // Representative Scan INI; keep the test independent of local engine files.
  Lines.Text:='' + LineEnding +
    '# main' + LineEnding +
    '' + LineEnding +
    'variant = normal' + LineEnding +
    'book = false' + LineEnding +
    'book-ply = 4' + LineEnding +
    'book-margin = 4' + LineEnding +
    'threads = 1' + LineEnding +
    'tt-size = 16' + LineEnding +
    'bb-size = 2' + LineEnding +
    '' + LineEnding +
    '# DXP' + LineEnding +
    '' + LineEnding +
    'dxp-server = false' + LineEnding +
    'dxp-host = 127.0.0.1' + LineEnding +
    'dxp-port = 27532' + LineEnding +
    'dxp-initiator = false' + LineEnding +
    'dxp-time = 3' + LineEnding +
    'dxp-moves = 75' + LineEnding +
    'dxp-board = false' + LineEnding +
    'dxp-search = false' + LineEnding +
    '';
  for I:=0 to RegisteredGameCount-1 do begin
   V:=RegisteredGame(I);F:=TEngineEditForm.Create(nil,V);
   try
    F.LoadEngine(nil);M:=nil;C:=nil;
    for J:=0 to F.ComponentCount-1 do begin
     if (F.Components[J] is TMemo) and (Pos('These will be expanded',TMemo(F.Components[J]).Hint)>0) then M:=TMemo(F.Components[J]);
     if (F.Components[J] is TComboBox) and (TComboBox(F.Components[J]).Items.IndexOf('DXP')>=0) then C:=TComboBox(F.Components[J]);
    end;
    if M=nil then raise Exception.Create('INI editor missing');
    M.Lines.Assign(Lines);
    if I=0 then begin C.ItemIndex:=1;C.OnChange(C);end;
    F.Show;
    for K:=0 to High(Heights) do begin
     F.Height:=Heights[K];
     for H:=1 to 10 do begin Application.ProcessMessages;Sleep(5);end;
     WriteLn(V.Name,' height=',F.Height,' INI top=',M.Top,' height=',M.Height,' parent=',M.Parent.ClientHeight);
     if (M.Top+M.Height>M.Parent.ClientHeight) or (M.Height<=0) then
       raise Exception.Create('INI editor/scrollbar clipped outside parent');
     if (M.Lines.Count<>Lines.Count) or (Pos('dxp-search = false',M.Text)=0) then
       raise Exception.Create('INI text lost');
    end;
   finally F.Free;end;
  end;
  WriteLn('PASS: INI text and viewport at minimum, default and larger sizes for both games');
 finally Lines.Free;ClearRegisteredGames;end;
end.
