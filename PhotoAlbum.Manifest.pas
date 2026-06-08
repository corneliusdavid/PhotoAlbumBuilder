unit PhotoAlbum.Manifest;

{ Incremental build manifest.
  Stored as JSON at [output]/.manifest.json.
  Maps album RelPath → the UTC last-modified timestamp of the album's source
  at the time it was last built.  NeedsRebuild() compares the stored value
  against the current filesystem timestamp; if they differ the album is stale.

  AlbumSourceModified() scans the _index.md and every declared resource file
  and returns the newest mtime, so any edit — to the metadata or a photo —
  triggers a rebuild of that album. }

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  PhotoAlbum.Content;

type
  TBuildManifest = class
  private
    FPath:    string;
    FEntries: TDictionary<string, TDateTime>;  // relPath → source mtime (UTC)
    FDirty:   Boolean;
  public
    constructor Create;
    destructor  Destroy; override;

    { Load existing manifest from disk; silently starts empty if not found. }
    procedure Load(const AManifestPath: string);

    { Flush to disk only when entries have changed. }
    procedure Save;

    { True when the album has never been built, or its source is newer
      than the stored timestamp. }
    function NeedsRebuild(const ARelPath: string;
                          ASourceModified: TDateTime): Boolean;

    { Record that the album was just built from the given source mtime. }
    procedure MarkBuilt(const ARelPath: string;
                        ASourceModified: TDateTime);

    { Remove stale entries for albums that no longer exist in the content tree. }
    procedure PurgeAbsent(ACategories: TCategories);
  end;

{ Returns the newest UTC last-write time across _index.md and all resource
  files for the given album.  Uses 0 on any missing file so a missing photo
  always triggers a rebuild. }
function AlbumSourceModified(const AAlbum: TAlbumMeta;
                             const AAssetsPath: string): TDateTime;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.JSON;

{ ── Timestamp helpers ─────────────────────────────────────────────────────── }

function MaxDateTime(A, B: TDateTime): TDateTime; inline;
begin
  if A > B then Result := A else Result := B;
end;

function FileModifiedUtc(const APath: string): TDateTime;
begin
  if TFile.Exists(APath) then
    Result := TFile.GetLastWriteTimeUtc(APath)
  else
    Result := 0;
end;

{ ── AlbumSourceModified ──────────────────────────────────────────────────── }

function AlbumSourceModified(const AAlbum: TAlbumMeta;
                             const AAssetsPath: string): TDateTime;
var
  LNewest:   TDateTime;
  LResource: string;
  LPath:     string;
begin
  LNewest := FileModifiedUtc(TPath.Combine(AAlbum.ContentPath, '_index.md'));

  for LResource in AAlbum.Resources do
  begin
    { Photos live in assets under the same relative album path }
    LPath   := TPath.Combine(AAssetsPath, AAlbum.RelPath);
    LPath   := TPath.Combine(LPath, LResource);
    LNewest := MaxDateTime(LNewest, FileModifiedUtc(LPath));
  end;

  Result := LNewest;
end;

{ ── TBuildManifest ───────────────────────────────────────────────────────── }

constructor TBuildManifest.Create;
begin
  inherited;
  FEntries := TDictionary<string, TDateTime>.Create;
end;

destructor TBuildManifest.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TBuildManifest.Load(const AManifestPath: string);
var
  LJson:   TJSONObject;
  LPair:   TJSONPair;
  LMtime:  TDateTime;
begin
  FPath := AManifestPath;
  FEntries.Clear;
  FDirty := False;

  if not TFile.Exists(AManifestPath) then
    Exit;

  try
    LJson := TJSONObject.ParseJSONValue(
               TFile.ReadAllText(AManifestPath, TEncoding.UTF8))
             as TJSONObject;
    if LJson = nil then
      Exit;
    try
      for LPair in LJson do
      begin
        LMtime := ISO8601ToDate(LPair.JsonValue.Value, False); // False = UTC
        FEntries.AddOrSetValue(LPair.JsonString.Value, LMtime);
      end;
    finally
      LJson.Free;
    end;
  except
    { Corrupt manifest — start fresh }
    FEntries.Clear;
  end;
end;

procedure TBuildManifest.Save;
var
  LJson: TJSONObject;
  LPair: TPair<string, TDateTime>;
begin
  if not FDirty then
    Exit;

  LJson := TJSONObject.Create;
  try
    for LPair in FEntries do
      LJson.AddPair(LPair.Key,
                    DateToISO8601(LPair.Value, False)); // False = UTC

    TDirectory.CreateDirectory(TPath.GetDirectoryName(FPath));
    TFile.WriteAllText(FPath,
                       LJson.Format(2),   // 2-space indent for readability
                       TEncoding.UTF8);
  finally
    LJson.Free;
  end;

  FDirty := False;
end;

function TBuildManifest.NeedsRebuild(const ARelPath: string;
                                     ASourceModified: TDateTime): Boolean;
var
  LStored: TDateTime;
begin
  if not FEntries.TryGetValue(ARelPath, LStored) then
    Exit(True);   // never built

  { Allow a one-second tolerance for FAT/NTFS timestamp rounding }
  Result := Abs(ASourceModified - LStored) > (1 / SecsPerDay);
end;

procedure TBuildManifest.MarkBuilt(const ARelPath: string;
                                   ASourceModified: TDateTime);
begin
  FEntries.AddOrSetValue(ARelPath, ASourceModified);
  FDirty := True;
end;

procedure TBuildManifest.PurgeAbsent(ACategories: TCategories);
var
  LLive:     TDictionary<string, Boolean>;
  LCat:      TCategoryMeta;
  LAlbum:    TAlbumMeta;
  LKey:      string;
  LToDelete: TArray<string>;
  I:         Integer;
begin
  { Build a set of live album paths }
  LLive := TDictionary<string, Boolean>.Create;
  try
    for LCat in ACategories do
      for LAlbum in LCat.Albums do
        LLive.AddOrSetValue(LAlbum.RelPath, True);

    { Collect stale keys }
    SetLength(LToDelete, 0);
    for LKey in FEntries.Keys do
      if not LLive.ContainsKey(LKey) then
      begin
        SetLength(LToDelete, Length(LToDelete) + 1);
        LToDelete[High(LToDelete)] := LKey;
      end;
  finally
    LLive.Free;
  end;

  { Remove them }
  for I := 0 to High(LToDelete) do
  begin
    FEntries.Remove(LToDelete[I]);
    FDirty := True;
  end;
end;

end.
