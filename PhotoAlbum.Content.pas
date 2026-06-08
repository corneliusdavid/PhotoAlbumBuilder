unit PhotoAlbum.Content;

{ Walks the content folder tree and parses every _index.md file.
  Builds the in-memory content model:
    TContentTree → TCategories → TAlbums

  The two-level structure (category / album) matches the site layout:
    content/
      <category>/
        _index.md
        <album>/
          _index.md   ← has resources list, tags, locations

  VSoft.YAML parses the YAML frontmatter (the block between the ---
  delimiters).  Draft albums/categories are silently skipped. }

interface

uses
  System.SysUtils,
  System.Classes, System.Generics.Defaults,
  System.Generics.Collections,
  System.IOUtils;

type

  TAlbumMeta = class
  private
    FTitle:       string;
    FDescription: string;
    FAlbumThumb:  string;
    FDate:        TDateTime;
    FWeight:      Integer;
    FDraft:       Boolean;
    FTags:        TStringList;
    FLocations:   TStringList;
    FResources:   TStringList;
    FContentPath: string;   // full path to the album folder
    FRelPath:     string;   // forward-slash path, e.g. "beach/cannon-beach-2010"
  public
    constructor Create;
    destructor  Destroy; override;
    property Title:       string      read FTitle       write FTitle;
    property Description: string      read FDescription write FDescription;
    property AlbumThumb:  string      read FAlbumThumb  write FAlbumThumb;
    property Date:        TDateTime   read FDate        write FDate;
    property Weight:      Integer     read FWeight      write FWeight;
    property Draft:       Boolean     read FDraft       write FDraft;
    property Tags:        TStringList read FTags;
    property Locations:   TStringList read FLocations;
    property Resources:   TStringList read FResources;
    property ContentPath: string      read FContentPath write FContentPath;
    property RelPath:     string      read FRelPath     write FRelPath;
  end;

  TAlbums = class(TObjectList<TAlbumMeta>);

  TCategoryMeta = class
  private
    FTitle:       string;
    FDescription: string;
    FAlbumThumb:  string;
    FWeight:      Integer;
    FDraft:       Boolean;
    FAlbums:      TAlbums;
    FContentPath: string;
    FRelPath:     string;
  public
    constructor Create;
    destructor  Destroy; override;
    property Title:       string    read FTitle       write FTitle;
    property Description: string    read FDescription write FDescription;
    property AlbumThumb:  string    read FAlbumThumb  write FAlbumThumb;
    property Weight:      Integer   read FWeight      write FWeight;
    property Draft:       Boolean   read FDraft       write FDraft;
    property Albums:      TAlbums   read FAlbums;
    property ContentPath: string    read FContentPath write FContentPath;
    property RelPath:     string    read FRelPath     write FRelPath;
  end;

  TCategories = class(TObjectList<TCategoryMeta>);

  TContentTree = class
  private
    FSiteDescription: string;
    FCategories:      TCategories;
    procedure ParseAlbumIndex(const AFolder, ARelPath: string;
                              AAlbum: TAlbumMeta);
    procedure ParseCategoryIndex(const AFolder, ARelPath: string;
                                 ACategory: TCategoryMeta);
    procedure LoadCategory(const ACategoryFolder: string;
                           ACategories: TCategories);
  public
    constructor Create;
    destructor  Destroy; override;
    procedure Load(const AContentPath: string);
    property SiteDescription: string      read FSiteDescription;
    property Categories:      TCategories read FCategories;
  end;

{ Extracts the YAML block between the leading --- markers from any Hugo
  markdown file.  Returns empty string if the file has no frontmatter. }
function ExtractFrontmatter(const AFilePath: string): string;

implementation

uses
  System.DateUtils,
  VSoft.YAML;

{ ── Frontmatter extraction ───────────────────────────────────────────────── }

function ExtractFrontmatter(const AFilePath: string): string;
var
  LLines:   TStringList;
  I:        Integer;
  LInBlock: Boolean;
  LResult:  TStringBuilder;
begin
  Result := '';
  if not TFile.Exists(AFilePath) then
    Exit;

  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(AFilePath, TEncoding.UTF8);

    { First non-blank line must be '---' to have frontmatter }
    I := 0;
    while (I < LLines.Count) and (LLines[I].Trim = '') do
      Inc(I);

    if (I >= LLines.Count) or (LLines[I].Trim <> '---') then
      Exit;

    Inc(I); // step past opening ---
    LInBlock := True;
    LResult  := TStringBuilder.Create;
    try
      while LInBlock and (I < LLines.Count) do
      begin
        if LLines[I].Trim = '---' then
          LInBlock := False
        else
        begin
          LResult.AppendLine(LLines[I]);
          Inc(I);
        end;
      end;
      Result := LResult.ToString;
    finally
      LResult.Free;
    end;
  finally
    LLines.Free;
  end;
end;

{ ── Sequence → TStringList ───────────────────────────────────────────────── }

procedure SeqToList(const ASeq: IYAMLSequence; AList: TStringList);
var
  J: Integer;
begin
  for J := 0 to ASeq.Count - 1 do
    AList.Add(ASeq.S[J]);
end;

{ ── TAlbumMeta ───────────────────────────────────────────────────────────── }

constructor TAlbumMeta.Create;
begin
  inherited;
  FTags      := TStringList.Create;
  FLocations := TStringList.Create;
  FResources := TStringList.Create;
  FWeight    := 0;
end;

destructor TAlbumMeta.Destroy;
begin
  FTags.Free;
  FLocations.Free;
  FResources.Free;
  inherited;
end;

{ ── TCategoryMeta ────────────────────────────────────────────────────────── }

constructor TCategoryMeta.Create;
begin
  inherited;
  FAlbums := TAlbums.Create(True);
  FWeight := 0;
end;

destructor TCategoryMeta.Destroy;
begin
  FAlbums.Free;
  inherited;
end;

{ ── TContentTree ─────────────────────────────────────────────────────────── }

constructor TContentTree.Create;
begin
  inherited;
  FCategories := TCategories.Create(True);
end;

destructor TContentTree.Destroy;
begin
  FCategories.Free;
  inherited;
end;

{ Reads the resources: block from a raw _index.md without going through the
  YAML parser.  Scans for the 'resources:' key then collects every '- value'
  line until a non-indented line is encountered.  This preserves underscores
  and other characters that VSoft.YAML's lexer strips from numeric-looking
  scalar tokens (e.g. 100_3319.jpg → 1003319.jpg). }
procedure ReadResourcesFromFile(const APath: string; AList: TStringList);
var
  LLines:      TStringList;
  I:           Integer;
  LTrimmed:    string;
  LInResources: Boolean;
  LValue:      string;
begin
  if not TFile.Exists(APath) then
    Exit;

  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(APath, TEncoding.UTF8);
    LInResources := False;

    I := 0;
    while I < LLines.Count do
    begin
      LTrimmed := LLines[I].Trim;

      if LTrimmed = '---' then
      begin
        if LInResources then
          Break;  // hit closing frontmatter delimiter
        Inc(I);
        Continue;
      end;

      if not LInResources then
      begin
        { Look for the resources: key (unindented or indented) }
        if SameText(LTrimmed, 'resources:') then
          LInResources := True;
      end
      else
      begin
        { Inside the resources block — collect '- value' lines }
        if LTrimmed.StartsWith('- ') then
        begin
          LValue := LTrimmed.Substring(2).Trim;
          { Strip surrounding quotes if present }
          if (Length(LValue) >= 2) and
             (CharInSet(LValue[1], ['"', ''''])) and
             (LValue[Length(LValue)] = LValue[1]) then
            LValue := Copy(LValue, 2, Length(LValue) - 2);
          if LValue <> '' then
            AList.Add(LValue);
        end
        else if (LTrimmed <> '') and not LTrimmed.StartsWith('#') then
          Break;  // non-indented non-comment line ends the block
      end;

      Inc(I);
    end;
  finally
    LLines.Free;
  end;
end;

procedure TContentTree.ParseAlbumIndex(const AFolder, ARelPath: string;
                                       AAlbum: TAlbumMeta);
var
  LFrontmatter: string;
  LDoc:         IYAMLDocument;
  LMap:         IYAMLMapping;
  LValue:       IYAMLValue;
begin
  AAlbum.ContentPath := AFolder;
  AAlbum.RelPath     := ARelPath;

  LFrontmatter := ExtractFrontmatter(TPath.Combine(AFolder, '_index.md'));
  if LFrontmatter.Trim.IsEmpty then
    Exit;

  LDoc := TYAML.LoadFromString(LFrontmatter);
  if not LDoc.IsMapping then
    Exit;

  LMap := LDoc.AsMapping;

  AAlbum.Title       := LMap.S['title'];
  AAlbum.Description := LMap.S['description'];
  AAlbum.AlbumThumb  := LMap.S['albumthumb'];
  AAlbum.Draft       := LMap.B['draft'];
  AAlbum.Weight      := LMap.I['weight'];

  { Date — stored as a timestamp scalar }
  if LMap.ContainsKey('date') and not LMap['date'].IsNull then
  try
    AAlbum.Date := LMap['date'].AsLocalDateTime;
  except
    AAlbum.Date := 0;
  end;

  { Tags — inline [a, b] or block list }
  if LMap.ContainsKey('tags') then
  begin
    LValue := LMap['tags'];
    if LValue.IsSequence then
      SeqToList(LValue.AsSequence, AAlbum.Tags);
  end;

  { Locations }
  if LMap.ContainsKey('locations') then
  begin
    LValue := LMap['locations'];
    if LValue.IsSequence then
      SeqToList(LValue.AsSequence, AAlbum.Locations);
  end;

  { Resources — read directly from raw lines to avoid VSoft.YAML's lexer
    stripping underscores from filenames it mis-identifies as numeric literals
    (YAML 1.1 treats underscore as a digit separator in integer patterns). }
  ReadResourcesFromFile(TPath.Combine(AFolder, '_index.md'), AAlbum.Resources);
end;

procedure TContentTree.ParseCategoryIndex(const AFolder, ARelPath: string;
                                          ACategory: TCategoryMeta);
var
  LFrontmatter: string;
  LDoc:         IYAMLDocument;
  LMap:         IYAMLMapping;
begin
  ACategory.ContentPath := AFolder;
  ACategory.RelPath     := ARelPath;

  LFrontmatter := ExtractFrontmatter(TPath.Combine(AFolder, '_index.md'));
  if LFrontmatter.Trim.IsEmpty then
    Exit;

  LDoc := TYAML.LoadFromString(LFrontmatter);
  if not LDoc.IsMapping then
    Exit;

  LMap := LDoc.AsMapping;

  ACategory.Title       := LMap.S['title'];
  ACategory.Description := LMap.S['description'];
  ACategory.AlbumThumb  := LMap.S['albumthumb'];
  ACategory.Draft       := LMap.B['draft'];
  ACategory.Weight      := LMap.I['weight'];
end;

procedure TContentTree.LoadCategory(const ACategoryFolder: string;
                                    ACategories: TCategories);
var
  LCatRelPath: string;
  LCategory:   TCategoryMeta;
  LAlbumDirs:  TArray<string>;
  LAlbumDir:   string;
  LRelPath:    string;
  LAlbum:      TAlbumMeta;
begin
  LCatRelPath := TPath.GetFileName(ACategoryFolder);

  LCategory := TCategoryMeta.Create;
  ParseCategoryIndex(ACategoryFolder, LCatRelPath, LCategory);

  if LCategory.Draft then
  begin
    LCategory.Free;
    Exit;
  end;

  { Walk album subdirectories (one level deep) }
  LAlbumDirs := TDirectory.GetDirectories(ACategoryFolder);
  for LAlbumDir in LAlbumDirs do
  begin
    if not TFile.Exists(TPath.Combine(LAlbumDir, '_index.md')) then
      Continue;

    LRelPath := LCatRelPath + '/' + TPath.GetFileName(LAlbumDir);
    LAlbum   := TAlbumMeta.Create;
    ParseAlbumIndex(LAlbumDir, LRelPath, LAlbum);

    if LAlbum.Draft or (LAlbum.Resources.Count = 0) then
      LAlbum.Free
    else
      LCategory.Albums.Add(LAlbum);
  end;

  { Keep the category even if all albums are draft — the page is still valid }
  ACategories.Add(LCategory);
end;

procedure TContentTree.Load(const AContentPath: string);
var
  LRootIndex:   string;
  LFrontmatter: string;
  LDoc:         IYAMLDocument;
  LCategoryDirs: TArray<string>;
  LCategoryDir:  string;
begin
  FCategories.Clear;

  { Root _index.md — only the description is used (goes in the footer) }
  LRootIndex   := TPath.Combine(AContentPath, '_index.md');
  LFrontmatter := ExtractFrontmatter(LRootIndex);
  if not LFrontmatter.Trim.IsEmpty then
  begin
    LDoc := TYAML.LoadFromString(LFrontmatter);
    if LDoc.IsMapping then
      FSiteDescription := LDoc.AsMapping.S['description'];
  end;

  { One subdirectory = one category }
  LCategoryDirs := TDirectory.GetDirectories(AContentPath);
  for LCategoryDir in LCategoryDirs do
  begin
    if not TFile.Exists(TPath.Combine(LCategoryDir, '_index.md')) then
      Continue;
    LoadCategory(LCategoryDir, FCategories);
  end;

  { Sort categories by weight ascending, then alphabetically by title }
  FCategories.Sort(
    TComparer<TCategoryMeta>.Construct(
      function(const A, B: TCategoryMeta): Integer
      begin
        Result := A.Weight - B.Weight;
        if Result = 0 then
          Result := CompareText(A.Title, B.Title);
      end));

  { Sort albums within each category the same way }
  var LCat: TCategoryMeta;
  for LCat in FCategories do
    LCat.Albums.Sort(
      TComparer<TAlbumMeta>.Construct(
        function(const A, B: TAlbumMeta): Integer
        begin
          Result := A.Weight - B.Weight;
          if Result = 0 then
            Result := CompareText(A.Title, B.Title);
        end));
end;

end.
