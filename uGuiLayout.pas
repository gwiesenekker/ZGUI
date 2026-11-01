unit uGuiLayout;

{$mode objfpc}{$H+}

interface

uses Classes, Controls, ExtCtrls, Forms, StdCtrls;

type
  // Numeric entry widths follow a representative value and the active font.
  // This controls presentation only; existing parsers validate the entered value.
  TGuiNumberEdit = class(TEdit)
  public
    WidthSample:string;
    constructor Create(AOwner:TComponent); override;
  end;

  // A splitter-sized pane has a preferred height separate from its minimum.
  TGuiSplitPanel = class(TPanel);

  // Reuses LCL alignment/child sizing. Only content measurements are refreshed here.
  TGuiLayoutForm = class(TForm)
  private
    FLayoutReady, FMeasuring,FLayoutQueued,FContentDirty: Boolean;
    FBaseMinWidth,FBaseMinHeight:Integer;
    procedure AsyncLayout(Data:PtrInt);
    procedure RequestLayout(ContentChanged:Boolean);
  protected
    procedure RefreshMinimum;
    procedure FontChanged(Sender:TObject); override;
    procedure DoShow; override;
    procedure Resize; override;
    procedure DoAutoAdjustLayout(const AMode:TLayoutAdjustmentPolicy;
      const AXProportion,AYProportion:Double); override;
  public
    destructor Destroy; override;
    procedure EnableAutoLayout;
    procedure InvalidateLayout;
    procedure RefreshLayout; virtual;
  end;

function LayoutRow(AParent:TWinControl;const AControls:array of TControl;
  StretchIndex:Integer=-1):TPanel;
function LayoutFields(AParent:TWinControl;const AControls:array of TControl):TPanel;
function LayoutStack(AParent:TWinControl):TPanel;
function LayoutFlow(AParent:TWinControl;const AControls:array of TControl):TFlowPanel;
procedure LayoutExistingFields(AParent:TPanel);
procedure ScrollLayoutPages(AOwner:TComponent;AControl:TWinControl);

implementation

uses Math, Graphics, ComCtrls, Grids, uGuiDialogs;

constructor TGuiNumberEdit.Create(AOwner:TComponent);
begin inherited Create(AOwner);WidthSample:='999';end;

type
  TGridAccess=class(TCustomGrid);
  TMeasuredPanel = class(TPanel)
  public
    StretchCells:TList;
    constructor Create(AOwner:TComponent); override;
    destructor Destroy; override;
    procedure Resize; override;
  end;

constructor TMeasuredPanel.Create(AOwner:TComponent);
begin inherited Create(AOwner);StretchCells:=TList.Create;end;
destructor TMeasuredPanel.Destroy;
begin StretchCells.Free;inherited Destroy;end;

type TMeasuredFlowPanel=class(TFlowPanel)
  protected procedure Resize; override;
end;

procedure TMeasuredPanel.Resize;
var F:TCustomForm;
begin
  inherited Resize;F:=GetParentForm(Self);
  if F is TGuiLayoutForm then TGuiLayoutForm(F).RequestLayout(False);
end;
procedure TMeasuredFlowPanel.Resize;
var F:TCustomForm;
begin
  inherited Resize;F:=GetParentForm(Self);
  if F is TGuiLayoutForm then TGuiLayoutForm(F).RequestLayout(False);
end;

function Gap(C:TControl):Integer;
begin Result:=Max(4,MeasureGuiText('M',C.Font).cx div 2);end;

function LayoutStack(AParent:TWinControl):TPanel;
begin
  Result:=TMeasuredPanel.Create(AParent.Owner);Result.Parent:=AParent;
  Result.BevelOuter:=bvNone;Result.Align:=alTop;Result.AutoSize:=True;
end;

procedure PrepareCell(C:TControl;Stretch:Boolean);
begin
  C.Align:=alNone;C.Anchors:=[akLeft,akTop];
  if Stretch then TMeasuredPanel(C.Parent).StretchCells.Add(C);
  C.BorderSpacing.CellAlignHorizontal:=ccaLeftTop;
  if Stretch then C.BorderSpacing.CellAlignHorizontal:=ccaFill;
  C.BorderSpacing.CellAlignVertical:=ccaCenter;
  if C is TLabel then TLabel(C).AutoSize:=True;
  if C is TButton then TButton(C).AutoSize:=True;
end;

function LayoutRow(AParent:TWinControl;const AControls:array of TControl;
  StretchIndex:Integer):TPanel;
var I:Integer;
begin
  Result:=LayoutStack(AParent);
  // Explicit order: keep controls owned by their original forms, including events.
  for I:=0 to High(AControls) do begin
    AControls[I].Parent:=Result;PrepareCell(AControls[I],I=StretchIndex);
  end;
  Result.ChildSizing.EnlargeHorizontal:=crsHomogenousChildResize;
  Result.ChildSizing.ShrinkHorizontal:=crsHomogenousChildResize;
  Result.ChildSizing.Layout:=cclLeftToRightThenTopToBottom;
  Result.ChildSizing.ControlsPerLine:=Length(AControls);
  Result.ChildSizing.HorizontalSpacing:=Gap(Result);
  Result.ChildSizing.VerticalSpacing:=Gap(Result);
  Result.BorderSpacing.Bottom:=Gap(Result);
end;

function LayoutFields(AParent:TWinControl;const AControls:array of TControl):TPanel;
var I:Integer;
begin
  Result:=LayoutRow(AParent,AControls,-1);
  Result.ChildSizing.ControlsPerLine:=2;
  for I:=0 to High(AControls) do PrepareCell(AControls[I],Odd(I));
end;

function LayoutFlow(AParent:TWinControl;const AControls:array of TControl):TFlowPanel;
var I:Integer;
begin
  Result:=TMeasuredFlowPanel.Create(AParent.Owner);Result.Parent:=AParent;
  Result.BevelOuter:=bvNone;Result.Align:=alTop;Result.AutoSize:=True;Result.AutoWrap:=True;
  for I:=0 to High(AControls) do begin
    AControls[I].Parent:=Result;AControls[I].Align:=alNone;
    AControls[I].Anchors:=[akTop,akLeft];AControls[I].BorderSpacing.Around:=Gap(Result);
    if AControls[I] is TButton then TButton(AControls[I]).AutoSize:=True;
  end;
end;

procedure LayoutExistingFields(AParent:TPanel);
var Children:array of TControl;I:Integer;
begin
  SetLength(Children,AParent.ControlCount);
  for I:=0 to High(Children) do Children[I]:=AParent.Controls[I];
  LayoutFields(AParent,Children);AParent.AutoSize:=True;
end;

procedure ScrollLayoutPages(AOwner:TComponent;AControl:TWinControl);
var I,J:Integer;Page:TTabSheet;Scroll:TScrollBox;
begin
  if AControl is TPageControl then begin
    for I:=0 to TPageControl(AControl).PageCount-1 do begin
      Page:=TPageControl(AControl).Pages[I];Scroll:=TScrollBox.Create(AOwner);
      // Reparent before attaching the scroll box to avoid capturing itself.
      for J:=Page.ControlCount-1 downto 0 do Page.Controls[J].Parent:=Scroll;
      Scroll.Parent:=Page;Scroll.Align:=alClient;Scroll.BorderStyle:=bsNone;
      Scroll.HorzScrollBar.Tracking:=True;Scroll.VertScrollBar.Tracking:=True;
    end;
  end else for I:=AControl.ControlCount-1 downto 0 do
    if AControl.Controls[I] is TWinControl then ScrollLayoutPages(AOwner,TWinControl(AControl.Controls[I]));
end;

procedure MeasureControls(C:TWinControl);
var I,J,W,H,TextHeight,Cols,Required,Buttons,ButtonHeight,Rows:Integer;Child:TControl;ColumnWidths,RowHeights:array of Integer;
begin
  Buttons:=0;ButtonHeight:=0;
  for I:=0 to C.ControlCount-1 do begin
    Child:=C.Controls[I];
    TextHeight:=MeasureGuiText('Ag',Child.Font).cy;
    if Child is TButton then begin
      Inc(Buttons);
      TButton(Child).AutoSize:=True;
      Child.Constraints.MinWidth:=MeasureGuiText(TButton(Child).Caption,Child.Font).cx+4*Gap(Child);
      Child.Constraints.MinHeight:=TextHeight+2*Gap(Child);
      ButtonHeight:=Max(ButtonHeight,Max(Child.Height,Child.Constraints.MinHeight));
      if Child.Align=alNone then Child.Top:=Gap(Child);
    end;
    if (Child is TLabel) and not TLabel(Child).WordWrap then begin
      if C is TMeasuredPanel then Child.Constraints.MinWidth:=MeasureGuiText(TLabel(Child).Caption,Child.Font).cx;
      if Child.Align in [alTop,alBottom] then Child.Constraints.MinHeight:=TextHeight+Gap(Child);
    end;
    if Child is TCheckBox then TCheckBox(Child).AutoSize:=True;
    if (Child is TEdit) or (Child is TComboBox) then begin
      W:=0;H:=0;Child.GetPreferredSize(W,H,True);
      Child.Constraints.MinHeight:=Max(H,TextHeight+Gap(Child));
      if Child.Parent is TMeasuredPanel then Child.Constraints.MinWidth:=MeasureGuiText('MMMMMMMM',Child.Font).cx;
      if Child is TComboBox then begin
        W:=0;
        for J:=0 to TComboBox(Child).Items.Count-1 do
          W:=Max(W,MeasureGuiText(TComboBox(Child).Items[J],Child.Font).cx);
        Child.Constraints.MinWidth:=Max(Child.Constraints.MinWidth,W+TextHeight+2*Gap(Child));
      end;
    end;
    if Child is TMemo then Child.Constraints.MinHeight:=2*TextHeight+2*Gap(Child);
    if Child is TCustomGrid then begin
      Child.Constraints.MinHeight:=2*(TextHeight+2*Gap(Child));
      TGridAccess(Child).DefaultRowHeight:=TextHeight+2*Gap(Child);
    end;
    if Child is TMeasuredPanel then begin
      with TMeasuredPanel(Child).ChildSizing do begin
        HorizontalSpacing:=Gap(Child);VerticalSpacing:=Gap(Child);
      end;
      Child.BorderSpacing.Bottom:=Gap(Child);
    end;
    if Child is TWinControl then MeasureControls(TWinControl(Child));
    if C is TMeasuredPanel then begin
      Child.Anchors:=[akLeft,akTop];
      Child.BorderSpacing.CellAlignHorizontal:=ccaFill;
      if TMeasuredPanel(C).StretchCells.IndexOf(Child)<0 then begin
        W:=0;H:=0;Child.GetPreferredSize(W,H,True);
        if Child is TLabel then W:=MeasureGuiText(TLabel(Child).Caption,Child.Font).cx;
        if Child is TComboBox then W:=Child.Constraints.MinWidth;
        if Child is TButton then W:=MeasureGuiText(TButton(Child).Caption,Child.Font).cx+4*Gap(Child);
        // Leave breathing room after native checkbox captions across themes.
        if Child is TCheckBox then Inc(W,Gap(Child));
        Child.Constraints.MinWidth:=W;
        Child.Constraints.MaxWidth:=Child.Constraints.MinWidth;
      end else Child.Constraints.MaxWidth:=0;
    end;
    if Child is TGuiNumberEdit then begin
      W:=MeasureGuiText(TGuiNumberEdit(Child).WidthSample,Child.Font).cx+2*Gap(Child);
      Child.Constraints.MaxWidth:=0;
      Child.Constraints.MinWidth:=W;
      Child.Constraints.MaxWidth:=W;
    end;
  end;
  if C is TMeasuredPanel then begin
    Cols:=Max(1,C.ChildSizing.ControlsPerLine);SetLength(ColumnWidths,Cols);
    Rows:=(C.ControlCount+Cols-1) div Cols;SetLength(RowHeights,Rows);
    for I:=0 to C.ControlCount-1 do begin
      Child:=C.Controls[I];W:=Child.Constraints.MinWidth;
      if W=0 then begin H:=0;Child.GetPreferredSize(W,H,True);end;
      J:=I mod Cols;ColumnWidths[J]:=Max(ColumnWidths[J],W);
      H:=0;W:=0;Child.GetPreferredSize(W,H,True);
      H:=Max(H,Child.Constraints.MinHeight);
      Inc(H,Child.BorderSpacing.Top+Child.BorderSpacing.Bottom+2*Child.BorderSpacing.Around);
      J:=I div Cols;RowHeights[J]:=Max(RowHeights[J],H);
    end;
    Required:=Max(0,Cols-1)*Gap(C);
    for J:=0 to High(ColumnWidths) do Inc(Required,ColumnWidths[J]);
    for I:=0 to C.ControlCount-1 do
      if TMeasuredPanel(C).StretchCells.IndexOf(C.Controls[I])<0 then
        C.Controls[I].Constraints.MaxWidth:=ColumnWidths[I mod Cols];
    C.Constraints.MinWidth:=Required;
    Required:=0;
    for J:=0 to High(RowHeights) do Inc(Required,RowHeights[J]);
    if C.ChildSizing.ControlsPerLine>0 then Inc(Required,Max(0,Rows-1)*Gap(C));
    C.Constraints.MinHeight:=Required;
  end;
  if (Buttons>0) and (Buttons=C.ControlCount) and (C is TPanel) then begin
    C.Constraints.MinHeight:=ButtonHeight+2*Gap(C);
    C.Height:=C.Constraints.MinHeight;
  end;
end;

type TLayoutMinimum=class(TComponent)
  public Width,Height:Integer;
end;

function OriginalMinimum(C:TWinControl):TLayoutMinimum;
begin
  Result:=TLayoutMinimum(C.FindComponent('GuiLayoutMinimum'));
  if Result<>nil then Exit;
  Result:=TLayoutMinimum.Create(C);Result.Name:='GuiLayoutMinimum';
  Result.Width:=C.Constraints.MinWidth;Result.Height:=C.Constraints.MinHeight;
end;

function MinimumWidth(C:TWinControl):Integer;
var I,Side,Middle,W:Integer;Child:TControl;
begin
  Result:=C.Constraints.MinWidth;
  if (C is TPanel) and not (C is TMeasuredPanel) then Result:=OriginalMinimum(C).Width;
  if C is TForm then Result:=0;
  if (C is TScrollBox) or (C is TMeasuredPanel) then Exit;
  Side:=0;Middle:=0;
  for I:=0 to C.ControlCount-1 do begin
    Child:=C.Controls[I];W:=Child.Constraints.MinWidth;
    if Child is TWinControl then W:=MinimumWidth(TWinControl(Child));
    if Child.Align in [alLeft,alRight] then Inc(Side,W+Child.BorderSpacing.Left+Child.BorderSpacing.Right+2*Child.BorderSpacing.Around)
    else Middle:=Max(Middle,W+Child.BorderSpacing.Left+Child.BorderSpacing.Right+2*Child.BorderSpacing.Around);
  end;
  Result:=Max(Result,Side+Middle);
  if (C.Align in [alLeft,alRight]) and not (C is TForm) then C.Constraints.MinWidth:=Result;
end;

function MinimumHeight(C:TWinControl):Integer;
var I,Edge,Middle,H:Integer;Child:TControl;
begin
  Result:=C.Constraints.MinHeight;
  if (C is TPanel) and not (C is TMeasuredPanel) then Result:=OriginalMinimum(C).Height;
  if C is TForm then Result:=0;
  if C is TScrollBox then Exit;
  if (C is TMeasuredPanel) or (C is TFlowPanel) then Exit(Max(Result,C.Height));
  Edge:=0;Middle:=0;
  for I:=0 to C.ControlCount-1 do begin
    Child:=C.Controls[I];if not Child.Visible then Continue;
    H:=Child.Constraints.MinHeight;
    if Child is TWinControl then H:=MinimumHeight(TWinControl(Child));
    if Child.Align in [alTop,alBottom] then begin
      if not (Child is TGuiSplitPanel) then H:=Max(H,Child.Height);
      Inc(Edge,H+Child.BorderSpacing.Top+Child.BorderSpacing.Bottom+2*Child.BorderSpacing.Around);
    end
    else Middle:=Max(Middle,H+Child.BorderSpacing.Top+Child.BorderSpacing.Bottom+2*Child.BorderSpacing.Around);
  end;
  Result:=Max(Result,Edge+Middle);
  if (C.Align in [alTop,alBottom]) and not (C is TForm) then C.Constraints.MinHeight:=Result;
end;

procedure TGuiLayoutForm.RefreshMinimum;
begin
  Constraints.MinWidth:=Max(FBaseMinWidth,MinimumWidth(Self)+Width-ClientWidth);
  Constraints.MinHeight:=Max(FBaseMinHeight,MinimumHeight(Self)+Height-ClientHeight);
  // A new constraint alone does not grow an already shown GTK/Windows form.
  // Wrapping can increase the minimum after a user narrows the window.
  if Width<Constraints.MinWidth then Width:=Constraints.MinWidth;
  if Height<Constraints.MinHeight then Height:=Constraints.MinHeight;
end;

procedure TGuiLayoutForm.RefreshLayout;
begin
  if not FLayoutReady or FMeasuring or (csDestroying in ComponentState) then Exit;
  FMeasuring:=True;
  try
    MeasureControls(Self);
    RefreshMinimum;
  finally FMeasuring:=False;end;
end;

procedure TGuiLayoutForm.RequestLayout(ContentChanged:Boolean);
begin
  if not FLayoutReady or (csDestroying in ComponentState) then Exit;
  FContentDirty:=FContentDirty or ContentChanged;
  if FLayoutQueued then Exit;
  FLayoutQueued:=True;Application.QueueAsyncCall(@AsyncLayout,0);
end;

procedure TGuiLayoutForm.AsyncLayout(Data:PtrInt);
begin
  FLayoutQueued:=False;
  if not FLayoutReady or (csDestroying in ComponentState) then Exit;
  if FContentDirty then begin FContentDirty:=False;RefreshLayout;end
  else begin FMeasuring:=True;try RefreshMinimum;finally FMeasuring:=False;end;end;
end;

destructor TGuiLayoutForm.Destroy;
begin
  FLayoutReady:=False;Application.RemoveAsyncCalls(Self);inherited Destroy;
end;

procedure TGuiLayoutForm.InvalidateLayout;
begin RequestLayout(True);end;

procedure TGuiLayoutForm.DoAutoAdjustLayout(const AMode:TLayoutAdjustmentPolicy;
  const AXProportion,AYProportion:Double);
begin
  inherited DoAutoAdjustLayout(AMode,AXProportion,AYProportion);
  if FLayoutReady then begin
    FBaseMinWidth:=Round(FBaseMinWidth*AXProportion);
    FBaseMinHeight:=Round(FBaseMinHeight*AYProportion);
  end;
  // Update constraints before LCL resumes alignment of the scaled children.
  RefreshLayout;
  RequestLayout(True);
end;

procedure TGuiLayoutForm.EnableAutoLayout;
begin
  FBaseMinWidth:=Constraints.MinWidth;FBaseMinHeight:=Constraints.MinHeight;
  FLayoutReady:=True;RequestLayout(True);
end;

procedure TGuiLayoutForm.FontChanged(Sender:TObject);
begin inherited FontChanged(Sender);RequestLayout(True);end;
procedure TGuiLayoutForm.Resize;
begin inherited Resize;RequestLayout(False);end;
procedure TGuiLayoutForm.DoShow;
begin inherited DoShow;RequestLayout(True);end;

end.
