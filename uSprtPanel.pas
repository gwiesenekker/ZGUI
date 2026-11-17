unit uSprtPanel;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Controls,ExtCtrls,StdCtrls,Grids,Graphics,Forms,uSprt,uGuiLayout;
type
 TSprtGraph=class(TGraphicControl)
 private FReport:TSprtReport;FPoints:array of TPoint;
 protected
  procedure Paint;override;
  procedure MouseMove(Shift:TShiftState;X,Y:Integer);override;
  procedure MouseLeave;override;
 public
  function PointAt(X,Y:Integer):Integer;
  function PointHint(Index:Integer):string;
  procedure SetReport(const R:TSprtReport);
 end;
 TSprtPanel=class(TGuiCompositePanel)
 private
  FConfig:TSprtConfig;FKeys:TStringList;FUpdating,FMeasuring,FExpanded:Boolean;
  FUserHeight,FMeasuredHeight:Integer;
  FHeading:TButton;FBody:TScrollBox;FSelectors,FInfo,FData:TPanel;
  FReport:TSprtReport;
  FCandidate,FBaseline:TComboBox;FCandidateLabel,FBaselineLabel,FInfoText,FStatus,FHeadline:TLabel;
  FSwap,FSettings:TButton;FCounts:TStringGrid;FGraph:TSprtGraph;
  FOnChanged:TNotifyEvent;
  procedure Toggle(Sender:TObject);procedure SelectionChanged(Sender:TObject);
  procedure Swap(Sender:TObject);procedure Settings(Sender:TObject);
 protected procedure Resize;override;
 public
  constructor Create(AOwner:TComponent);override;destructor Destroy;override;
  procedure SetParticipants(Names,Keys:TStrings);
  procedure SetConfig(const C:TSprtConfig);
  procedure ApplyConfig(const C:TSprtConfig);
  procedure ShowReport(const R:TSprtReport;Amended:Boolean;const ErrorText:string);
  procedure RefreshMeasurements;
  property Config:TSprtConfig read FConfig;
  property OnChanged:TNotifyEvent read FOnChanged write FOnChanged;
  property Expanded:Boolean read FExpanded;
  property Report:TSprtReport read FReport;
 end;
implementation
uses Math,Dialogs,uGuiDialogs,LCLIntf,LCLType;
procedure TSprtGraph.SetReport(const R:TSprtReport);
var I:Integer;Same:Boolean;
begin
 Same:=(R.Included=FReport.Included) and (R.Lower=FReport.Lower) and (R.Upper=FReport.Upper) and
  (R.DecisionPair=FReport.DecisionPair) and (Length(R.Trace)=Length(FReport.Trace));
 if Same then for I:=0 to High(R.Trace) do
  if (R.Trace[I].Opening<>FReport.Trace[I].Opening) or (R.Trace[I].LLR<>FReport.Trace[I].LLR) or (R.Trace[I].MeanScore<>FReport.Trace[I].MeanScore) then begin Same:=False;Break;end;
 if Same then Exit;
 Hint:='';Application.CancelHint;FPoints:=nil;FReport:=R;Invalidate;
end;
function TSprtGraph.PointHint(Index:Integer):string;
begin
 Result:='';if (Index<0) or (Index>=Length(FReport.Trace)) then Exit;
 Result:='Opening pair '+IntToStr(FReport.Trace[Index].Opening)+LineEnding+
  'LLR: '+FormatFloat('0.0000',FReport.Trace[Index].LLR);
 if FReport.Trace[Index].MeanScore<=0 then Result+=LineEnding+'Estimated Elo: -infinity (all losses)'
 else if FReport.Trace[Index].MeanScore>=1 then Result+=LineEnding+'Estimated Elo: +infinity (all wins)'
 else Result+=LineEnding+'Estimated Elo: '+FormatFloat('+0.0;-0.0;0.0',400*Log10(FReport.Trace[Index].MeanScore/(1-FReport.Trace[Index].MeanScore)));
 if FReport.Trace[Index].Opening=FReport.DecisionPair then Result+=LineEnding+'First '+UpperCase(FReport.Decision)+' crossing';
end;
function TSprtGraph.PointAt(X,Y:Integer):Integer;
var I,Distance,Best,Radius:Integer;
begin
 Result:=-1;Radius:=Max(8,MeasureGuiText('Ag',Font).cy div 2);Best:=Radius*Radius+1;
 for I:=0 to High(FPoints) do begin
  Distance:=Sqr(X-FPoints[I].X)+Sqr(Y-FPoints[I].Y);
  if Distance<Best then begin Result:=I;Best:=Distance;end;
 end;
end;
procedure TSprtGraph.MouseMove(Shift:TShiftState;X,Y:Integer);
var HintText:string;
begin
 inherited MouseMove(Shift,X,Y);HintText:=PointHint(PointAt(X,Y));
 if Hint=HintText then Exit;Hint:=HintText;Application.CancelHint;
 if HintText<>'' then Application.ActivateHint(ClientToScreen(Point(X,Y)),True);
end;
procedure TSprtGraph.MouseLeave;
begin inherited MouseLeave;Hint:='';Application.CancelHint;end;
procedure TSprtGraph.Paint;
var R:TRect;I,X,Y,PrevX,PrevY,BottomPad,LeftPad:Integer;Low,High:Double;
 function PosY(V:Double):Integer;
 begin Result:=R.Bottom-Round((V-Low)/(High-Low)*(R.Bottom-R.Top));end;
begin
 Canvas.Brush.Color:=clWindow;Canvas.FillRect(ClientRect);Canvas.Font.Assign(Font);
 BottomPad:=Canvas.TextHeight('Ag')+8;
 LeftPad:=Max(Canvas.TextWidth('H0 '+FormatFloat('0.00',FReport.Lower)),
  Canvas.TextWidth('H1 '+FormatFloat('0.00',FReport.Upper)))+8;
 R:=Rect(LeftPad,Canvas.TextHeight('Ag')+10,Max(LeftPad+1,Width-12),Max(Canvas.TextHeight('Ag')+11,Height-BottomPad));
 Low:=Min(-1,FReport.Lower);High:=Max(1,FReport.Upper);
 for I:=0 to System.High(FReport.Trace) do begin Low:=Min(Low,FReport.Trace[I].LLR);High:=Max(High,FReport.Trace[I].LLR);end;
 Low:=Low-0.15;High:=High+0.15;
 Canvas.TextOut(R.Left,0,'Evidence (LLR): '+FormatFloat('0.0000',FReport.LLR));
 Canvas.Pen.Color:=clGray;Canvas.MoveTo(R.Left,PosY(0));Canvas.LineTo(R.Right,PosY(0));
 Canvas.Pen.Style:=psDot;Canvas.Pen.Color:=clMaroon;
 Y:=PosY(FReport.Lower);Canvas.MoveTo(R.Left,Y);Canvas.LineTo(R.Right,Y);Canvas.TextOut(2,Y-Canvas.TextHeight('Ag') div 2,'H0 '+FormatFloat('0.00',FReport.Lower));
 Y:=PosY(FReport.Upper);Canvas.MoveTo(R.Left,Y);Canvas.LineTo(R.Right,Y);Canvas.TextOut(2,Y-Canvas.TextHeight('Ag') div 2,'H1 '+FormatFloat('0.00',FReport.Upper));
 Canvas.Pen.Style:=psSolid;Canvas.Pen.Color:=clNavy;Canvas.Pen.Width:=2;
 PrevX:=R.Left;PrevY:=PosY(0);SetLength(FPoints,Length(FReport.Trace));
 for I:=0 to System.High(FReport.Trace) do begin
  X:=R.Left+Round((I+1)/Max(1,Length(FReport.Trace))*(R.Right-R.Left));Y:=PosY(FReport.Trace[I].LLR);
  Canvas.MoveTo(PrevX,PrevY);Canvas.LineTo(X,Y);FPoints[I]:=Point(X,Y);PrevX:=X;PrevY:=Y;
 end;
 Canvas.Pen.Width:=1;Canvas.Brush.Color:=clNavy;
 for I:=0 to System.High(FPoints) do Canvas.Ellipse(FPoints[I].X-2,FPoints[I].Y-2,FPoints[I].X+3,FPoints[I].Y+3);
 if (FReport.DecisionPair>0) and (Length(FReport.Trace)>0) then begin
  Canvas.Brush.Color:=clNavy;Canvas.Ellipse(PrevX-4,PrevY-4,PrevX+4,PrevY+4);
 end;
 Canvas.Brush.Color:=clWindow;
 Canvas.TextOut(R.Left,Height-BottomPad+4,'Opening pairs: '+IntToStr(FReport.Included));
end;
function Panel(AOwner:TComponent;Parent:TWinControl):TPanel;
begin Result:=TPanel.Create(AOwner);Result.Parent:=Parent;Result.BevelOuter:=bvNone;end;
constructor TSprtPanel.Create(AOwner:TComponent);
var I:Integer;
begin
 inherited Create(AOwner);BevelOuter:=bvNone;Name:='TournamentSprt';FKeys:=TStringList.Create;FConfig:=DefaultSprtConfig;
 FHeading:=TButton.Create(Self);FHeading.Parent:=Self;FHeading.Name:='SprtToggle';FHeading.Caption:='SPRT comparison >';FHeading.OnClick:=@Toggle;
 FBody:=TScrollBox.Create(Self);FBody.Parent:=Self;FBody.BorderStyle:=bsNone;FBody.AutoScroll:=True;FBody.HorzScrollBar.Visible:=False;FBody.Visible:=False;
 FSelectors:=Panel(Self,FBody);FInfo:=Panel(Self,FBody);FData:=Panel(Self,FBody);
 FCandidateLabel:=TLabel.Create(Self);FCandidateLabel.Parent:=FSelectors;FCandidateLabel.Caption:='Candidate';FCandidateLabel.AutoSize:=False;
 FBaselineLabel:=TLabel.Create(Self);FBaselineLabel.Parent:=FSelectors;FBaselineLabel.Caption:='Baseline';FBaselineLabel.AutoSize:=False;
 FCandidate:=TComboBox.Create(Self);FCandidate.Parent:=FSelectors;FCandidate.Name:='SprtCandidate';FCandidate.Style:=csDropDownList;FCandidate.OnChange:=@SelectionChanged;
 FBaseline:=TComboBox.Create(Self);FBaseline.Parent:=FSelectors;FBaseline.Name:='SprtBaseline';FBaseline.Style:=csDropDownList;FBaseline.OnChange:=@SelectionChanged;
 FSwap:=TButton.Create(Self);FSwap.Parent:=FSelectors;FSwap.Name:='SprtSwap';FSwap.Caption:='Swap';FSwap.OnClick:=@Swap;
 FSettings:=TButton.Create(Self);FSettings.Parent:=FInfo;FSettings.Caption:='SPRT settings...';FSettings.Name:='SprtSettings';FSettings.OnClick:=@Settings;
 FInfoText:=TLabel.Create(Self);FInfoText.Parent:=FInfo;FInfoText.AutoSize:=False;FInfoText.ShowHint:=True;
 FHeadline:=TLabel.Create(Self);FHeadline.Parent:=FBody;FHeadline.AutoSize:=False;
 FStatus:=TLabel.Create(Self);FStatus.Parent:=FBody;FStatus.AutoSize:=False;FStatus.WordWrap:=True;FStatus.ShowHint:=True;
 FCounts:=TStringGrid.Create(Self);FCounts.Parent:=FData;FCounts.Name:='SprtCounts';FCounts.ColCount:=2;FCounts.RowCount:=6;
 FCounts.FixedCols:=0;FCounts.FixedRows:=1;FCounts.ScrollBars:=ssNone;FCounts.Options:=FCounts.Options-[goEditing,goRowSelect];
 FCounts.Cells[0,0]:='Pair score';FCounts.Cells[1,0]:='Count';
 FCounts.Cells[0,1]:='0 (LL)';FCounts.Cells[0,2]:='0.5 (LD/DL)';FCounts.Cells[0,3]:='1 (DD/WL/LW)';
 FCounts.Cells[0,4]:='1.5 (WD/DW)';FCounts.Cells[0,5]:='2 (WW)';
 FGraph:=TSprtGraph.Create(Self);FGraph.Parent:=FData;FGraph.Name:='SprtGraph';FGraph.ShowHint:=True;FGraph.ParentShowHint:=False;
 RefreshMeasurements;
end;
destructor TSprtPanel.Destroy;
begin FKeys.Free;inherited Destroy;end;
procedure TSprtPanel.Resize;
begin
 inherited Resize;
 if FExpanded and not FMeasuring and (Height<>FMeasuredHeight) then FUserHeight:=Height;
 if FHeading<>nil then RefreshMeasurements;
end;
procedure TSprtPanel.RefreshMeasurements;
var H,Gap,ToggleH,NameW,SwapW,SettingsW,LeftW,DataH,W,StatusH,PrefW,Wanted,Limit,LabelW,CountW,ComboH:Integer;
begin
 if FMeasuring then Exit;FMeasuring:=True;
 try
  H:=MeasureGuiText('Ag',Font).cy;Gap:=Max(4,H div 3);ToggleH:=Max(26,H+12);W:=Max(1,ClientWidth);
  PrefW:=0;ComboH:=0;FCandidate.GetPreferredSize(PrefW,ComboH,True);
  ToggleH:=Max(ToggleH,ComboH);
  Constraints.MinHeight:=ToggleH;
  FHeading.SetBounds(0,0,W,ToggleH);FBody.SetBounds(0,ToggleH,W,Max(1,Height-ToggleH));
  W:=Max(1,ClientWidth-GetSystemMetrics(SM_CXVSCROLL)-2);
  NameW:=Max(MeasureGuiText('Candidate',Font).cx,MeasureGuiText('Baseline',Font).cx)+Gap;
  SwapW:=MeasureGuiText('Swap',Font).cx+24;
  if W<480 then begin
   FSelectors.SetBounds(0,0,W,2*(ToggleH+Gap));
   FCandidateLabel.SetBounds(Gap,Gap,NameW,H);FCandidate.SetBounds(NameW+Gap,0,Max(20,W-NameW-SwapW-3*Gap),FCandidate.Height);
   FBaselineLabel.SetBounds(Gap,ToggleH+2*Gap,NameW,H);FBaseline.SetBounds(NameW+Gap,ToggleH+Gap,FCandidate.Width,FBaseline.Height);
  end else begin
   FSelectors.SetBounds(0,0,W,ToggleH+Gap);
   LeftW:=(W-SwapW-4*Gap) div 2;
   FCandidateLabel.SetBounds(Gap,Gap,NameW,H);FCandidate.SetBounds(NameW+Gap,0,Max(20,LeftW-NameW),FCandidate.Height);
   FBaselineLabel.SetBounds(LeftW+2*Gap,Gap,NameW,H);FBaseline.SetBounds(LeftW+NameW+2*Gap,0,Max(20,LeftW-NameW),FBaseline.Height);
  end;
  FSwap.SetBounds(W-SwapW-Gap,0,SwapW,ToggleH);
  FInfo.SetBounds(0,FSelectors.Height,W,ToggleH+Gap);
  SettingsW:=MeasureGuiText('SPRT settings...',Font).cx+24;FSettings.SetBounds(Gap,0,SettingsW,ToggleH);
  FInfoText.SetBounds(SettingsW+2*Gap,Gap,Max(1,W-SettingsW-3*Gap),H+4);
  FHeadline.Font.Name:=Font.Name;FHeadline.Font.Size:=Font.Size;FHeadline.Font.Color:=Font.Color;FHeadline.Font.Style:=Font.Style+[fsBold];
  FHeadline.SetBounds(Gap,FInfo.Top+FInfo.Height,Max(1,W-2*Gap),H+4);
  FStatus.SetBounds(Gap,FHeadline.Top+FHeadline.Height,Max(1,W-2*Gap),FStatus.Height);
  FStatus.GetPreferredSize(PrefW,StatusH);StatusH:=Max(2*H,StatusH)+Gap;FStatus.Height:=StatusH;
  FCounts.Canvas.Font.Assign(Font);FCounts.DefaultRowHeight:=H+8;
  LabelW:=MeasureGuiText('1 (DD/WL/LW)',Font).cx+20;CountW:=MeasureGuiText('999999',Font).cx+20;
  LeftW:=LabelW+CountW+4;FCounts.ColWidths[0]:=LabelW;FCounts.ColWidths[1]:=CountW;
  DataH:=6*(H+8)+8;
  FCounts.SetBounds(Gap,0,LeftW,DataH);
  if W<LeftW+200 then begin
   FGraph.SetBounds(Gap,DataH+Gap,Max(1,W-2*Gap),Max(120,DataH));
  end else FGraph.SetBounds(LeftW+2*Gap,0,Max(1,W-LeftW-3*Gap),DataH);
  if W<LeftW+200 then FData.SetBounds(0,FStatus.Top+StatusH,W,DataH+Gap+FGraph.Height)
  else FData.SetBounds(0,FStatus.Top+StatusH,W,DataH);
  Wanted:=ToggleH;
  if FExpanded then begin
   Wanted:=ToggleH+FData.Top+FData.Height+Gap;if FUserHeight>0 then Wanted:=Max(ToggleH+60,FUserHeight);
   if Parent<>nil then begin Limit:=Max(ToggleH+60,Parent.ClientHeight-60);Wanted:=Min(Wanted,Limit);end;
  end;
  Height:=Wanted;FMeasuredHeight:=Height;
  FBody.Height:=Max(1,Height-ToggleH);
 finally FMeasuring:=False;end;
end;
procedure TSprtPanel.Toggle(Sender:TObject);
begin
 FExpanded:=not FExpanded;FBody.Visible:=FExpanded;
 if FExpanded then FHeading.Caption:='SPRT comparison v' else FHeading.Caption:='SPRT comparison >';
 RefreshMeasurements;
end;
procedure TSprtPanel.SetConfig(const C:TSprtConfig);
begin
 FUpdating:=True;
 try FConfig:=C;FCandidate.ItemIndex:=FKeys.IndexOf(C.CandidateKey);FBaseline.ItemIndex:=FKeys.IndexOf(C.BaselineKey);
 finally FUpdating:=False;end;
end;
procedure TSprtPanel.ApplyConfig(const C:TSprtConfig);
begin
 ValidateSprtConfig(C,True);if FConfig.Stored and SameSprtDesign(C,FConfig) then Exit;
 SetConfig(C);if Assigned(FOnChanged) then FOnChanged(Self);
end;
procedure TSprtPanel.SetParticipants(Names,Keys:TStrings);
begin
 FUpdating:=True;
 try
  if (FKeys.Text<>Keys.Text) or (FCandidate.Items.Text<>Names.Text) then begin
   FKeys.Assign(Keys);FCandidate.Items.Assign(Names);FBaseline.Items.Assign(Names);
  end;
  if (Keys.Count=2) and (FConfig.CandidateKey='') and (FConfig.BaselineKey='') then begin
   FConfig.CandidateKey:=Keys[0];FConfig.BaselineKey:=Keys[1];
  end;
  FCandidate.ItemIndex:=Keys.IndexOf(FConfig.CandidateKey);FBaseline.ItemIndex:=Keys.IndexOf(FConfig.BaselineKey);
 finally FUpdating:=False;end;
end;
procedure TSprtPanel.SelectionChanged(Sender:TObject);
var C:TSprtConfig;
begin
 if FUpdating then Exit;
 C:=FConfig;C.CandidateKey:='';C.BaselineKey:='';
 if FCandidate.ItemIndex>=0 then C.CandidateKey:=FKeys[FCandidate.ItemIndex];
 if FBaseline.ItemIndex>=0 then C.BaselineKey:=FKeys[FBaseline.ItemIndex];
 if (C.CandidateKey<>'') and (C.CandidateKey=C.BaselineKey) then begin
  if Sender=FCandidate then C.BaselineKey:='' else C.CandidateKey:='';
 end;
 if FConfig.Stored and SameSprtDesign(C,FConfig) then Exit;
 SetConfig(C);if Assigned(FOnChanged) then FOnChanged(Self);
end;
procedure TSprtPanel.Swap(Sender:TObject);
var C:TSprtConfig;K:string;
begin
 C:=FConfig;K:=C.CandidateKey;C.CandidateKey:=C.BaselineKey;C.BaselineKey:=K;
 if (C.CandidateKey='') or (C.BaselineKey='') then Exit;ApplyConfig(C);
end;
procedure TSprtPanel.Settings(Sender:TObject);
var Dialog:TForm;Edits:array[0..3] of TEdit;L:TLabel;OK,Cancel:TButton;I,Y,W,H:Integer;C:TSprtConfig;
const Captions:array[0..3] of string=('H0 logistic Elo','H1 logistic Elo','Alpha (fraction)','Beta (fraction)');
begin
 Dialog:=TForm.Create(GetParentForm(Self));
 try
  Dialog.Caption:='Paired SPRT test settings';Dialog.BorderStyle:=bsDialog;Dialog.Font.Assign(Font);
  H:=MeasureGuiText('Ag',Font).cy+14;W:=MeasureGuiText('Alpha (fraction)   -1000.000',Font).cx+80;
  Dialog.ClientWidth:=Max(340,W);Y:=12;
  for I:=0 to 3 do begin
   L:=TLabel.Create(Dialog);L.Parent:=Dialog;L.Caption:=Captions[I];L.SetBounds(12,Y+4,Dialog.ClientWidth div 2-20,H);
   Edits[I]:=TEdit.Create(Dialog);Edits[I].Parent:=Dialog;Edits[I].SetBounds(Dialog.ClientWidth div 2,Y,Dialog.ClientWidth div 2-12,H);Inc(Y,H+8);
  end;
  Edits[0].Text:=FloatToStr(FConfig.Elo0);Edits[1].Text:=FloatToStr(FConfig.Elo1);Edits[2].Text:=FloatToStr(FConfig.Alpha);Edits[3].Text:=FloatToStr(FConfig.Beta);
  OK:=TButton.Create(Dialog);OK.Parent:=Dialog;OK.Caption:='Apply';OK.ModalResult:=mrOK;OK.Default:=True;OK.SetBounds(Dialog.ClientWidth-184,Y,80,H);
  Cancel:=TButton.Create(Dialog);Cancel.Parent:=Dialog;Cancel.Caption:='Cancel';Cancel.ModalResult:=mrCancel;Cancel.Cancel:=True;Cancel.SetBounds(Dialog.ClientWidth-96,Y,84,H);
  Dialog.ClientHeight:=Y+H+12;CenterFormOnOwner(Dialog,GetParentForm(Self));
  repeat
   if Dialog.ShowModal<>mrOK then Break;
   try
    C:=FConfig;C.Elo0:=StrToFloat(Edits[0].Text);C.Elo1:=StrToFloat(Edits[1].Text);C.Alpha:=StrToFloat(Edits[2].Text);C.Beta:=StrToFloat(Edits[3].Text);
    ApplyConfig(C);Break;
   except on E:Exception do ShowGuiOkDialog(Dialog,'SPRT settings',E.Message);end;
  until False;
 finally Dialog.Free;end;
end;
procedure TSprtPanel.ShowReport(const R:TSprtReport;Amended:Boolean;const ErrorText:string);
var I:Integer;Mode,StatusText:string;
begin
 FReport:=R;FGraph.Visible:=ErrorText='';
 Mode:='Exploratory';if FConfig.BeforePlay then Mode:='Configured before play';if Amended then Mode:='Amended results';
 FInfoText.Caption:='H0: '+FloatToStr(FConfig.Elo0)+' Elo    H1: '+FloatToStr(FConfig.Elo1)+
  ' Elo    Alpha: '+FloatToStr(FConfig.Alpha*100)+'%    Beta: '+FloatToStr(FConfig.Beta*100)+'%';
 FInfoText.Hint:=FInfoText.Caption+LineEnding+'Paired logistic-Elo GSPRT. Alpha and beta are nominal error targets.';
 if ErrorText<>'' then begin
  FHeadline.Caption:='Comparison unavailable';StatusText:=Mode+'. '+ErrorText;
 end else begin
  FHeadline.Caption:='Continue collecting evidence';
  if R.Decision<>'continue' then FHeadline.Caption:=UpperCase(R.Decision)+' reached at opening '+IntToStr(R.DecisionPair);
  StatusText:=Mode+'. Display only; games continue.'+LineEnding+
    Format('%d of %d pairs included; %d complete.',[R.Included,R.Total,R.Complete]);
  if (R.Decision='continue') and (R.WaitingAt>0) then StatusText+=' Waiting for opening '+IntToStr(R.WaitingAt)+'.'
  else if R.Complete>R.Included then StatusText+=' '+IntToStr(R.Complete-R.Included)+' complete pairs outside the decision sample.';
 end;
 FStatus.Caption:=StatusText;FStatus.Hint:=StatusText;
 FCandidate.ShowHint:=True;FCandidate.Hint:=FCandidate.Text;FBaseline.ShowHint:=True;FBaseline.Hint:=FBaseline.Text;
 for I:=0 to 4 do FCounts.Cells[1,I+1]:=IntToStr(R.Counts[I]);
 FGraph.SetReport(R);RefreshMeasurements;
end;
end.
