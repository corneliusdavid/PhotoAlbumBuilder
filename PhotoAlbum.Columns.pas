unit PhotoAlbum.Columns;

{ Masonry column balancer.
  Distributes items into N columns by greedily appending each item to the
  shortest column (by cumulative pixel height).  This matches the visual
  result of CSS column-count / column-fill: balance without requiring
  JavaScript measurement at render time.

  Two overloads:
    BalanceCards  — categories or albums onto a TCardsPageData.Columns grid
    BalancePhotos — photos onto a TAlbumPageData.Columns grid

  Callers own the TCardsPageData / TAlbumPageData and its Columns list;
  this unit only populates them. }

interface

uses
  PhotoAlbum.StencilData;

{ Distribute AItems across AColumnCount columns inside APage.Columns.
  AThumbHeight is the fixed card thumbnail height in pixels (used for
  balance heuristic; all cards are assumed the same height). }
procedure BalanceCards(APage: TCardsPageData;
                       AItems: TCardItems;
                       AColumnCount: Integer;
                       AThumbHeight: Integer = 200); overload;

{ Same balancer for taxonomy terms — populates ATerm.Columns directly. }
procedure BalanceCards(ATerm: TTaxTerm;
                       AItems: TCardItems;
                       AColumnCount: Integer;
                       AThumbHeight: Integer = 200); overload;

{ Distribute AItems across AColumnCount columns inside APage.Columns.
  Each TPhotoItem must already have ThumbH set (actual pixel height of its
  thumbnail) so column heights reflect the real image heights. }
procedure BalancePhotos(APage: TAlbumPageData;
                        AItems: TPhotoItems;
                        AColumnCount: Integer);

implementation

uses
  System.SysUtils;

{ ── Shortest-column greedy fill ──────────────────────────────────────────── }

{ Returns the index of the column with the smallest cumulative height. }
function ShortestColumn(const AHeights: array of Integer): Integer;
var
  I, LMin: Integer;
begin
  Result := 0;
  LMin   := AHeights[0];
  for I  := 1 to High(AHeights) do
    if AHeights[I] < LMin then
    begin
      LMin   := AHeights[I];
      Result := I;
    end;
end;

{ ── BalanceCards ─────────────────────────────────────────────────────────── }

procedure BalanceCards(APage: TCardsPageData;
                       AItems: TCardItems;
                       AColumnCount: Integer;
                       AThumbHeight: Integer);
var
  LHeights: array of Integer;
  LCol:     Integer;
  I:        Integer;
  LItem:    TCardItem;
  LCard:    TCardItem;
  LColumn:  TCardColumn;
begin
  if (AColumnCount < 1) or (AItems.Count = 0) then
    Exit;

  { Create columns }
  SetLength(LHeights, AColumnCount);
  for I := 0 to AColumnCount - 1 do
  begin
    LColumn := TCardColumn.Create;
    APage.Columns.Add(LColumn);
    LHeights[I] := 0;
  end;

  { Assign each card to the shortest column }
  for LItem in AItems do
  begin
    LCol := ShortestColumn(LHeights);

    { The card item is owned by the caller's AItems list; we add a new
      wrapper into the column that copies the display fields. }
    LCard          := TCardItem.Create;
    LCard.Title    := LItem.Title;
    LCard.URL      := LItem.URL;
    LCard.ThumbURL := LItem.ThumbURL;
    APage.Columns[LCol].Items.Add(LCard);

    Inc(LHeights[LCol], AThumbHeight);
  end;
end;

{ ── BalanceCards (TTaxTerm overload) ─────────────────────────────────────── }

procedure BalanceCards(ATerm: TTaxTerm;
                       AItems: TCardItems;
                       AColumnCount: Integer;
                       AThumbHeight: Integer);
var
  LHeights: array of Integer;
  LCol:     Integer;
  I:        Integer;
  LItem:    TCardItem;
  LCard:    TCardItem;
  LColumn:  TCardColumn;
begin
  if (AColumnCount < 1) or (AItems.Count = 0) then
    Exit;

  SetLength(LHeights, AColumnCount);
  for I := 0 to AColumnCount - 1 do
  begin
    LColumn := TCardColumn.Create;
    ATerm.Columns.Add(LColumn);
    LHeights[I] := 0;
  end;

  for LItem in AItems do
  begin
    LCol           := ShortestColumn(LHeights);
    LCard          := TCardItem.Create;
    LCard.Title    := LItem.Title;
    LCard.URL      := LItem.URL;
    LCard.ThumbURL := LItem.ThumbURL;
    ATerm.Columns[LCol].Items.Add(LCard);
    Inc(LHeights[LCol], AThumbHeight);
  end;
end;

{ ── BalancePhotos ─────────────────────────────────────────────────────────── }

procedure BalancePhotos(APage: TAlbumPageData;
                        AItems: TPhotoItems;
                        AColumnCount: Integer);
var
  LHeights: array of Integer;
  LCol:     Integer;
  I:        Integer;
  LSrc:     TPhotoItem;
  LPhoto:   TPhotoItem;
  LColumn:  TPhotoColumn;
begin
  if (AColumnCount < 1) or (AItems.Count = 0) then
    Exit;

  { Create columns }
  SetLength(LHeights, AColumnCount);
  for I := 0 to AColumnCount - 1 do
  begin
    LColumn := TPhotoColumn.Create;
    APage.Columns.Add(LColumn);
    LHeights[I] := 0;
  end;

  { Assign each photo to the shortest column }
  for LSrc in AItems do
  begin
    LCol := ShortestColumn(LHeights);

    LPhoto              := TPhotoItem.Create;
    LPhoto.ThumbURL     := LSrc.ThumbURL;
    LPhoto.FullURL      := LSrc.FullURL;
    LPhoto.OrigName     := LSrc.OrigName;
    LPhoto.ID           := LSrc.ID;
    LPhoto.Description  := LSrc.Description;
    LPhoto.GalleryIndex := LSrc.GalleryIndex;
    LPhoto.SetPhotoTitle(LSrc.PhotoTitle);
    APage.Columns[LCol].Photos.Add(LPhoto);

    Inc(LHeights[LCol], LSrc.ThumbH);
  end;
end;

end.
