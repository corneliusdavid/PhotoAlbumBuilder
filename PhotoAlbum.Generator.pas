unit PhotoAlbum.Generator;

{ Site generator — orchestrates the full build pipeline:
    1. Load incremental manifest
    2. Walk content tree; for stale albums: generate images + HTML
    3. Rebuild index pages (root, categories, taxonomies, 404) every run
    4. Save manifest

  URL conventions (all relative to the output folder — site is subfolder-safe):
    Thumbnails : thumbs/<filename>              (relative, from album page)
    Originals  : <filename>                     (relative, same folder as HTML)
    Album page : <album-slug>/                  (relative, from category page)
    Category   : <category-slug>/               (relative, from root)
    Tags index : tags/                          (relative, from root)
    Locations  : locations/                     (relative, from root)
    Assets     : assets/… or ../assets/… etc.  (via @base.Assets in templates)

  TBaseUrls (registered as "base") supplies depth-adjusted prefix strings so
  templates can write href="@base.Assets/css/main.css" and get the correct
  relative path regardless of the page's nesting level (0, 1, or 2). }

interface

uses
  PhotoAlbum.Config,
  PhotoAlbum.Content;

type
  TGenerator = class
  private
    FConfig:        TAppConfig;
    FTree:          TContentTree;
    FTemplatesPath: string;

    { Render a template and return the HTML string.
      ADepth: 0 = root / 404, 1 = category / taxonomy, 2 = album. }
    function RenderPage(const ATemplateName: string;
                        APage: TObject; ADepth: Integer): string;

    { Write HTML to OutputPath\ARelPath, creating directories as needed.
      Skipped entirely when DryRun is True. }
    procedure WriteHtml(const ARelPath, AHtml: string);

    { URL helpers — relative paths for use inside album pages. }
    function ThumbUrl(const AFilename: string): string;
    function FullUrl(const AFilename:  string): string;

    { Filesystem paths where generated image files are written. }
    function ThumbDest(const ARelPath, AFilename: string): string;
    function OrigDest(const ARelPath,  AFilename: string): string;

    { Cover thumbnail URL for a card, relative to AFromRelPath (the page dir).
      e.g. from "beach" to album "beach/cannon-beach-2010" → "cannon-beach-2010/thumbs/cover.jpg"
           from ""      to album "beach/cannon-beach-2010" → "beach/cannon-beach-2010/thumbs/cover.jpg" }
    function AlbumCoverThumbUrl(AAlbum: TAlbumMeta;
                                const AFromRelPath: string): string;

    { Copies CSS/JS/font files from the Hugo theme into output\assets\.
      Only called when --force is set. }
    procedure CopyStaticAssets;

    { Page builders. }
    procedure BuildAlbum(ACat: TCategoryMeta; AAlbum: TAlbumMeta);
    procedure BuildCategoryPage(ACat: TCategoryMeta);
    procedure BuildRootPage;
    procedure BuildTaxonomyPages;
    procedure Build404;
  public
    constructor Create(AConfig: TAppConfig; ATree: TContentTree);
    procedure Run;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Web.Stencils,
  PhotoAlbum.StencilData,
  PhotoAlbum.Images,
  PhotoAlbum.Manifest,
  PhotoAlbum.Columns;

{ ── URL / path helpers ───────────────────────────────────────────────────── }

function TGenerator.ThumbUrl(const AFilename: string): string;
begin
  Result := 'thumbs/' + AFilename;
end;

function TGenerator.FullUrl(const AFilename: string): string;
begin
  Result := AFilename;
end;

function TGenerator.ThumbDest(const ARelPath, AFilename: string): string;
begin
  Result := TPath.Combine(FConfig.OutputPath,
              TPath.Combine(ARelPath.Replace('/', TPath.DirectorySeparatorChar),
                TPath.Combine('thumbs', AFilename)));
end;

function TGenerator.OrigDest(const ARelPath, AFilename: string): string;
begin
  Result := TPath.Combine(FConfig.OutputPath,
              TPath.Combine(ARelPath.Replace('/', TPath.DirectorySeparatorChar),
                AFilename));
end;

{ ── Static asset copy ────────────────────────────────────────────────────── }

procedure TGenerator.CopyStaticAssets;

  { Copy every file in ASrcDir into ADestDir, creating ADestDir if needed.
    Does NOT recurse into sub-directories — add explicit calls for sub-dirs. }
  procedure CopyDir(const ASrcDir, ADestDir: string);
  var
    LFiles: TArray<string>;
    LFile:  string;
    LDest:  string;
  begin
    if not TDirectory.Exists(ASrcDir) then
    begin
      Writeln('  warning: source not found: ', ASrcDir);
      Exit;
    end;
    TDirectory.CreateDirectory(ADestDir);
    LFiles := TDirectory.GetFiles(ASrcDir);
    for LFile in LFiles do
    begin
      LDest := TPath.Combine(ADestDir, TPath.GetFileName(LFile));
      TFile.Copy(LFile, LDest, {overwrite=}True);
    end;
    Writeln('  copied ', Length(LFiles), ' file(s): ', ADestDir);
  end;

var
  LTheme:  string;
  LOut:    string;
begin
  LTheme := FConfig.ThemePath;
  LOut   := TPath.Combine(FConfig.OutputPath, 'assets');

  Writeln('Copying static theme assets...');

  { CSS }
  CopyDir(TPath.Combine(LTheme, TPath.Combine('assets', 'css')),
          TPath.Combine(LOut, 'css'));

  { JS }
  CopyDir(TPath.Combine(LTheme, TPath.Combine('assets', 'js')),
          TPath.Combine(LOut, 'js'));

  { FontAwesome + other root-level webfonts }
  CopyDir(TPath.Combine(LTheme, TPath.Combine('static', 'fonts')),
          TPath.Combine(LOut, 'fonts'));

  { Source Sans Pro TrueType subset }
  CopyDir(TPath.Combine(LTheme, TPath.Combine('static', TPath.Combine('fonts', 'ssp'))),
          TPath.Combine(LOut, TPath.Combine('fonts', 'ssp')));

  { Category icons (gallery_icons/ under AssetsPath → assets/icons/) }
  CopyDir(TPath.Combine(FConfig.AssetsPath, 'gallery_icons'),
          TPath.Combine(LOut, 'icons'));
end;

{ Returns a relative URL from AFromDir (the page's directory, forward-slash,
  no trailing slash, empty string for root) to AToPath (forward-slash target). }
function RelativeUrl(const AFromDir, AToPath: string): string;
var
  LFrom:    TArray<string>;
  LTo:      TArray<string>;
  LCommon:  Integer;
  I:        Integer;
  LResult:  TStringBuilder;
begin
  if AFromDir = '' then
    Exit(AToPath);

  LFrom   := AFromDir.Split(['/']);
  LTo     := AToPath.Split(['/']);
  LCommon := 0;
  while (LCommon < Length(LFrom)) and (LCommon < Length(LTo)) and
        SameText(LFrom[LCommon], LTo[LCommon]) do
    Inc(LCommon);

  LResult := TStringBuilder.Create;
  try
    { Go up from the page's directory to the common ancestor }
    for I := LCommon to High(LFrom) do
    begin
      if LResult.Length > 0 then LResult.Append('/');
      LResult.Append('..');
    end;
    { Then descend to the target }
    for I := LCommon to High(LTo) do
    begin
      if LResult.Length > 0 then LResult.Append('/');
      LResult.Append(LTo[I]);
    end;
    Result := LResult.ToString;
  finally
    LResult.Free;
  end;
end;

function TGenerator.AlbumCoverThumbUrl(AAlbum: TAlbumMeta;
                                       const AFromRelPath: string): string;
var
  LCover: string;
begin
  if AAlbum.AlbumThumb <> '' then
    LCover := AAlbum.AlbumThumb
  else if AAlbum.Resources.Count > 0 then
    LCover := AAlbum.Resources[0]
  else
    Exit('');

  { LCover may contain a subdirectory prefix from the YAML (e.g. "beach/img.jpg");
    strip it so the thumb path is always <relpath>/thumbs/<filename>. }
  Result := RelativeUrl(AFromRelPath,
                        AAlbum.RelPath + '/thumbs/' + TPath.GetFileName(LCover));
end;

{ ── Template rendering ───────────────────────────────────────────────────── }

function TGenerator.RenderPage(const ATemplateName: string;
                                APage: TObject; ADepth: Integer): string;
var
  LProc: TWebStencilsProcessor;
  LBase: TBaseUrls;
begin
  LBase := TBaseUrls.Create(ADepth);
  try
    LProc := TWebStencilsProcessor.Create(nil);
    try
      LProc.AddVar('site', FConfig.SiteData, False);
      LProc.AddVar('page', APage, False);
      LProc.AddVar('base', LBase, False);
      LProc.InputFileName := TPath.Combine(FTemplatesPath, ATemplateName);
      Result := LProc.Content;
    finally
      LProc.Free;
    end;
  finally
    LBase.Free;
  end;
end;

procedure TGenerator.WriteHtml(const ARelPath, AHtml: string);
var
  LFullPath: string;
begin
  LFullPath := TPath.Combine(FConfig.OutputPath, ARelPath);
  TDirectory.CreateDirectory(TPath.GetDirectoryName(LFullPath));
  if not FConfig.DryRun then
    TFile.WriteAllText(LFullPath, AHtml, TEncoding.UTF8);
end;

{ ── Album page ───────────────────────────────────────────────────────────── }

procedure TGenerator.BuildAlbum(ACat: TCategoryMeta; AAlbum: TAlbumMeta);
var
  LImages:     TImageProcessor;
  LFlatPhotos: TPhotoItems;
  LPhoto:      TPhotoItem;
  LPage:       TAlbumPageData;
  LFilename:   string;
  LSrcPath:    string;
  LThumbDest:  string;
  LThumbSize:  TThumbSize;
  LIndex:      Integer;
  LHtml:       string;
begin
  LImages     := TImageProcessor.Create(FConfig.ThumbWidth, FConfig.ThumbQuality);
  LFlatPhotos := TPhotoItems.Create(True);
  LPage       := TAlbumPageData.Create;
  try
    { ── Populate photo list ────────────────────────────────────────────── }
    LIndex := 0;
    for LFilename in AAlbum.Resources do
    begin
      Inc(LIndex);
      LSrcPath   := TPath.Combine(FConfig.AssetsPath,
                      TPath.Combine(
                        AAlbum.RelPath.Replace('/', TPath.DirectorySeparatorChar),
                        LFilename));
      LThumbDest := ThumbDest(AAlbum.RelPath, LFilename);

      if not FConfig.DryRun then
      begin
        LThumbSize := LImages.GenerateThumb(LSrcPath, LThumbDest);
        LImages.CopyOriginal(LSrcPath, OrigDest(AAlbum.RelPath, LFilename));
      end
      else
        LThumbSize := Default(TThumbSize);

      LPhoto              := TPhotoItem.Create;
      LPhoto.ThumbURL     := ThumbUrl(LFilename);
      LPhoto.FullURL      := FullUrl(LFilename);
      LPhoto.OrigName     := LFilename;
      LPhoto.ID           := 'photo-' + LIndex.ToString;
      LPhoto.GalleryIndex := LIndex;
      LPhoto.ThumbH       := LThumbSize.Height;
      LPhoto.SetPhotoTitle('');  // individual photos have no separate title
      LFlatPhotos.Add(LPhoto);
    end;

    { ── Page metadata ──────────────────────────────────────────────────── }
    LPage.Title := AAlbum.Title;
    LPage.SetDescription(AAlbum.Description);
    { Breadcrumb back to category page — relative from the album directory }
    LPage.AddBreadcrumb(ACat.Title,
                        RelativeUrl(AAlbum.RelPath, ACat.RelPath) + '/');
    LPage.AddCurrentCrumb(AAlbum.Title);

    var LTag: string;
    for LTag in AAlbum.Tags do
      LPage.AddTag(LTag);
    for LTag in AAlbum.Locations do
      LPage.AddLocation(LTag);
    LPage.UpdateTaxonomyFlag;

    { ── Distribute into columns ────────────────────────────────────────── }
    BalancePhotos(LPage, LFlatPhotos, FConfig.ColumnCount);

    { ── Render and write ───────────────────────────────────────────────── }
    LHtml := RenderPage('album.html', LPage, 2);
    WriteHtml(AAlbum.RelPath.Replace('/', TPath.DirectorySeparatorChar)
              + TPath.DirectorySeparatorChar + 'index.html', LHtml);

    Writeln('  built: ', AAlbum.RelPath);
  finally
    LFlatPhotos.Free;
    LPage.Free;
    LImages.Free;
  end;
end;

{ ── Category page (album grid) ───────────────────────────────────────────── }

procedure TGenerator.BuildCategoryPage(ACat: TCategoryMeta);
var
  LFlatCards: TCardItems;
  LCard:      TCardItem;
  LPage:      TCardsPageData;
  LHtml:      string;
begin
  LFlatCards := TCardItems.Create(True);
  LPage      := TCardsPageData.Create;
  try
    for var LAlbum in ACat.Albums do
    begin
      LCard          := TCardItem.Create;
      LCard.Title    := LAlbum.Title;
      { Relative from the category page dir to the album dir }
      LCard.URL      := RelativeUrl(ACat.RelPath, LAlbum.RelPath) + '/';
      LCard.ThumbURL := AlbumCoverThumbUrl(LAlbum, ACat.RelPath);
      LFlatCards.Add(LCard);
    end;

    LPage.Title := ACat.Title;
    LPage.SetDescription(ACat.Description);
    LPage.AddCurrentCrumb(ACat.Title);

    BalanceCards(LPage, LFlatCards, FConfig.ColumnCount);

    LHtml := RenderPage('cards.html', LPage, 1);
    WriteHtml(ACat.RelPath + TPath.DirectorySeparatorChar + 'index.html', LHtml);
  finally
    LFlatCards.Free;
    LPage.Free;
  end;
end;

{ ── Root index page (category grid) ─────────────────────────────────────── }

procedure TGenerator.BuildRootPage;
var
  LFlatCards: TCardItems;
  LCard:      TCardItem;
  LCat:       TCategoryMeta;
  LPage:      TCardsPageData;
  LHtml:      string;
begin
  LFlatCards := TCardItems.Create(True);
  LPage      := TCardsPageData.Create;
  try
    for LCat in FTree.Categories do
    begin
      { Category icon: albumthumb in the category _index.md is a path like
        "gallery_icons/noun-misc-512.png" — strip the directory and serve
        from assets/icons/.  Fall back to the first album's photo cover. }
      var LThumbUrl: string := '';
      if LCat.AlbumThumb <> '' then
        LThumbUrl := 'assets/icons/' + TPath.GetFileName(LCat.AlbumThumb)
      else if LCat.Albums.Count > 0 then
        LThumbUrl := AlbumCoverThumbUrl(LCat.Albums[0], '');

      LCard          := TCardItem.Create;
      LCard.Title    := LCat.Title;
      { From root (depth 0), category RelPath is already a simple relative slug }
      LCard.URL      := LCat.RelPath + '/';
      LCard.ThumbURL := LThumbUrl;
      LFlatCards.Add(LCard);
    end;

    LPage.Title := FConfig.SiteData.Title;
    LPage.SetDescription(FTree.SiteDescription);

    BalanceCards(LPage, LFlatCards, FConfig.ColumnCount);

    LHtml := RenderPage('cards.html', LPage, 0);
    WriteHtml('index.html', LHtml);
  finally
    LFlatCards.Free;
    LPage.Free;
  end;
end;

{ ── Taxonomy index pages ─────────────────────────────────────────────────── }

procedure TGenerator.BuildTaxonomyPages;
type
  TAlbumList = TList<TAlbumMeta>;
var
  LTagMap:   TObjectDictionary<string, TAlbumList>;
  LLocMap:   TObjectDictionary<string, TAlbumList>;
  LCat:      TCategoryMeta;
  LAlbum:    TAlbumMeta;
  LList:     TAlbumList;

  procedure IndexAlbum(AMap: TObjectDictionary<string, TAlbumList>;
                       ATerms: TStrings; AAlbum: TAlbumMeta);
  var
    LTerm: string;
  begin
    for LTerm in ATerms do
    begin
      if not AMap.TryGetValue(LTerm, LList) then
      begin
        LList := TAlbumList.Create;
        AMap.Add(LTerm, LList);
      end;
      LList.Add(AAlbum);
    end;
  end;

  procedure RenderTaxPage(AMap: TObjectDictionary<string, TAlbumList>;
                          const APageTitle, AOutputPath, ATaxRelPath: string);
  var
    LPage:     TTaxonomyPageData;
    LTerm:     TTaxTerm;
    LTermKey:  string;
    LAlbums:   TAlbumList;
    LFlatCards: TCardItems;
    LCard:     TCardItem;
    LHtml:     string;
  begin
    LPage := TTaxonomyPageData.Create;
    try
      LPage.Title := APageTitle;

      for LTermKey in AMap.Keys do
      begin
        LAlbums := AMap[LTermKey];
        LTerm        := TTaxTerm.Create;
        LTerm.Name   := LTermKey;
        LTerm.Slug   := Slugify(LTermKey);
        LPage.Terms.Add(LTerm);

        LFlatCards := TCardItems.Create(True);
        try
          for var LAlbum in LAlbums do
          begin
            LCard          := TCardItem.Create;
            LCard.Title    := LAlbum.Title;
            { Relative from the taxonomy page dir (e.g. 'tags') to the album }
            LCard.URL      := RelativeUrl(ATaxRelPath, LAlbum.RelPath) + '/';
            LCard.ThumbURL := AlbumCoverThumbUrl(LAlbum, ATaxRelPath);
            LFlatCards.Add(LCard);
          end;
          BalanceCards(LTerm, LFlatCards, FConfig.ColumnCount);
        finally
          LFlatCards.Free;
        end;
      end;

      LHtml := RenderPage('taxonomy.html', LPage, 1);
      WriteHtml(AOutputPath, LHtml);
    finally
      LPage.Free;
    end;
  end;

begin
  LTagMap := TObjectDictionary<string, TAlbumList>.Create([doOwnsValues]);
  LLocMap := TObjectDictionary<string, TAlbumList>.Create([doOwnsValues]);
  try
    for LCat in FTree.Categories do
      for LAlbum in LCat.Albums do
      begin
        IndexAlbum(LTagMap, LAlbum.Tags,      LAlbum);
        IndexAlbum(LLocMap, LAlbum.Locations, LAlbum);
      end;

    RenderTaxPage(LTagMap, 'Tags',      'tags'      + TPath.DirectorySeparatorChar + 'index.html', 'tags');
    RenderTaxPage(LLocMap, 'Locations', 'locations' + TPath.DirectorySeparatorChar + 'index.html', 'locations');
  finally
    LTagMap.Free;
    LLocMap.Free;
  end;
end;

{ ── 404 page ─────────────────────────────────────────────────────────────── }

procedure TGenerator.Build404;
var
  LPage: TPageData;
  LHtml: string;
begin
  LPage := TPageData.Create;
  try
    LPage.Title := 'Page Not Found';
    LHtml := RenderPage('404.html', LPage, 0);
    WriteHtml('404.html', LHtml);
  finally
    LPage.Free;
  end;
end;

{ ── TGenerator ───────────────────────────────────────────────────────────── }

constructor TGenerator.Create(AConfig: TAppConfig; ATree: TContentTree);
begin
  inherited Create;
  FConfig        := AConfig;
  FTree          := ATree;
  FTemplatesPath := TPath.Combine(
                      TPath.GetDirectoryName(
                        TPath.GetFullPath(ParamStr(0))),
                      'templates');
end;

procedure TGenerator.Run;
var
  LManifest:    TBuildManifest;
  LCat:         TCategoryMeta;
  LSourceMtime: TDateTime;
  LNeedsRebuild: Boolean;
begin
  LManifest := TBuildManifest.Create;
  try
    LManifest.Load(TPath.Combine(FConfig.OutputPath, '.manifest.json'));
    LManifest.PurgeAbsent(FTree.Categories);

    { ── Static theme assets (CSS/JS/fonts) — only on --force ────────────── }
    if FConfig.ForceRebuild and not FConfig.DryRun then
      CopyStaticAssets;

    { ── Album pages + image generation ─────────────────────────────────── }
    for LCat in FTree.Categories do
      for var LAlbum in LCat.Albums do
      begin
        LSourceMtime  := AlbumSourceModified(LAlbum, FConfig.AssetsPath);
        LNeedsRebuild := FConfig.ForceRebuild or
                         LManifest.NeedsRebuild(LAlbum.RelPath, LSourceMtime);
        if LNeedsRebuild then
        begin
          BuildAlbum(LCat, LAlbum);
          if not FConfig.DryRun then
            LManifest.MarkBuilt(LAlbum.RelPath, LSourceMtime);
        end
        else
          Writeln('  skipped (current): ', LAlbum.RelPath);
      end;

    { ── Index pages — always regenerated (fast, no image I/O) ──────────── }
    Writeln('Building index pages...');
    BuildRootPage;
    for LCat in FTree.Categories do
      BuildCategoryPage(LCat);
    BuildTaxonomyPages;
    Build404;

    if not FConfig.DryRun then
      LManifest.Save;
    Writeln('Done.');
  finally
    LManifest.Free;
  end;
end;

end.
