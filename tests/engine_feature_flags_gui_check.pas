program engine_feature_flags_gui_check;
{$mode objfpc}{$H+}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,
  CheckLst,Grids,Dialogs,Math,Types,uGuiDialogs,uEngineFeatureFlags,uEngineFeatureFlagsForm,uEngineEditForm,
  uEngineParamsJson,uEngineRegistry,uChessPosition,uGamePosition;
type TProbe=class
  Cancel:Boolean;Calls:Integer;
  procedure Edit(Data:PtrInt);
end;
var Checks:Integer=0;
procedure Check(B:Boolean;const S:string);
begin Inc(Checks);if not B then raise Exception.Create(S);end;
procedure TProbe.Edit(Data:PtrInt);
var F:TForm;List:TCheckListBox;I,W:Integer;
begin
  F:=nil;for I:=0 to Screen.FormCount-1 do if Screen.Forms[I].Caption='Engine compatibility features' then F:=Screen.Forms[I];
  Check(F<>nil,'Friendly editor opens');
  List:=nil;for I:=0 to F.ComponentCount-1 do if F.Components[I] is TCheckListBox then List:=TCheckListBox(F.Components[I]);
  Check((List<>nil) and (List.Count=4),'Known flags and preserved additional flag are displayed');
  W:=0;for I:=0 to 2 do W:=Max(W,MeasureGuiText(List.Items[I],List.Font).cx);
  Check(List.ClientWidth>W,'Known flag captions fit the measured viewport');
  Inc(Calls);List.Checked[0]:=True;List.Checked[2]:=True;
  if Cancel then F.ModalResult:=mrCancel else F.ModalResult:=mrOk;
end;
var Probe:TProbe;Value,Original:string;Flags:TStringList;P,Loaded:TEngineParamArray;
    D:TExternalEngineDefinition;V:TChessVariant;Editor:TEngineEditForm;Grid:TStringGrid;
    I,Row:Integer;R:TRect;Raised:Boolean;FileName:string;
begin
  RequireDerivedFormResource:=False;Application.Initialize;Application.CaptureExceptions:=False;
  Probe:=TProbe.Create;V:=TChessVariant.Create;Editor:=nil;D:=TExternalEngineDefinition.Create;
  FileName:=GetTempFileName(GetTempDir,'flags');
  try
    Flags:=ParseEngineFeatureFlags('["no-pondering","NO-PONDERING","future-feature"]');
    try Check(Flags.Count=2,'Flag names normalised and duplicates removed');finally Flags.Free;end;
    for I:=0 to 3 do begin
      case I of 0:Value:='{}';1:Value:='[true]';2:Value:='[""]';3:Value:='["bad flag"]';end;
      Raised:=False;try Flags:=ParseEngineFeatureFlags(Value);Flags.Free;except on E:EConvertError do Raised:=True;end;
      Check(Raised,'Invalid flags rejected');
    end;
    Value:='["future-feature"]';Original:=Value;Probe.Cancel:=True;
    Application.QueueAsyncCall(@Probe.Edit,0);Check(not EditEngineFeatureFlags(nil,Value) and (Value=Original),'Cancel retains JSON exactly');
    Probe.Cancel:=False;Application.QueueAsyncCall(@Probe.Edit,0);Check(EditEngineFeatureFlags(nil,Value),'Checkbox selection accepted');
    Check(HasEngineFeatureFlag(Value,'dxp-pv') and HasEngineFeatureFlag(Value,'no-pondering') and
      HasEngineFeatureFlag(Value,'future-feature'),'Known selections and unknown flags preserved');
    P:=nil;SeedDefaultGuiParams(P,D);AddOrUpdateParam(P,'gui-feature-flags','string',Value,False);
    SaveEngineParamsToJson(FileName,'hub',P);LoadEngineParamsFromJson(FileName,'hub',Loaded);
    Check(EngineParamValue(Loaded,'gui-feature-flags','')=Value,'JSON string round-trips inside parameter JSON');
    Check(not EngineParamShouldSendToHub('gui-feature-flags'),'Feature flags are never Hub engine options');
    Editor:=TEngineEditForm.Create(nil,V);Editor.LoadEngine(nil);Editor.Show;Application.ProcessMessages;Grid:=nil;
    for I:=0 to Editor.ComponentCount-1 do if Editor.Components[I] is TStringGrid then Grid:=TStringGrid(Editor.Components[I]);
    Row:=0;for I:=1 to Grid.RowCount-1 do if Grid.Cells[0,I]='gui-feature-flags' then Row:=I;
    Check(Row>0,'Existing parameter grid contains GUI feature-flags row');
    Editor.Font.Size:=16;Application.ProcessMessages;
    Grid.Cells[2,Row]:='["future-feature"]';Grid.Row:=Row;Grid.TopRow:=Row;Application.ProcessMessages;
    R:=Grid.CellRect(2,Row);Application.QueueAsyncCall(@Probe.Edit,0);Grid.OnMouseUp(Grid,mbLeft,[],R.Left+2,R.Top+2);
    Check(HasEngineFeatureFlag(Grid.Cells[2,Row],'dxp-pv'),'Single click in the existing grid opens the checkbox editor');
    Check(Probe.Calls=3,'Each editor interaction completed');
    WriteLn('Engine feature flags checks passed (',Checks,' checks)');
  finally Editor.Free;D.Free;V.Free;Probe.Free;DeleteFile(FileName);end;
end.
