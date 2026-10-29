unit uPositionSetupAdapter;
{$mode objfpc}{$H+}
{ Dialog-local drafts only. No editing is added to the playable position API. }
interface
uses Classes, Graphics, Types, uGamePosition, uGameBoardControl;
type
  TPositionSetupAdapter=class
  public
    constructor Create; virtual;
    function IsChessSetup:Boolean; virtual;
    function CreateBoard(AOwner:TComponent):TGameBoardControl; virtual; abstract;
    procedure LoadFen(const Fen:string); virtual; abstract;
    function DraftFen:string; virtual; abstract;
    function ValidatedFen:string; virtual;
    procedure Start; virtual; abstract;
    procedure Clear; virtual; abstract;
    function Side:TGameSide; virtual; abstract;
    procedure SetSide(Value:TGameSide); virtual; abstract;
    function PaletteCount:Integer; virtual; abstract;
    function PalettePiece(Index:Integer):Integer; virtual; abstract;
    function PieceName(Index:Integer):string; virtual; abstract;
    procedure Toggle(Square,Piece:Integer); virtual; abstract;
    procedure PaintTile(Canvas:TCanvas;const Bounds:TRect;Index,Selected:Integer;
      DarkColor:TColor); virtual; abstract;
  end;
  TPositionSetupAdapterClass=class of TPositionSetupAdapter;
implementation
constructor TPositionSetupAdapter.Create;
begin inherited Create;end;
function TPositionSetupAdapter.IsChessSetup:Boolean;
begin Result:=False;end;
function TPositionSetupAdapter.ValidatedFen:string;
begin Result:=DraftFen;end;
end.
