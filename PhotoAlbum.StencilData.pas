unit PhotoAlbum.StencilData;

{ Data model classes registered with TWebStencilsProcessor.
  All properties accessed by templates must be published.
  Collections use typed TObjectList subclasses so WebStencils RTTI
  can locate GetEnumerator on a concrete (non-generic) type. }

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type

  // ── Shared primitives ─────────────────────────────────────────────────────

  TLinkItem = class
  private
    FName: string;
    FURL:  string;
    FIcon: string;
  public
    property Name: string read FName write FName;
    property URL:  string read FURL  write FURL;
    property Icon: string read FIcon write FIcon;
  end;

  TLinkItems = class(TObjectList<TLinkItem>);

  TBreadcrumb = class
  private
    FTitle:  string;
    FURL:    string;
    FIsLink: Boolean;
  public
    property Title:  string  read FTitle  write FTitle;
    property URL:    string  read FURL    write FURL;
    property IsLink: Boolean read FIsLink write FIsLink;
  end;

  TBreadcrumbs = class(TObjectList<TBreadcrumb>);

  TTermItem = class
  private
    FName: string;
    FSlug: string;
  public
    property Name: string read FName write FName;
    property Slug: string read FSlug write FSlug;
  end;

  TTermItems = class(TObjectList<TTermItem>);

  // ── Site-wide data (registered as "site" on every render) ─────────────────

  TSiteData = class
  private
    FTitle:           string;
    FAuthorName:      string;
    FDescription:     string;
    FRobotsTags:      string;
    FFormspreeID:     string;
    FFooterHeadline:  string;
    FContactHeadline: string;
    FContactButton:   string;
    FContactReset:    string;
    FCopyrightName:   string;
    FHeaderLinks:     TLinkItems;
    FSocialLinks:     TLinkItems;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Title:           string     read FTitle           write FTitle;
    property AuthorName:      string     read FAuthorName      write FAuthorName;
    property Description:     string     read FDescription     write FDescription;
    property RobotsTags:      string     read FRobotsTags      write FRobotsTags;
    property FormspreeID:     string     read FFormspreeID     write FFormspreeID;
    property FooterHeadline:  string     read FFooterHeadline  write FFooterHeadline;
    property ContactHeadline: string     read FContactHeadline write FContactHeadline;
    property ContactButton:   string     read FContactButton   write FContactButton;
    property ContactReset:    string     read FContactReset    write FContactReset;
    property CopyrightName:   string     read FCopyrightName   write FCopyrightName;
    property HeaderLinks:     TLinkItems read FHeaderLinks;
    property SocialLinks:     TLinkItems read FSocialLinks;
  end;

  // ── Page-level base (registered as "page" on every render) ────────────────

  TPageData = class
  private
    FTitle:          string;
    FDescription:    string;
    FHasDescription: Boolean;
    FHasTaxonomies:  Boolean;
    FBreadcrumbs:    TBreadcrumbs;
    FTags:           TTermItems;
    FLocations:      TTermItems;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure SetDescription(const AValue: string);
    procedure AddBreadcrumb(const ATitle, AURL: string);
    procedure AddCurrentCrumb(const ATitle: string);
    procedure AddTag(const AName: string);
    procedure AddLocation(const AName: string);
    procedure UpdateTaxonomyFlag;
  public
    property Title:          string       read FTitle write FTitle;
    property Description:    string       read FDescription;
    property HasDescription: Boolean      read FHasDescription;
    property HasTaxonomies:  Boolean      read FHasTaxonomies;
    property Breadcrumbs:    TBreadcrumbs read FBreadcrumbs;
    property Tags:           TTermItems   read FTags;
    property Locations:      TTermItems   read FLocations;
  end;

  // ── Card grid — used by index (categories) and category (albums) pages ────

  TCardItem = class
  private
    FTitle:    string;
    FURL:      string;
    FThumbURL: string;
  public
    property Title:    string read FTitle    write FTitle;
    property URL:      string read FURL      write FURL;
    property ThumbURL: string read FThumbURL write FThumbURL;
  end;

  TCardItems = class(TObjectList<TCardItem>);

  TCardColumn = class
  private
    FItems: TCardItems;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Items: TCardItems read FItems;
  end;

  TCardColumns = class(TObjectList<TCardColumn>);

  TCardsPageData = class(TPageData)
  private
    FColumns: TCardColumns;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Columns: TCardColumns read FColumns;
  end;

  // ── Photo grid — album pages ───────────────────────────────────────────────

  TPhotoItem = class
  private
    FThumbURL:    string;
    FFullURL:     string;
    FOrigName:    string;
    FID:          string;
    FPhotoTitle:  string;
    FDescription: string;
    FGalleryIndex: Integer;
    FHasTitle:    Boolean;
    FThumbH:      Integer;
  public
    procedure SetPhotoTitle(const AValue: string);
    property ThumbH: Integer read FThumbH write FThumbH;  // pixel height, for column balancing
  public
    property ThumbURL:     string  read FThumbURL    write FThumbURL;
    property FullURL:      string  read FFullURL     write FFullURL;
    property OrigName:     string  read FOrigName    write FOrigName;
    property ID:           string  read FID          write FID;
    property PhotoTitle:   string  read FPhotoTitle;
    property Description:  string  read FDescription write FDescription;
    property GalleryIndex: Integer read FGalleryIndex write FGalleryIndex;
    property HasTitle:     Boolean read FHasTitle;
  end;

  TPhotoItems = class(TObjectList<TPhotoItem>);

  TPhotoColumn = class
  private
    FPhotos: TPhotoItems;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Photos: TPhotoItems read FPhotos;
  end;

  TPhotoColumns = class(TObjectList<TPhotoColumn>);

  TAlbumPageData = class(TPageData)
  private
    FColumns: TPhotoColumns;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Columns: TPhotoColumns read FColumns;
  end;

  // ── Taxonomy index pages (tags/ and locations/) ───────────────────────────

  TTaxTerm = class
  private
    FName:    string;
    FSlug:    string;
    FColumns: TCardColumns;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Name:    string      read FName    write FName;
    property Slug:    string      read FSlug    write FSlug;
    property Columns: TCardColumns read FColumns;
  end;

  TTaxTerms = class(TObjectList<TTaxTerm>);

  TTaxonomyPageData = class(TPageData)
  private
    FTerms: TTaxTerms;
  public
    constructor Create;
    destructor  Destroy; override;
  public
    property Terms: TTaxTerms read FTerms;
  end;

// ── Per-page base URL prefix (registered as "base" on every render) ──────────

  { Provides root-relative prefix strings for use in templates, adjusted to the
    depth of the current page so the site can live in a sub-folder.
      depth 0 = site root (index.html, 404.html)
      depth 1 = category, tags/, locations/
      depth 2 = album
    Usage in templates:  href="@base.Assets/css/main.css"
                         href="@base.Root"
                         href="@base.Tags/"   }
  TBaseUrls = class
  private
    FRoot:      string;
    FAssets:    string;
    FTags:      string;
    FLocations: string;
  public
    constructor Create(ADepth: Integer);
    property Root:      string read FRoot;
    property Assets:    string read FAssets;
    property Tags:      string read FTags;
    property Locations: string read FLocations;
  end;

function Slugify(const AName: string): string;

implementation

uses
  System.Character;

{ TBaseUrls }

constructor TBaseUrls.Create(ADepth: Integer);
var
  LPrefix: string;
  I:       Integer;
begin
  inherited Create;
  LPrefix := '';
  for I := 1 to ADepth do
    LPrefix := LPrefix + '../';

  { Root href: '.' for depth 0, '..' for depth 1, '../..' for depth 2, … }
  if ADepth = 0 then
    FRoot := '.'
  else
    FRoot := LPrefix.TrimRight(['/']);

  FAssets    := LPrefix + 'assets';
  FTags      := LPrefix + 'tags';
  FLocations := LPrefix + 'locations';
end;

function Slugify(const AName: string): string;
var
  C: Char;
  LResult: TStringBuilder;
begin
  LResult := TStringBuilder.Create;
  try
    for C in AName.ToLower do
      if C.IsLetterOrDigit then
        LResult.Append(C)
      else if (LResult.Length > 0) and (LResult.Chars[LResult.Length - 1] <> '-') then
        LResult.Append('-');
    Result := LResult.ToString.TrimRight(['-']);
  finally
    LResult.Free;
  end;
end;

{ TSiteData }

constructor TSiteData.Create;
begin
  inherited;
  FHeaderLinks  := TLinkItems.Create(True);
  FSocialLinks  := TLinkItems.Create(True);
  FContactButton := 'Send';
  FContactReset  := 'Reset';
end;

destructor TSiteData.Destroy;
begin
  FHeaderLinks.Free;
  FSocialLinks.Free;
  inherited;
end;

{ TPageData }

constructor TPageData.Create;
begin
  inherited;
  FBreadcrumbs := TBreadcrumbs.Create(True);
  FTags        := TTermItems.Create(True);
  FLocations   := TTermItems.Create(True);
end;

destructor TPageData.Destroy;
begin
  FBreadcrumbs.Free;
  FTags.Free;
  FLocations.Free;
  inherited;
end;

procedure TPageData.SetDescription(const AValue: string);
begin
  FDescription    := AValue;
  FHasDescription := AValue.Trim <> '';
end;

procedure TPageData.AddBreadcrumb(const ATitle, AURL: string);
var
  LCrumb: TBreadcrumb;
begin
  LCrumb        := TBreadcrumb.Create;
  LCrumb.Title  := ATitle;
  LCrumb.URL    := AURL;
  LCrumb.IsLink := True;
  FBreadcrumbs.Add(LCrumb);
end;

procedure TPageData.AddCurrentCrumb(const ATitle: string);
var
  LCrumb: TBreadcrumb;
begin
  LCrumb        := TBreadcrumb.Create;
  LCrumb.Title  := ATitle;
  LCrumb.IsLink := False;
  FBreadcrumbs.Add(LCrumb);
end;

procedure TPageData.AddTag(const AName: string);
var
  LTerm: TTermItem;
begin
  LTerm      := TTermItem.Create;
  LTerm.Name := AName;
  LTerm.Slug := SlugIFY(AName);
  FTags.Add(LTerm);
end;

procedure TPageData.AddLocation(const AName: string);
var
  LTerm: TTermItem;
begin
  LTerm      := TTermItem.Create;
  LTerm.Name := AName;
  LTerm.Slug := SlugIFY(AName);
  FLocations.Add(LTerm);
end;

procedure TPageData.UpdateTaxonomyFlag;
begin
  FHasTaxonomies := (FTags.Count > 0) or (FLocations.Count > 0);
end;

{ TPhotoItem }

procedure TPhotoItem.SetPhotoTitle(const AValue: string);
begin
  FPhotoTitle := AValue;
  FHasTitle   := AValue.Trim <> '';
end;

{ TCardColumn }

constructor TCardColumn.Create;
begin
  inherited;
  FItems := TCardItems.Create(True);
end;

destructor TCardColumn.Destroy;
begin
  FItems.Free;
  inherited;
end;

{ TCardsPageData }

constructor TCardsPageData.Create;
begin
  inherited;
  FColumns := TCardColumns.Create(True);
end;

destructor TCardsPageData.Destroy;
begin
  FColumns.Free;
  inherited;
end;

{ TPhotoColumn }

constructor TPhotoColumn.Create;
begin
  inherited;
  FPhotos := TPhotoItems.Create(True);
end;

destructor TPhotoColumn.Destroy;
begin
  FPhotos.Free;
  inherited;
end;

{ TAlbumPageData }

constructor TAlbumPageData.Create;
begin
  inherited;
  FColumns := TPhotoColumns.Create(True);
end;

destructor TAlbumPageData.Destroy;
begin
  FColumns.Free;
  inherited;
end;

{ TTaxTerm }

constructor TTaxTerm.Create;
begin
  inherited;
  FColumns := TCardColumns.Create(True);
end;

destructor TTaxTerm.Destroy;
begin
  FColumns.Free;
  inherited;
end;

{ TTaxonomyPageData }

constructor TTaxonomyPageData.Create;
begin
  inherited;
  FTerms := TTaxTerms.Create(True);
end;

destructor TTaxonomyPageData.Destroy;
begin
  FTerms.Free;
  inherited;
end;

end.
