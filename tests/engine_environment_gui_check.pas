program engine_environment_gui_check;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,Grids,
 ComCtrls,Dialogs,Types,uEngineEnvironmentForm,uEngineEnvironment,uEngineEditForm,uEngineRegistry,
 uChessPosition,uDraughtsPosition,uGamePosition,uEngineParamsJson;
var Checks:Integer;
procedure Check(B:Boolean;const S:string);begin Inc(Checks);if not B then raise Exception.Create(S);end;
type TProbe=class
 Cancel,RawJson:Boolean;Calls,AcceptedCalls:Integer;
 procedure Edit(Data:PtrInt);
 procedure Accepted(Sender:TObject;Engine:TExternalEngineDefinition;var Allow:Boolean);
end;
procedure TProbe.Accepted(Sender:TObject;Engine:TExternalEngineDefinition;var Allow:Boolean);
begin Inc(AcceptedCalls);Check(Engine.EnvironmentJson=CanonicalEngineEnvironment('{"PRIVATE":"edited"}'),'Acceptance callback sees private environment');Allow:=False;end;
procedure TProbe.Edit(Data:PtrInt);
var F:TForm;G:TStringGrid;Pages:TPageControl;Memo:TMemo;I:Integer;B:TButton;
begin
 F:=nil;for I:=0 to Screen.FormCount-1 do if Screen.Forms[I].Caption='Engine environment' then F:=Screen.Forms[I];
 Check(F<>nil,'Environment editor opened');Inc(Calls);
 G:=TStringGrid(F.FindComponent('EnvironmentVariables'));Pages:=TPageControl(F.FindComponent('EnvironmentPages'));
 Check((G<>nil) and (Pages<>nil),'Table and JSON editor exist');
 if RawJson then begin Pages.ActivePageIndex:=1;Memo:=TMemo(F.FindComponent('EnvironmentJson'));Memo.Text:='{ "PRIVATE": "edited" }';end
 else begin G.Cells[0,1]:='PRIVATE';G.Cells[1,1]:='edited';end;
 for I:=0 to F.ComponentCount-1 do if F.Components[I] is TButton then begin
  B:=TButton(F.Components[I]);
  if (Cancel and (B.Caption='Cancel')) or (not Cancel and (B.Caption='OK')) then begin B.Click;Exit;end;
 end;
 raise Exception.Create('No dialog action');
end;
var P:TProbe;Value,Original:string;Def:TExternalEngineDefinition;Editor:TEngineEditForm;
 Variant:TGameVariant;Kind:TExternalEngineKind;Grid:TStringGrid;I,Row:Integer;R:TRect;B:TButton;
begin
 RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
 P:=TProbe.Create;Def:=TExternalEngineDefinition.Create;Editor:=nil;Variant:=nil;
 try
  Value:='{ "PRIVATE": "original" }';Original:=Value;P.Cancel:=True;
  Application.QueueAsyncCall(@P.Edit,0);Check(not EditEngineEnvironment(nil,Value) and (Value=Original),'Cancel preserves exact JSON');
  P.Cancel:=False;Application.QueueAsyncCall(@P.Edit,0);Check(EditEngineEnvironment(nil,Value),'Table accepted');
  Check(Value=CanonicalEngineEnvironment('{"PRIVATE":"edited"}'),'Table returns canonical JSON');
  P.RawJson:=True;Application.QueueAsyncCall(@P.Edit,0);Check(EditEngineEnvironment(nil,Value),'Multiline JSON accepted');
  for Kind:=Low(Kind) to High(Kind) do begin
   if Kind=eekUci then Variant:=TChessVariant.Create else Variant:=TDraughtsVariant.Create;
   Def.Kind:=Kind;Def.EnvironmentJson:='{ "PRIVATE": "original" }';
   Editor:=TEngineEditForm.Create(nil,Variant);
   try
    Editor.LoadEngine(Def);Editor.Font.Size:=16;Editor.Show;Application.ProcessMessages;Grid:=nil;
    for I:=0 to Editor.ComponentCount-1 do if Editor.Components[I] is TStringGrid then Grid:=TStringGrid(Editor.Components[I]);
    Check(Grid<>nil,'Parameter grid found');Row:=0;
    for I:=1 to Grid.RowCount-1 do if Grid.Cells[0,I]='gui-environment' then Row:=I;
    Check((Row>0) and (Grid.Cells[2,Row]=Def.EnvironmentJson),'Registration environment loaded for '+Def.KindText);
    Grid.Row:=Row;Grid.TopRow:=Row;Application.ProcessMessages;R:=Grid.CellRect(2,Row);
    Application.QueueAsyncCall(@P.Edit,0);Grid.OnMouseUp(Grid,mbLeft,[],R.Left+2,R.Top+2);
    Check(Grid.Cells[2,Row]=CanonicalEngineEnvironment('{"PRIVATE":"edited"}'),'Single click edits environment');
    Editor.OnAccepted:=@P.Accepted;
    for I:=0 to Editor.ComponentCount-1 do if Editor.Components[I] is TButton then begin
     B:=TButton(Editor.Components[I]);if B.Caption='Launched correctly' then begin B.Click;Break;end;
    end;
    Editor.LoadEngine(nil);Row:=0;for I:=1 to Grid.RowCount-1 do if Grid.Cells[0,I]='gui-environment' then Row:=I;
    Check((Row>0) and (Grid.Cells[2,Row]='{}'),'New registration does not inherit prior editor overrides');
   finally Editor.Free;Editor:=nil;Variant.Free;Variant:=nil;end;
  end;
  Check(P.AcceptedCalls=3,'Each protocol acceptance callback ran');
  Check(P.Calls=6,'All modal edits completed');
  WriteLn('Engine environment GUI checks passed (',Checks,' checks)');
 finally Editor.Free;Variant.Free;Def.Free;P.Free;end;
end.
