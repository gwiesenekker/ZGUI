program chess_board_check;
{$mode objfpc}{$H+}
{$IFNDEF GWDGUI_NONINTERACTIVE_TEST}{$FATAL Build with the LPI project}{$ENDIF}
uses {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Forms, Classes, SysUtils, Types,
  Controls, Graphics, Math, StdCtrls, Menus, LCLType, Clipbrd, uGamePosition,
  uChessPosition, uDraughtsPosition, uGameBoardControl, uChessBoardControl,
  uPvBrowser, uDraughtsHubEngine, uMainForm, uGameTree, uGameTreeActor, uGameTreeBuilder,
  uGameNotationView, uGuiDialogs, uGameGuiProfile, uPdnOpenDialog, Grids, uChessPgn, uGameFileReader, uScoreHistoryControl, uPreferences;
type
  TPaintScore = class(TScoreHistoryControl)
    procedure Render(B: TBitmap);
  end;
  TPaintChess = class(TChessBoardControl)
    procedure Render(B: TBitmap);
  end;
  TChoice = class
    Dialog: TForm;
    Main: TMainForm;
    Index: Integer;
    Stale: Boolean;
    procedure Shown(Sender: TObject);
    procedure Pick(Data: PtrInt);
  end;
  TConfirmation = class
    Dialog: TForm;
    ExpectedDefault: string;
    ExpectCancelFocus,ClickAccept: Boolean;
    ShownCount: Integer;
    procedure Shown(Sender: TObject);
    procedure Respond(Data: PtrInt);
  end;
  TErrors = class
    procedure Report(Sender: TObject; E: Exception);
  end;
var Checks: Integer=0; Variant: TChessVariant;
procedure TPaintScore.Render(B:TBitmap);
begin
  HandleNeeded;PaintWindow(B.Canvas.Handle);
  B.Canvas.Pixels[0,0]:=B.Canvas.Pixels[0,0];
end;

procedure CheckMateHistory;
var Host:TForm;S:TPaintScore;MateImage,NumericImage:TBitmap;
    Mode,ScaleIndex,LimitIndex:Integer;MateBytes,NumericBytes:TMemoryStream;
begin
  Host:=TForm.CreateNew(nil);S:=TPaintScore.Create(Host);S.Parent:=Host;
  MateImage:=TBitmap.Create;NumericImage:=TBitmap.Create;
  MateBytes:=TMemoryStream.Create;NumericBytes:=TMemoryStream.Create;
  try
    S.SetBounds(0,0,400,160);S.ShowEvaluationBar:=False;S.PlyCount:=2;S.CurrentPly:=0;
    MateImage.SetSize(S.Width,S.Height);NumericImage.SetSize(S.Width,S.Height);
    for LimitIndex:=0 to 1 do begin
      if LimitIndex=0 then S.MaxScore:=10 else S.MaxScore:=3;
      for Mode:=0 to 1 do for ScaleIndex:=0 to 1 do begin
        if Mode=0 then S.DisplayMode:=shdmGraph else S.DisplayMode:=shdmBars;
        S.Scale:=TScoreScale(ScaleIndex);
        S.AnnotationsText:='engine=#5; annotator=#-4'+LineEnding+'engine=#-2; annotator=#3';
        S.Render(MateImage);
        S.AnnotationsText:='engine='+IntToStr(Round(S.MaxScore))+'; annotator=-'+IntToStr(Round(S.MaxScore))+LineEnding+
          'engine=-'+IntToStr(Round(S.MaxScore))+'; annotator='+IntToStr(Round(S.MaxScore));
        S.Render(NumericImage);MateBytes.Clear;NumericBytes.Clear;
        MateImage.SaveToStream(MateBytes);NumericImage.SaveToStream(NumericBytes);
        if (MateBytes.Size<>NumericBytes.Size) or
          not CompareMem(MateBytes.Memory,NumericBytes.Memory,MateBytes.Size) then
          raise Exception.Create('Mate history does not render at the configured endpoints');
        Inc(Checks);
      end;
    end;
  finally MateBytes.Free;NumericBytes.Free;MateImage.Free;NumericImage.Free;Host.Free;end;
end;

procedure TErrors.Report(Sender: TObject; E: Exception);
begin WriteLn('FAIL: ',E.Message); DumpExceptionBackTrace(Output); Halt(1); end;
procedure Check(Value: Boolean; const Text: string);
begin Inc(Checks); if not Value then raise Exception.Create(Text); end;
procedure TConfirmation.Shown(Sender: TObject);
var I,Buttons: Integer;
begin
  Dialog:=TForm(Sender); Inc(ShownCount);
  Check(Dialog.DefaultControl is TButton,'Confirmation has a real default button');
  Check(TButton(Dialog.DefaultControl).Caption=ExpectedDefault,'Expected default '+ExpectedDefault);
  if ExpectCancelFocus then
  begin
    Check(Dialog.DefaultControl=Dialog.CancelControl,'Discard defaults to its cancel action');
    Check(Dialog.ActiveControl=Dialog.CancelControl,'Discard starts with Cancel focused');
    Buttons:=0;
    for I:=0 to Dialog.ComponentCount-1 do
      if Dialog.Components[I] is TButton then Inc(Buttons);
    Check(Buttons=2,'Discard dialog has exactly Discard and Cancel buttons');
  end;
  Application.QueueAsyncCall(@Respond,0);
end;
procedure TConfirmation.Respond(Data: PtrInt);
var I: Integer;
begin
  if ClickAccept then
  begin
    for I:=0 to Dialog.ComponentCount-1 do
      if (Dialog.Components[I] is TButton) and (TButton(Dialog.Components[I]).Caption='Discard') then
      begin TButton(Dialog.Components[I]).Click; Exit; end;
    raise Exception.Create('Missing explicit Discard button');
  end
  else TButton(Dialog.DefaultControl).Click;
end;

procedure TPaintChess.Render(B: TBitmap);
begin
  HandleNeeded;
  PaintWindow(B.Canvas.Handle);
  // Native painting bypasses TBitmap's change notification. Invalidate its
  // cached raw image before saving/assigning the pixels to a PNG.
  B.Canvas.Pixels[0,0] := B.Canvas.Pixels[0,0];
end;
function PointFor(Board: TGameBoardControl; Square: Integer): TPoint;
var X,Y,Step: Integer;
begin
  Step:=Max(1,Board.BoardSquareSize div 2); Y:=0;
  while Y<Board.ClientHeight do
  begin
    X:=0;
    while X<Board.ClientWidth do
    begin
      if Board.SquareAtPoint(X,Y)=Square then Exit(Point(X,Y));
      Inc(X,Step);
    end;
    Inc(Y,Step);
  end;
  raise Exception.Create('Square not found '+IntToStr(Square));
end;
procedure Click(Board: TGameBoardControl; Square: Integer);
var P: TPoint;
begin P:=PointFor(Board,Square); Board.OnMouseDown(Board,mbLeft,[],P.X,P.Y); end;
function Menu(Main: TMainForm; const Caption: string): TMenuItem;
var I: Integer;
begin
  for I:=0 to Main.ComponentCount-1 do
    if (Main.Components[I] is TMenuItem) and (TMenuItem(Main.Components[I]).Caption=Caption) then
      Exit(TMenuItem(Main.Components[I]));
  raise Exception.Create('Missing menu '+Caption);
end;
procedure TChoice.Shown(Sender: TObject);
var List: TListBox;
begin
  Dialog:=TForm(Sender); List:=TListBox(Dialog.FindComponent('Choices'));
  Check(Dialog.Caption='Choose move','Neutral chooser caption');
  Check(List.Items.Count=4,'Four promotion choices in existing chooser');
  Check(List.Items[0]='a8=Q+','SAN promotion captions');
  Application.QueueAsyncCall(@Pick,0);
end;
procedure TChoice.Pick(Data: PtrInt);
begin
  if Stale then Main.LoadStandaloneFen(ChessStartingFEN);
  if Index<0 then TButton(Dialog.FindComponent('CancelButton')).Click
  else
  begin
    TListBox(Dialog.FindComponent('Choices')).ItemIndex:=Index;
    TButton(Dialog.FindComponent('ChooseButton')).Click;
  end;
end;
procedure CheckView;
var F: TForm; B: TPaintChess; P: TChessPosition; I,S,Mode: Integer;
    Points: array[1..64] of TPoint; Image: TBitmap; PNG: TPortableNetworkGraphic;
    Original: string; Bad: TDraughtsPosition;
begin
  F:=TForm.CreateNew(nil); B:=TPaintChess.Create(F); P:=TChessPosition.Create;
  Image:=TBitmap.Create; PNG:=TPortableNetworkGraphic.Create; Bad:=TDraughtsPosition.Create;
  try
    B.Parent:=F;
    B.SetPosition(P); Original:=B.Position.ToFEN;
    P.PlayMove('e2e4'); Check(B.Position.ToFEN=Original,'View owns copy, source mutation isolated');
    P.Free; P:=nil; Check(B.Position.ToFEN=Original,'View survives source release');
    try B.SetPosition(Bad); Check(False,'Wrong view type must reject'); except on E:EGamePositionError do ; end;
    Check(B.Position.ToFEN=Original,'Rejected view input keeps old snapshot');
    for Mode:=0 to 2 do
    begin
      B.SetBounds(0,0,450+Mode*73,440+Mode*51);
      B.ShowSideToMoveMarker:=Mode<>0; B.BoardFlipped:=False;
      for S:=1 to 64 do begin Points[S]:=PointFor(B,S); Check(B.SquareAtPoint(Points[S].X,Points[S].Y)=S,'64 squares'); end;
      B.BoardFlipped:=True;
      for S:=1 to 64 do Check(B.SquareAtPoint(Points[S].X,Points[S].Y)=65-S,'Flip reverses mapping');
      Check(B.SquareAtPoint(-1,10)=0,'Outside left');
      Check(B.SquareAtPoint(B.Width,10)=0,'Outside right');
      Check(B.SquareAtPoint(10,B.Height)=0,'Outside bottom');
      Check(B.Position.ToFEN=Original,'Geometry does not change position');
    end;
    B.SetBounds(0,0,560,560); B.BoardFlipped:=False; B.ShowSideToMoveMarker:=True;
    B.HintSourceSquare:=13; B.HintTargetSquare:=29; B.PvSourceSquare:=7; B.PvTargetSquare:=22;
    B.LastMoveTargetSquare:=29; B.SetTargetSquares([21,29]);
    Image.SetSize(560,560); B.Render(Image); PNG.Assign(Image);
    if ParamStr(1)<>'' then PNG.SaveToFile(ParamStr(1));
    B.SetPosition(nil); Check(B.Position=nil,'Clear releases view snapshot'); B.Render(Image);
    // Render all piece kinds at mini-board size as well.
    P:=TChessPosition.Create;
    P.LoadFromFEN('4k3/8/8/8/8/8/8/RNBQKBNR w - - 0 1'); B.SetPosition(P);
    for I:=64 to 160 do if I mod 16=0 then begin B.SetBounds(0,0,I,I); B.Render(Image); end;
  finally Bad.Free; PNG.Free; Image.Free; P.Free; F.Free; end;
end;
procedure CheckCoordinateContrast;
var F: TForm; Board: TPaintChess; Image: TBitmap; Theme,Flip,Row,Col: Integer;
    Expected: TColor;
  function HasInk(ARow,ACol: Integer; Colour: TColor): Boolean;
  var X,Y,Brightness: Integer; Pixel: TColor;
  begin
    for Y:=ARow*50+1 to (ARow+1)*50-2 do
      for X:=ACol*50+1 to (ACol+1)*50-2 do
      begin
        Pixel:=ColorToRGB(Image.Canvas.Pixels[X,Y]);
        Brightness:=299*Red(Pixel)+587*Green(Pixel)+114*Blue(Pixel);
        // Antialiased small glyphs need not contain a pure foreground pixel.
        if ((Colour=clBlack) and (Brightness<128000)) or
          ((Colour=clWhite) and (Brightness>128000)) then Exit(True);
      end;
    Result:=False;
  end;
begin
  F:=TForm.CreateNew(nil); Board:=TPaintChess.Create(F); Board.Parent:=F;
  Image:=TBitmap.Create;
  try
    Board.SetBounds(0,0,400,400); Image.SetSize(400,400);
    // With no pieces/highlights, contrasting ink comes from the cell label.
    for Theme:=0 to 2 do
    begin
      case Theme of
        0: begin Board.BoardLightColor:=RGBToColor(228,207,176); Board.BoardDarkColor:=RGBToColor(98,73,53); end;
        1: begin Board.BoardLightColor:=RGBToColor(250,250,250); Board.BoardDarkColor:=RGBToColor(220,220,220); end;
        2: begin Board.BoardLightColor:=RGBToColor(30,30,30); Board.BoardDarkColor:=RGBToColor(60,60,60); end;
      end;
      for Flip:=0 to 1 do
      begin
        Board.BoardFlipped:=Flip=1; Board.Render(Image);
        for Row:=0 to 7 do
          for Col:=0 to 7 do
            if (Col=0) or (Row=7) then
            begin
              if Theme=1 then Expected:=clBlack
              else if Theme=2 then Expected:=clWhite
              else if (Row+Col) mod 2=0 then Expected:=clBlack else Expected:=clWhite;
              Check(HasInk(Row,Col,Expected),Format('Coordinate contrast theme %d flip %d row %d col %d',[Theme,Flip,Row,Col]));
            end;
      end;
    end;
  finally Image.Free; F.Free; end;
end;

procedure CheckPV;
var F: TForm; Board: TChessBoardControl; Memo: TMemo; Info: TLabel;
    Browser: TPvBrowser; P,Q: TChessPosition; Bad: TDraughtsPosition; Key: Word;

  procedure Show(const FEN,PV: string);
  begin
    Browser.Clear; P.LoadFromFEN(FEN); Browser.SetData(P,0,FEN,PV,'0.2','20','1');
  end;
  procedure Expected(const FEN: string; const Moves: array of string);
  var M: string;
  begin
    Q.LoadFromFEN(FEN); for M in Moves do Q.PlayMoveText(M);
    Check(Browser.Position.ToFEN=Q.ToFEN,'PV replays expected legal prefix');
    Check(Board.Position.ToFEN=Q.ToFEN,'PV control snapshot matches browser');
  end;
begin
  F:=TForm.CreateNew(nil); Board:=TChessBoardControl.Create(F); Board.Parent:=F;
  Memo:=TMemo.Create(F); Memo.Parent:=F; Memo.Enabled:=False; Info:=TLabel.Create(F);
  Browser:=TPvBrowser.Create(Variant,Board,Info,Memo); P:=TChessPosition.Create;
  Q:=TChessPosition.Create; Bad:=TDraughtsPosition.Create;
  try
    Show(ChessStartingFEN,'e2e4 e7e5 e1e8');
    Expected(ChessStartingFEN,['e4','e5']);
    Check(Pos('1.e4 e5',Memo.Text)>0,'PV uses SAN');
    Check(Pos('Invalid PV move 3: e1e8',Memo.Text)>0,'Invalid tail stays raw');
    Memo.SelStart:=Pos('e4',Memo.Text)-1; Memo.OnClick(Memo);
    Check(Memo.SelText='1.e4','Click offsets use displayed SAN');
    Q.LoadFromFEN(ChessStartingFEN); Q.PlayMove('e2e4');
    Check(Browser.Position.ToFEN=Q.ToFEN,'PV click replays one ply');
    P.LoadFromFEN(ChessStartingFEN); Browser.SetData(P,0,ChessStartingFEN,'d2d4','0.4','21','2');
    Check(Pos('newer PV pending',Info.Caption)>0,'PV frozen while browsing');
    Check(Browser.Position.ToFEN=Q.ToFEN,'Pending snapshot does not replace browsing');
    P.PlayMove('g1f3'); // pending base is an owned copy
    Key:=VK_ESCAPE; Memo.OnKeyDown(Memo,Key,[]);
    Expected(ChessStartingFEN,['d4']);
    Show('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1','e1g1 e8c8');
    Expected(P.ToFEN,['O-O','O-O-O']); Check(Pos('O-O-O',Memo.Text)>0,'PV castles in SAN');
    Show('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2','e5d6');
    Expected(P.ToFEN,['exd6']); Check(Pos('exd6',Memo.Text)>0,'PV en passant SAN');
    Show('4k3/8/8/8/8/8/4p3/K7 b - - 0 37','e2e1q');
    Expected(P.ToFEN,['e1=Q+']); Check(Pos('37...e1=Q+',Memo.Text)>0,'Black move 37 and promotion SAN');
    Show('B3k3/8/8/8/8/8/8/4K3 w - - 0 37','a8b7');
    Check(Pos('37.Bb7',Memo.Text)>0,'Bishop on a8 is not FEN side-to-move');
    Browser.SetData(Bad,0,'W:W31-50:B1-20','32-28','','','');
    Check((Browser.Position=nil) and (Board.Position=nil) and (Memo.Text='No PV'),'Wrong-game base clears stale PV');
    Show(ChessStartingFEN,'e2e4');
    Browser.SetData(P,0,'not a FEN','d2d4','','','');
    Check(Browser.Position=nil,'Wrong-game header clears PV');
  finally Browser.Free; Bad.Free; Q.Free; P.Free; F.Free; end;
end;
procedure CheckLayout;
var Draughts,Chess: TMainForm; Bounds: array of TRect; I,Count: Integer;
begin
  RegisterDefaultGameVariant(DraughtsVariant);
  Draughts:=TMainForm.Create(nil);
  try
    Count:=Draughts.ComponentCount; SetLength(Bounds,Count);
    for I:=0 to Count-1 do
      if Draughts.Components[I] is TControl then Bounds[I]:=TControl(Draughts.Components[I]).BoundsRect;
  finally Draughts.Free; RegisterDefaultGameVariant(Variant); end;
  Chess:=TMainForm.Create(nil);
  try
    Check(Chess.ComponentCount=Count,'Same component layout for both games');
    for I:=0 to Count-1 do
      if Chess.Components[I] is TControl then
        Check(EqualRect(Bounds[I],TControl(Chess.Components[I]).BoundsRect),
          'Existing control bounds preserved at component '+IntToStr(I));
  finally Chess.Free; end;
end;

procedure CheckMain;
var Main: TMainForm; B: TGameBoardControl; Legal: TMemo; Memo: TGameNotationView;
    Expected: TChessPosition; Choice: TChoice; Scenario,I: Integer; NodeId: Int64;
    Key: Word; Before: string; Actor: TGameTreeActor; C: TGameTreeCommand;
    Score: TScoreHistoryControl; Value: Double;
const Promotions: array[0..3] of string=('a7a8q','a7a8r','a7a8b','a7a8n');
  Unsupported: array[0..0] of string = ('Open MCTS annotator');
begin
  Main:=TMainForm.Create(nil); Expected:=TChessPosition.Create; Choice:=TChoice.Create;
  Actor:=nil;
  try
    Main.Show; Application.ProcessMessages;
    B:=TGameBoardControl(Main.FindComponent('MainBoard'));
    Memo:=TGameNotationView(Main.FindComponent('GameMoveMemo')); Memo.Enabled:=False;
    Legal:=TMemo(Main.FindComponent('LegalMovesMemo'));
    Check((B is TChessBoardControl) and (Main.Caption='ZGUI - Chess'),'Chess composed in existing main form');
    Check(Legal.Lines.Count=20,'Existing legal list shows 20 initial chess moves');
    Check(B.Position.ToFEN=ChessStartingFEN,'Initial board');
    Before:=B.Position.ToFEN; Click(B,13);
    Check((Main.ActiveGameTree.MainlineCount=0) and (B.Position.ToFEN=Before),'Source click only selects');
    Click(B,29); Expected.PlayMove('e2e4');
    Check((Main.ActiveGameTree.MainlineNode[1].MoveText='e2e4') and (B.Position.ToFEN=Expected.ToFEN),'Board click goes through existing actor');
    Legal.CaretPos:=Point(0,Legal.Lines.IndexOf('e7e5')); Legal.OnClick(Legal);
    Expected.PlayMove('e7e5'); Check(B.Position.ToFEN=Expected.ToFEN,'Existing legal list plays chess move');
    NodeId:=Main.ActiveGameTree.MainlineNode[2].NodeId;
    Key:=Ord('F'); Main.OnKeyDown(Main,Key,[]);
    Check((B.Position.ToFEN=Expected.ToFEN) and (Main.ActiveGameTree.MainlineNode[2].NodeId=NodeId),'Flip preserves tree identity');
    Key:=Ord('F'); Main.OnKeyDown(Main,Key,[]);
    Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]); // Freeze at current tip first.
    Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]);
    Expected.LoadFromFEN(ChessStartingFEN); Expected.PlayMove('e2e4');
    Check(B.Position.ToFEN=Expected.ToFEN,'Existing notation navigation replays chess');
    Check(Main.ActiveGameTree.MainlineNode[2].NodeId=NodeId,'Navigation keeps continuation');
    Click(B,51); Click(B,35); // c7-c5 as a variation after e4
    Check(Main.ActiveGameTree.BranchCount=1,'Existing move router creates variation');
    Check(Main.ActiveGameTree.MainlineNode[2].NodeId=NodeId,'Variation does not replace mainline');
    Expected.PlayMove('c7c5'); Check(B.Position.ToFEN=Expected.ToFEN,'Variation board');
    Click(B,7); Click(B,22); Expected.PlayMove('g1f3');
    Check(B.Position.ToFEN=Expected.ToFEN,'Nested branch replay');
    // Existing score view consumes neutral score annotations on chess trees.
    Main.LoadStandaloneFen(ChessStartingFEN); Click(B,13); Click(B,29);
    Actor:=TGameTreeActor.Create(Main.ActiveGameTree,False);
    C:=Actor.CreateRecordEnginePVCommand(Main.ActiveGameTree.MainlineNode[1].NodeId,'0.25','e7e5');
    try Actor.ExecuteCommand(C); Check(C.Accepted,'Existing actor stores chess analysis'); finally C.Free; end;
    Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]); // Request a normal view refresh.
    Key:=VK_ESCAPE; Memo.OnKeyDown(Memo,Key,[]);
    Score:=nil;
    for I:=0 to Main.ComponentCount-1 do
      if Main.Components[I] is TScoreHistoryControl then Score:=TScoreHistoryControl(Main.Components[I]);
    Check((Score<>nil) and Score.TryCurrentEvaluation(Value) and (Abs(Value-0.25)<0.0001),'Score history works on chess annotations');
    C:=Actor.CreateRecordEnginePVCommand(Main.ActiveGameTree.Root.NodeId,'#5','d2d4');
    try Actor.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);finally C.Free;end;
    Key:=VK_LEFT;Memo.OnKeyDown(Memo,Key,[]);
    Key:=VK_LEFT;Memo.OnKeyDown(Memo,Key,[]);
    Check(Score.TryCurrentEvaluation(Value) and (Value=Score.MaxScore),
      'Root evaluation uses its own positive mate score');
    Click(B,12);Click(B,28); // d4 is a real variation; the mainline remains e4.
    C:=Actor.CreateRecordEnginePVCommand(Main.ActiveGameTree.Root.Children[1].NodeId,'#-4','d7d5');
    try Actor.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);finally C.Free;end;
    Key:=VK_LEFT;Memo.OnKeyDown(Memo,Key,[]);
    Key:=VK_RIGHT;Memo.OnKeyDown(Memo,Key,[]);
    Expected.LoadFromFEN(ChessStartingFEN);Expected.PlayMove('d2d4');
    Check(B.Position.ToFEN=Expected.ToFEN,'Evaluation probe displays the variation position');
    Check(Score.TryCurrentEvaluation(Value) and (Value=-Score.MaxScore),
      'Variation evaluation uses its negative mate score rather than mainline at same ply');
    Key:=VK_ESCAPE;Memo.OnKeyDown(Memo,Key,[]);
    Check(Score.TryCurrentEvaluation(Value) and (Abs(Value-0.25)<0.0001),
      'Returning to mainline restores the displayed position evaluation');
    Actor.Free; Actor:=nil;
    Main.LoadStandaloneFen('8/8/8/8/8/2kb4/r7/K7 w - - 99 1');
    Click(B,1); Check(Main.ActiveGameTree.MainlineCount=0,'Single legal chess move still waits for target');
    Click(B,9); Check(Main.ActiveGameTree.MainlineNode[1].MoveText='a1a2','Second click plays single move');
    Main.LoadStandaloneFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    Click(B,5); Click(B,7); Check(Main.ActiveGameTree.MainlineNode[1].MoveText='e1g1','Board castling');
    Main.LoadStandaloneFen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2');
    Click(B,37); Click(B,44); Check(Main.ActiveGameTree.MainlineNode[1].MoveText='e5d6','Board en passant');
    Choice.Main:=Main; GuiTestChoiceOnShow:=@Choice.Shown;
    for Scenario:=-1 to 4 do
    begin
      Main.LoadStandaloneFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      Choice.Index:=Scenario; Choice.Stale:=Scenario=4;
      if Choice.Stale then Choice.Index:=0;
      Click(B,49); Click(B,57);
      if Scenario=-1 then Check(Main.ActiveGameTree.MainlineCount=0,'Promotion cancellation changes nothing')
      else if Scenario=4 then Check((Main.ActiveGameTree.MainlineCount=0) and (B.Position.ToFEN=ChessStartingFEN),'Stale promotion rejected')
      else Check(Main.ActiveGameTree.MainlineNode[1].MoveText=Promotions[Scenario],'Promotion selection reaches existing actor');
    end;
    GuiTestChoiceOnShow:=nil;
    Main.LoadStandaloneFen('4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
    Legal.CaretPos:=Point(0,Legal.Lines.IndexOf('e8e7')); Legal.OnClick(Legal);
    Check(Pos('37...Ke7',Memo.Text)>0,'Main notation uses black fullmove 37');
    for I:=Low(Unsupported) to High(Unsupported) do
      Check(not Menu(Main,Unsupported[I]).Enabled,'Unsupported action disabled: '+Unsupported[I]);
    Check(Menu(Main,'&Database').Enabled and Menu(Main,'Search position in database').Enabled,'Chess database actions enabled');
    Check(Menu(Main,'&Open PGN...').Enabled and Menu(Main,'&Save PGN...').Enabled,'PGN file actions enabled');
    Clipboard.AsText:='sentinel'; Menu(Main,'Setup position...').OnClick(nil);
    Check(Clipboard.AsText='sentinel','Opening setup does not change clipboard');
    Menu(Main,'Copy FEN position to clipboard').Click;
    Check(Clipboard.AsText=B.Position.ToFEN,'Existing copy FEN exports displayed position');
    GuiTestConfirmationResult:=mrNo;
    Clipboard.AsText:=ChessStartingFEN; Menu(Main,'Paste FEN position from clipboard').Click;
    GuiTestConfirmationResult:=0;
    Check((Main.ActiveGameTree.MainlineCount=0) and (B.Position.ToFEN=ChessStartingFEN),'Existing paste FEN loads chess');
    Check(Pos('[Result',Main.CurrentGameTreePdnText(''))>0,'Existing export entry supplies PGN');
    Main.Close; // No misleading PDN save dialog in standalone chess mode.
  finally GuiTestChoiceOnShow:=nil; Actor.Free; Choice.Free; Expected.Free; Main.Free; end;
end;
procedure CheckPreviewEvaluation;
var Main:TMainForm;Actor:TGameTreeActor;C:TGameTreeCommand;Memo:TGameNotationView;
    Score:TScoreHistoryControl;Value:Double;I:Integer;Key:Word;Before:string;
  procedure Store(Command:TGameTreeCommand);
  begin C:=Command;try Actor.ExecuteCommand(C);Check(C.Accepted,C.ErrorText);finally C.Free;end;end;
  procedure SelectText(const Text:string);
  begin
    Check(Pos(Text,Memo.Text)>0,'Preview text '+Text);
    Memo.SelStart:=Pos(Text,Memo.Text)-1;
    Memo.SelLength:=Length(Text);Memo.OnClick(Memo);
  end;
  procedure Escape;
  begin Key:=VK_ESCAPE;Memo.OnKeyDown(Memo,Key,[]);end;
begin
  Main:=TMainForm.Create(nil);Actor:=nil;Score:=nil;
  try
    Main.LoadStandaloneFen(ChessStartingFEN);Actor:=TGameTreeActor.Create(Main.ActiveGameTree,False);
    Store(Actor.CreateRecordEnginePVCommand(Main.ActiveGameTree.Root.NodeId,'#5','d2d4 d7d5 c2c4'));
    Store(Actor.CreateRecordAnnotatorPVCommand(Main.ActiveGameTree.Root.NodeId,'#-4','e2e4 e7e5'));
    Store(Actor.CreateRecordAutoPlayPVCommand(Main.ActiveGameTree.Root.NodeId,'g1f3 g8f6'));
    Memo:=TGameNotationView(Main.FindComponent('GameMoveMemo'));Memo.Enabled:=False;
    for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TScoreHistoryControl then Score:=TScoreHistoryControl(Main.Components[I]);
    Check(Score<>nil,'Preview evaluation control exists');
    if not Menu(Main,'Show engine PV move').Checked then Menu(Main,'Show engine PV move').Click;
    if not Menu(Main,'Show engine full PV').Checked then Menu(Main,'Show engine full PV').Click;
    if not Menu(Main,'Show annotator PV move').Checked then Menu(Main,'Show annotator PV move').Click;
    if not Menu(Main,'Show annotator full PV').Checked then Menu(Main,'Show annotator full PV').Click;
    Key:=VK_LEFT;Memo.OnKeyDown(Memo,Key,[]);Before:=Main.CurrentGameTreePdnText('preview');
    SelectText('d4');
    for I:=1 to 3 do begin
      Check(Score.TryCurrentEvaluation(Value) and (Value=Score.MaxScore),'Every engine PV ply uses its positive mate score');
      Key:=VK_RIGHT;Memo.OnKeyDown(Memo,Key,[]);
    end;
    Escape;SelectText('e4');
    Check(Score.TryCurrentEvaluation(Value) and (Value=-Score.MaxScore),'Annotator PV uses its own negative mate score');
    Escape;SelectText('f3');
    Check(not Score.TryCurrentEvaluation(Value),'Unscored Auto Play preview stays neutral');
    Escape;Check(Main.CurrentGameTreePdnText('preview')=Before,'Score preview preserves tree and export');
  finally Actor.Free;Main.Free;end;
end;

procedure CheckPgnFiles;
var Main: TMainForm; Browser: TPdnOpenDialog; Grid: TStringGrid; Data: TStringList;
  Name,SavedName,BeforeFEN,BeforeText: string; Board: TGameBoardControl; Memo: TGameNotationView;
  I: Integer; RootId: Int64; CanClose: Boolean; Reader: TChessPgnReader; Key: Word;
begin
  Main:=TMainForm.Create(nil); Data:=TStringList.Create;
  Name:=GetTempFileName(GetTempDir,'zgi'); SavedName:=GetTempFileName(GetTempDir,'zgs');
  Reader:=nil;
  try
    Main.Show; Application.ProcessMessages;
    Board:=TGameBoardControl(Main.FindComponent('MainBoard'));
    Memo:=TGameNotationView(Main.FindComponent('GameMoveMemo'));
    Data.Text:='[Event "GUI first"] 1.e4 {literal engine: words} e5 (1...c5 $5) *'+#10+
      '[Event "GUI second"] 1.d4 d5 *'+#10+'[Event "bad"] 1.Ke5 *'; Data.SaveToFile(Name);
    GuiTestFileDialogResult:=1; GuiTestFileName:=Name;
    Menu(Main,'&Open PGN...').Click;
    Check((GuiTestFileTitle='Open PGN') and (Pos('*.pgn',GuiTestFileFilter)>0),'Existing Open uses PGN profile');
    Browser:=nil;
    for I:=0 to Main.ComponentCount-1 do if Main.Components[I] is TPdnOpenDialog then Browser:=TPdnOpenDialog(Main.Components[I]);
    Check(Browser<>nil,'Existing browser reused'); Grid:=TStringGrid(Browser.FindComponent('PdnGames'));
    Check((Grid.RowCount=4) and (Grid.Cells[2,1]='GUI first'),'Existing multi-game grid populated');
    Check((Grid.Cells[4,2]='On selection') and (Grid.Cells[4,3]='On selection'),'Other games remain deferred');
    GuiTestConfirmationResult:=mrNo;
    GuiTestFileName:=Name+'.missing'; Menu(Main,'&Open PGN...').Click;
    Check((Grid.RowCount=4) and (Grid.Cells[2,1]='GUI first'),'Failed Open preserves browser contents');
    GuiTestConfirmationResult:=mrNo; Grid.Row:=1; Grid.OnDblClick(Grid);
    Check((Main.ActiveGameTree.MainlineCount=2) and (Main.ActiveGameTree.BranchCount=1),'PGN selection imports existing tree');
    Check(Main.ActiveGameTree.MainlineNode[1].CommentText='literal engine: words','GUI retains literal comments');
    BeforeFEN:=Board.Position.ToFEN; BeforeText:=Memo.Text; RootId:=Main.ActiveGameTree.Root.NodeId;
    Grid.Row:=3; Grid.OnDblClick(Grid);
    Check(Pos('illegal',GuiTestLastConfirmationText)>0,'Bad selected game reported');
    Check((Main.ActiveGameTree.Root.NodeId=RootId) and (Board.Position.ToFEN=BeforeFEN) and
      (Memo.Text=BeforeText),'Bad selection preserves tree and display');
    Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]); Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]);
    BeforeFEN:=Board.Position.ToFEN; BeforeText:=Memo.Text;
    GuiTestConfirmationResult:=mrCancel; Grid.Row:=2; Grid.OnDblClick(Grid);
    Check(Main.ActiveGameTree.Root.NodeId=RootId,'Cancelled replacement preserves tree');
    GuiTestConfirmationResult:=mrYes; GuiTestFileDialogResult:=0; Grid.OnDblClick(Grid);
    Check((Main.ActiveGameTree.Root.NodeId=RootId) and (Board.Position.ToFEN=BeforeFEN) and
      (Memo.Text=BeforeText),'Cancelled Save preserves replacement tree, cursor and view');
    GuiTestFileDialogResult:=1; GuiTestFileName:=SavedName+'/missing/game.pgn'; Grid.OnDblClick(Grid);
    Check((Main.ActiveGameTree.Root.NodeId=RootId) and (Board.Position.ToFEN=BeforeFEN) and
      (Memo.Text=BeforeText),'Failed Save preserves replacement tree, cursor and view');
    GuiTestFileName:=SavedName; Grid.OnDblClick(Grid);
    Check(Main.ActiveGameTree.EventName='GUI second','Successful Save then replacement');
    Check((GuiTestFileTitle='Save PGN') and ((GuiTestFileExtension='pgn') or (GuiTestFileExtension='.pgn')),'Existing Save uses PGN profile');
    Reader:=TChessPgnReader.Create(Variant); Reader.OpenFile(SavedName);
    Check(Reader.Entries.Count=1,'Saved first game');
    TGameFileEntry(Reader.Entries[0]).Validate;
    Check(TGameFileEntry(Reader.Entries[0]).ErrorText='','Saved PGN validates');
    Menu(Main,'&Save PGN...').Click; Reader.OpenFile(SavedName);
    Check(Reader.Entries.Count=2,'Existing append workflow saves second game');
    GuiTestFileDialogResult:=0; Main.OnCloseQuery(Main,CanClose);
    Check(not CanClose,'Cancelled Save vetoes close');
    GuiTestConfirmationResult:=mrNo; Main.OnCloseQuery(Main,CanClose);
    Check(CanClose,'Explicit No permits close with PGN available');
  finally
    GuiTestFileDialogResult:=-1; GuiTestConfirmationResult:=0;
    Reader.Free; Main.Free; Data.Free; DeleteFile(Name); DeleteFile(SavedName);
  end;
end;

procedure CheckDiscardProtection;
var Main: TMainForm; Board: TGameBoardControl; Memo: TGameNotationView;
    Actor: TGameTreeActor; Command: TGameTreeCommand; CanClose: Boolean;
    BeforeFEN,BeforeText,BeforeLegal,Selection: string; Key: Word;
    TreeId,TipId,BranchId: Int64; BeforeCount,BeforeBranches,BeforeSelStart,BeforeSelLength: Integer;
    BeforeNode,BeforeBranch: TGameTreePlyNode; Confirmation: TConfirmation; Profile: TGameGuiProfile;
begin
  Profile:=ChessGuiProfile; Profile.Features:=[];
  RegisterGameGuiProfile(DefaultGameVariant,Profile);
  Main:=TMainForm.Create(nil); Actor:=nil; Confirmation:=TConfirmation.Create;
  try
    Main.Show; Application.ProcessMessages;
    Board:=TGameBoardControl(Main.FindComponent('MainBoard'));
    Memo:=TGameNotationView(Main.FindComponent('GameMoveMemo')); Memo.Enabled:=False;
    // An untouched standard board neither blocks Paste nor asks on close.
    GuiTestConfirmationResult:=0; GuiTestLastConfirmationText:='';
    CanClose:=False; Main.OnCloseQuery(Main,CanClose); Check(CanClose,'Empty initial board closes without a prompt');
    Check(GuiTestLastConfirmationText='','No initial-board discard prompt');
    Clipboard.AsText:=ChessStartingFEN; Menu(Main,'Paste FEN position from clipboard').Click;
    Check(GuiTestLastConfirmationText='','Empty initial board can be replaced without a prompt');
    Click(Board,13); Click(Board,29); Click(Board,53); Click(Board,37);
    Actor:=TGameTreeActor.Create(Main.ActiveGameTree,False);
    BeforeNode:=Main.ActiveGameTree.MainlineNode[1];
    Command:=Actor.CreateStoreMoveVariationCommand(BeforeNode.NodeId,'c7c5',gmsHuman);
    try
      Actor.ExecuteCommand(Command); Check(Command.Accepted,'Create branch for discard tests');
      BranchId:=Command.CreatedNodeId;
    finally Command.Free; end;
    Command:=Actor.CreateStoreMoveVariationCommand(BranchId,'g1f3',gmsHuman);
    try Actor.ExecuteCommand(Command); Check(Command.Accepted,'Create nested branch'); finally Command.Free; end;
    BeforeBranch:=Main.ActiveGameTree.FindNodeById(BranchId);
    Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]); // Freeze at mainline tip.
    Key:=VK_LEFT; Memo.OnKeyDown(Memo,Key,[]); // Select e4, not the live tip.
    TreeId:=Main.ActiveGameTree.GameTreeId; BeforeCount:=Main.ActiveGameTree.MainlineCount;
    BeforeBranches:=Main.ActiveGameTree.BranchCount; TipId:=Main.ActiveGameTree.MainlineNode[2].NodeId;
    BeforeFEN:=Board.Position.ToFEN; BeforeText:=Memo.Text;
    BeforeLegal:=TMemo(Main.FindComponent('LegalMovesMemo')).Text;
    BeforeSelStart:=Memo.SelStart; BeforeSelLength:=Memo.SelLength; Selection:=Memo.SelText;
    Check(Selection<>'','Cancel test has a real notation selection');
    GuiTestConfirmationResult:=0;
    Confirmation.ExpectedDefault:='Cancel'; Confirmation.ExpectCancelFocus:=True;
    GuiTestConfirmationOnShow:=@Confirmation.Shown;
    Clipboard.AsText:=ChessStartingFEN; Menu(Main,'Paste FEN position from clipboard').Click;
    Check(Confirmation.ShownCount=1,'Paste constructs actual Cancel-default dialog');
    Check((Board.Position.ToFEN=BeforeFEN) and (Memo.SelStart=BeforeSelStart) and
      (Main.ActiveGameTree.FindNodeById(BranchId)=BeforeBranch),'Default Paste action preserves explored tree and selection');
    Main.OnCloseQuery(Main,CanClose);
    Check((not CanClose) and (Confirmation.ShownCount=2),'Default close action cancels');
    Check(Main.ActiveGameTree.MainlineNode[2].NodeId=TipId,'Default close action preserves tree');
    Confirmation.ClickAccept:=True; Main.OnCloseQuery(Main,CanClose);
    Check(CanClose,'Explicit Discard still accepts actual close dialog');
    Confirmation.ClickAccept:=False; Confirmation.ExpectCancelFocus:=False; Confirmation.ExpectedDefault:='Yes';
    Check(ShowGuiConfirmationDialog(Main,'Legacy save','Save first?','Yes','No',mrNo)=mrYes,
      'Omitted option preserves actual legacy accept default');
    Confirmation.ExpectedDefault:='OK';
    Check(ShowGuiOkDialog(Main,'Information','Unchanged OK default')=mrYes,'OK dialog keeps its default');
    GuiTestConfirmationOnShow:=nil;
    GuiTestConfirmationResult:=mrCancel;
    Clipboard.AsText:=ChessStartingFEN; Menu(Main,'Paste FEN position from clipboard').Click;
    Check(GuiTestLastConfirmationText='Discard the current board and its moves?','Paste asks about discarding');
    Check((Main.ActiveGameTree.GameTreeId=TreeId) and
      (Main.ActiveGameTree.MainlineCount=BeforeCount) and (Main.ActiveGameTree.BranchCount=BeforeBranches),
      'Cancelled Paste preserves tree and branches');
    Check((Main.ActiveGameTree.MainlineNode[2].NodeId=TipId) and
      (Main.ActiveGameTree.FindNodeById(BeforeNode.NodeId)=BeforeNode) and
      (Main.ActiveGameTree.FindNodeById(BranchId)=BeforeBranch), 'Cancelled Paste preserves node identity');
    Check((Board.Position.ToFEN=BeforeFEN) and (Memo.Text=BeforeText) and
      (Memo.SelStart=BeforeSelStart) and (Memo.SelLength=BeforeSelLength) and (Memo.SelText=Selection) and
      (TMemo(Main.FindComponent('LegalMovesMemo')).Text=BeforeLegal), 'Cancelled Paste preserves view, cursor and legal list');
    GuiTestLastConfirmationText:=''; Main.OnCloseQuery(Main,CanClose);
    Check(not CanClose,'Cancel vetoes close');
    Check(GuiTestLastConfirmationText='Discard the current board and its moves?','Close asks about discarding');
    Check((Main.ActiveGameTree.GameTreeId=TreeId) and (Main.ActiveGameTree.BranchCount=BeforeBranches) and
      (Main.ActiveGameTree.MainlineNode[2].NodeId=TipId) and
      (Main.ActiveGameTree.FindNodeById(BranchId)=BeforeBranch), 'Cancelled close preserves entire tree');
    Check((Board.Position.ToFEN=BeforeFEN) and (Memo.Text=BeforeText) and
      (Memo.SelStart=BeforeSelStart) and (Memo.SelLength=BeforeSelLength), 'Cancelled close preserves view and selection');
    GuiTestConfirmationResult:=mrNo; Main.OnCloseQuery(Main,CanClose);
    Check(not CanClose,'Only explicit Discard accepts close');
    GuiTestConfirmationResult:=mrYes; Main.OnCloseQuery(Main,CanClose);
    Check(CanClose,'Explicit Discard allows close');
    Check(Main.ActiveGameTree.MainlineNode[2].NodeId=TipId,'Close query does not mutate the tree');
    Clipboard.AsText:='not a chess FEN'; Menu(Main,'Paste FEN position from clipboard').Click;
    Check(Pos('Invalid FEN:',GuiTestLastConfirmationText)>0,'Invalid replacement is reported');
    Check((Main.ActiveGameTree.MainlineNode[2].NodeId=TipId) and
      (Main.ActiveGameTree.FindNodeById(BranchId)=BeforeBranch) and
      (Board.Position.ToFEN=BeforeFEN),'Invalid replacement preserves explored tree');
    Check((Memo.Text=BeforeText) and (Memo.SelStart=BeforeSelStart) and
      (Memo.SelLength=BeforeSelLength),'Invalid replacement preserves displayed notation');
    // Releasing a test-only observer before replacing the tree keeps ownership explicit.
    Actor.Free; Actor:=nil;
    Clipboard.AsText:=ChessStartingFEN; Menu(Main,'Paste FEN position from clipboard').Click;
    Check((Main.ActiveGameTree.MainlineCount=0) and (Main.ActiveGameTree.BranchCount=0) and
      (Board.Position.ToFEN=ChessStartingFEN),'Explicit Discard allows FEN replacement');
    // A custom root FEN is valuable even when it has no played moves.
    Main.LoadStandaloneFen('4k3/8/8/8/8/8/8/R3K3 b - - 0 37');
    BeforeFEN:=Board.Position.ToFEN; GuiTestConfirmationResult:=mrCancel;
    Menu(Main,'Paste FEN position from clipboard').Click;
    Check(Board.Position.ToFEN=BeforeFEN,'Cancel protects a custom root position');
    Main.OnCloseQuery(Main,CanClose); Check(not CanClose,'Custom root also protected on close');
  finally GuiTestConfirmationOnShow:=nil; GuiTestConfirmationResult:=0;
    Confirmation.Free; Actor.Free; Main.Free; RegisterGameGuiProfile(DefaultGameVariant,ChessGuiProfile); end;
end;

var Errors: TErrors;
begin
  RequireDerivedFormResource:=False; Application.Initialize; Errors:=TErrors.Create;
  Application.OnException:=@Errors.Report;
  Variant:=TChessVariant.Create;
  try
    RegisterDefaultGameVariant(Variant);
    CheckView; CheckCoordinateContrast; CheckPV; CheckLayout; CheckMain; CheckMateHistory; CheckPreviewEvaluation; CheckPgnFiles; CheckDiscardProtection;
    WriteLn('Chess board/PV/GUI checks passed (',Checks,' checks)');
  finally RegisterDefaultGameVariant(DraughtsVariant); Variant.Free; Errors.Free; end;
end.
