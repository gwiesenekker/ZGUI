unit uEngineEnvironmentForm;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes,Forms,uGuiLayout,StdCtrls,Grids,ComCtrls;
type
 TEngineEnvironmentDialog=class(TGuiLayoutForm)
 private
  FGrid:TStringGrid;
  FJson:TMemo;
  FPages:TPageControl;
  function TableJson:string;
  procedure FillTable(const AValue:string);
  procedure PageChanging(Sender:TObject;var AllowChange:Boolean);
  procedure AddRow(Sender:TObject);
  procedure RemoveRow(Sender:TObject);
  procedure Accept(Sender:TObject);
 public
  Value:string;
  constructor Create(AOwner:TComponent);override;
 end;
function EditEngineEnvironment(Owner:TCustomForm;var Value:string):Boolean;
implementation
uses SysUtils,Controls,ExtCtrls,Dialogs,Math,fpjson,uEngineEnvironment,uGuiDialogs;
constructor TEngineEnvironmentDialog.Create(AOwner:TComponent);
var Info:TLabel;Buttons,Tools:TPanel;TableTab,JsonTab:TTabSheet;B,CancelButton,AddButton:TButton;H:Integer;
begin
 inherited CreateNew(AOwner);
 Caption:='Engine environment';Position:=poDesigned;BorderStyle:=bsSizeable;
 if AOwner is TCustomForm then Font.Assign(TCustomForm(AOwner).Font);
 H:=MeasureGuiText('Ag',Font).cy;
 ClientWidth:=Max(620,MeasureGuiText('GWD_LMR_POLICY_LOGIT_THRESHOLD',Font).cx*2+80);
 ClientHeight:=Max(360,H*20);
 Info:=TLabel.Create(Self);Info.Parent:=Self;Info.Align:=alTop;Info.AutoSize:=True;
 Info.WordWrap:=True;Info.BorderSpacing.Around:=8;
 Info.Caption:='Inherit the current environment and override these variables for this engine only.'+LineEnding+
   'Values are strings. An empty value sets an empty variable; removing a row restores inheritance.';
 Buttons:=TPanel.Create(Self);Buttons.Parent:=Self;Buttons.Align:=alBottom;Buttons.BevelOuter:=bvNone;
 B:=TButton.Create(Self);B.Parent:=Buttons;B.Caption:='Cancel';B.Cancel:=True;B.ModalResult:=mrCancel;CancelButton:=B;
 B:=TButton.Create(Self);B.Parent:=Buttons;B.Caption:='OK';B.Default:=True;B.OnClick:=@Accept;
 LayoutFlow(Buttons,[CancelButton,B]);Buttons.AutoSize:=True;
 FPages:=TPageControl.Create(Self);FPages.Name:='EnvironmentPages';FPages.Parent:=Self;FPages.Align:=alClient;
 TableTab:=TTabSheet.Create(Self);TableTab.PageControl:=FPages;TableTab.Caption:='Variables';
 JsonTab:=TTabSheet.Create(Self);JsonTab.PageControl:=FPages;JsonTab.Caption:='JSON';
 Tools:=TPanel.Create(Self);Tools.Parent:=TableTab;Tools.Align:=alBottom;Tools.BevelOuter:=bvNone;
 B:=TButton.Create(Self);B.Parent:=Tools;B.Caption:='Add';B.OnClick:=@AddRow;AddButton:=B;
 B:=TButton.Create(Self);B.Parent:=Tools;B.Caption:='Remove';B.OnClick:=@RemoveRow;
 LayoutFlow(Tools,[AddButton,B]);Tools.AutoSize:=True;
 FGrid:=TStringGrid.Create(Self);FGrid.Name:='EnvironmentVariables';FGrid.Parent:=TableTab;FGrid.Align:=alClient;
 FGrid.FixedCols:=0;FGrid.ColCount:=2;FGrid.RowCount:=2;FGrid.FixedRows:=1;
 FGrid.Cells[0,0]:='Name';FGrid.Cells[1,0]:='Value';
 FGrid.Options:=FGrid.Options+[goEditing,goColSizing,goThumbTracking];
 FGrid.AutoFillColumns:=True;FGrid.ColWidths[0]:=MeasureGuiText('GWD_LMR_POLICY_LOGIT_THRESHOLD',Font).cx+20;
 FJson:=TMemo.Create(Self);FJson.Name:='EnvironmentJson';FJson.Parent:=JsonTab;FJson.Align:=alClient;
 FJson.ScrollBars:=ssAutoBoth;FJson.WordWrap:=False;
 FPages.OnChanging:=@PageChanging;
 EnableAutoLayout;
end;
function TEngineEnvironmentDialog.TableJson:string;
var Obj:TJSONObject;I:Integer;VarName:string;
begin
 FGrid.EditorMode:=False;Obj:=TJSONObject.Create;
 try
  for I:=1 to FGrid.RowCount-1 do begin
   VarName:=FGrid.Cells[0,I];
   if (VarName='') and (FGrid.Cells[1,I]='') then Continue;
   Obj.Add(VarName,FGrid.Cells[1,I]);
  end;
  Result:=CanonicalEngineEnvironment(Obj.AsJSON);
 finally Obj.Free;end;
end;
procedure TEngineEnvironmentDialog.FillTable(const AValue:string);
var Obj:TJSONObject;I:Integer;
begin
 Obj:=ParseEngineEnvironment(AValue);
 try
  FGrid.RowCount:=Max(2,Obj.Count+1);FGrid.Rows[1].Clear;
  for I:=0 to Obj.Count-1 do begin FGrid.Cells[0,I+1]:=Obj.Names[I];FGrid.Cells[1,I+1]:=Obj.Items[I].AsString;end;
  FJson.Text:=Obj.FormatJSON;
 finally Obj.Free;end;
end;
procedure TEngineEnvironmentDialog.PageChanging(Sender:TObject;var AllowChange:Boolean);
begin
 try
  if FPages.ActivePageIndex=0 then begin FillTable(TableJson);end
  else FillTable(CanonicalEngineEnvironment(FJson.Text));
 except on E:Exception do begin AllowChange:=False;ShowGuiOkDialog(Self,'Invalid environment',E.Message);end;end;
end;
procedure TEngineEnvironmentDialog.AddRow(Sender:TObject);
begin FGrid.RowCount:=FGrid.RowCount+1;FGrid.Row:=FGrid.RowCount-1;FGrid.SetFocus;end;
procedure TEngineEnvironmentDialog.RemoveRow(Sender:TObject);
var I:Integer;
begin
 for I:=FGrid.Row to FGrid.RowCount-2 do FGrid.Rows[I].Assign(FGrid.Rows[I+1]);
 if FGrid.RowCount>2 then FGrid.RowCount:=FGrid.RowCount-1 else FGrid.Rows[1].Clear;
end;
procedure TEngineEnvironmentDialog.Accept(Sender:TObject);
begin
 try
  if FPages.ActivePageIndex=0 then Value:=TableJson else Value:=CanonicalEngineEnvironment(FJson.Text);
  ModalResult:=mrOk;
 except on E:Exception do ShowGuiOkDialog(Self,'Invalid environment',E.Message);end;
end;
function EditEngineEnvironment(Owner:TCustomForm;var Value:string):Boolean;
var Form:TEngineEnvironmentDialog;
begin
 Form:=TEngineEnvironmentDialog.Create(Owner);
 try
  Form.FillTable(Value);CenterFormOnOwner(Form,Owner);Result:=Form.ShowModal=mrOk;
  if Result then Value:=Form.Value;
 finally Form.Free;end;
end;
end.
