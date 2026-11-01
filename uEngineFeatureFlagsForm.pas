unit uEngineFeatureFlagsForm;
{$mode objfpc}{$H+}
interface
uses Classes,Forms;
function EditEngineFeatureFlags(Owner:TCustomForm;var Value:string):Boolean;
implementation
uses SysUtils,Controls,StdCtrls,CheckLst,ExtCtrls,Dialogs,Math,uEngineFeatureFlags,uGuiDialogs,uGuiLayout;
function EditEngineFeatureFlags(Owner:TCustomForm;var Value:string):Boolean;
const Names:array[0..2]of string=(FeatureNoPondering,FeatureNoPonderHit,FeatureDxpPv);
  Captions:array[0..2]of string=('Disable pondering',
    'Restart the search on a ponder hit (do not send ponder-hit / ponderhit)',
    'DXP: read Hub-format PV and evaluation from stdout');
var Form:TGuiLayoutForm;List:TCheckListBox;Info:TLabel;Buttons:TPanel;B:TButton;
    Flags,Selected:TStringList;I,TextHeight,TextWidth,Margin:Integer;
begin
  Result:=False;Flags:=ParseEngineFeatureFlags(Value);Selected:=TStringList.Create;Form:=TGuiLayoutForm.CreateNew(Owner);
  try
    Form.Caption:='Engine compatibility features';Form.Position:=poDesigned;Form.BorderStyle:=bsSizeable;
    if Owner<>nil then Form.Font.Assign(Owner.Font);
    TextHeight:=MeasureGuiText('Ag',Form.Font).cy;Margin:=Max(8,TextHeight div 2);TextWidth:=0;
    for I:=0 to High(Captions) do TextWidth:=Max(TextWidth,MeasureGuiText(Captions[I],Form.Font).cx);
    Form.ClientWidth:=TextWidth+6*Margin;Form.ClientHeight:=14*TextHeight+6*Margin;
    Form.Constraints.MinWidth:=Form.Width;
    Info:=TLabel.Create(Form);Info.Parent:=Form;Info.Align:=alTop;Info.BorderSpacing.Around:=12;
    Info.AutoSize:=True;Info.WordWrap:=True;
    Info.Caption:='These settings belong to the GUI and are never sent as engine options.'+LineEnding+
      'Disable pondering takes precedence over the ponder-hit setting. DXP stdout PV does not define an analysis command.';
    Buttons:=TPanel.Create(Form);Buttons.Parent:=Form;Buttons.Align:=alBottom;Buttons.Height:=46;Buttons.BevelOuter:=bvNone;
    B:=TButton.Create(Form);B.Parent:=Buttons;B.Align:=alRight;B.Width:=90;B.Caption:='Cancel';B.ModalResult:=mrCancel;B.Cancel:=True;
    B:=TButton.Create(Form);B.Parent:=Buttons;B.Align:=alRight;B.Width:=90;B.Caption:='OK';B.ModalResult:=mrOk;B.Default:=True;
    List:=TCheckListBox.Create(Form);List.Parent:=Form;List.Align:=alClient;List.BorderSpacing.Around:=Margin;
    List.Constraints.MinHeight:=5*TextHeight;
    for I:=0 to High(Names) do begin Selected.Add(Names[I]);List.Items.Add(Captions[I]);List.Checked[I]:=Flags.IndexOf(Names[I])>=0;end;
    // Unknown flags survive editing so newer configurations remain usable.
    for I:=0 to Flags.Count-1 do if Selected.IndexOf(Flags[I])<0 then begin
      Selected.Add(Flags[I]);List.Items.Add('Additional flag: '+Flags[I]);List.Checked[List.Count-1]:=True;
    end;
    TextWidth:=0;
    for I:=0 to List.Count-1 do TextWidth:=Max(TextWidth,MeasureGuiText(List.Items[I],Form.Font).cx);
    List.ScrollWidth:=TextWidth+3*Margin;
    Form.EnableAutoLayout;
    CenterFormOnOwner(Form,Owner);Result:=Form.ShowModal=mrOk;
    if Result then begin
      Flags.Clear;for I:=0 to Selected.Count-1 do if List.Checked[I] then Flags.Add(Selected[I]);
      Value:=EngineFeatureFlagsJson(Flags);
    end;
  finally Form.Free;Selected.Free;Flags.Free;end;
end;
end.
