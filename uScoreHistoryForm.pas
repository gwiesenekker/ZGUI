unit uScoreHistoryForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, Controls, Forms, uGamePosition, uPreferences,
  uScoreHistoryControl;

type
  TScoreHistoryForm = class(TForm)
  private
    FScoreHistoryControl: TScoreHistoryControl;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ApplyScoreColors(const Colors:TScoreHistoryColors);
    procedure SetPositionEvaluation(const EngineScore,AnnotatorScore:string;
      AUsePosition:Boolean=True);
    procedure UpdateScores(const AAnnotationsText: string; APlyCount,
      ACurrentPly: Integer; AMaxScore: Double; AScale: TScoreScale;
      AStartingSide: TGameSide; AStartingMoveNumber: Integer = 1);
  end;

implementation

constructor TScoreHistoryForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Caption := 'Score history';
  Position := poDesigned;
  BorderStyle := bsSizeable;
  Width := 760;
  Height := 260;
  Constraints.MinWidth := 360;
  Constraints.MinHeight := 180;

  FScoreHistoryControl := TScoreHistoryControl.Create(Self);
  FScoreHistoryControl.Parent := Self;
  FScoreHistoryControl.Align := alClient;
  FScoreHistoryControl.DisplayMode := shdmBars;
  FScoreHistoryControl.ShowEvaluationBar := True;
end;

procedure TScoreHistoryForm.ApplyScoreColors(const Colors:TScoreHistoryColors);
begin FScoreHistoryControl.ScoreColors:=Colors;end;

procedure TScoreHistoryForm.SetPositionEvaluation(const EngineScore,AnnotatorScore:string;
  AUsePosition:Boolean);
begin FScoreHistoryControl.SetPositionEvaluation(EngineScore,AnnotatorScore,AUsePosition);end;

procedure TScoreHistoryForm.UpdateScores(const AAnnotationsText: string;
  APlyCount, ACurrentPly: Integer; AMaxScore: Double; AScale: TScoreScale;
  AStartingSide: TGameSide; AStartingMoveNumber: Integer);
begin
  FScoreHistoryControl.MaxScore := AMaxScore;
  FScoreHistoryControl.Scale := AScale;
  FScoreHistoryControl.StartingSide := AStartingSide;
  FScoreHistoryControl.StartingMoveNumber := AStartingMoveNumber;
  FScoreHistoryControl.PlyCount := APlyCount;
  FScoreHistoryControl.AnnotationsText := AAnnotationsText;
  FScoreHistoryControl.CurrentPly := ACurrentPly;
end;

end.
