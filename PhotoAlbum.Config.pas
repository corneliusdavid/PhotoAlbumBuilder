unit PhotoAlbum.Config;

{ Reads config.toml and command-line arguments.
  Owns a TSiteData instance populated from the TOML file.
  Also carries build settings (paths, thumb dimensions, column count). }

interface

uses
  System.SysUtils,
  PhotoAlbum.StencilData;

type
  TAppConfig = class
  private
    FContentPath:   string;
    FAssetsPath:    string;
    FOutputPath:    string;
    FConfigPath:    string;
    FThemePath:     string;
    FDryRun:        Boolean;
    FForceRebuild:  Boolean;
    FThumbWidth:    Integer;
    FThumbQuality:  Integer;
    FColumnCount:   Integer;
    FSiteData:      TSiteData;

    procedure SetDefaults;
    procedure ParseCommandLine;
    procedure LoadToml;
  public
    constructor Create;
    destructor  Destroy; override;

    { Call once at startup. Raises on missing config or bad args. }
    procedure Initialize;

    property ContentPath:  string    read FContentPath;
    property AssetsPath:   string    read FAssetsPath;
    property OutputPath:   string    read FOutputPath;
    property ConfigPath:   string    read FConfigPath;
    property ThemePath:    string    read FThemePath;
    property DryRun:       Boolean   read FDryRun;
    property ForceRebuild: Boolean   read FForceRebuild;
    property ThumbWidth:   Integer   read FThumbWidth;
    property ThumbQuality: Integer   read FThumbQuality;
    property ColumnCount:  Integer   read FColumnCount;
    property SiteData:     TSiteData read FSiteData;
  end;

implementation

uses
  System.IOUtils,
  System.Classes;

{ ── Minimal TOML value stripper ─────────────────────────────────────────── }

{ Removes surrounding quotes (single or double) from a TOML scalar.
  Returns empty string for inline arrays/tables — we don't need those. }
function TomlScalar(const ARaw: string): string;
var
  S: string;
begin
  S := ARaw.Trim;
  if S.IsEmpty then
    Exit('');
  if S.StartsWith('[') or S.StartsWith('{') then
    Exit('');  // inline collection — not needed at config level
  if (Length(S) >= 2) and
     (CharInSet(S[1], ['"', ''''])) and
     (S[Length(S)] = S[1]) then
    Exit(Copy(S, 2, Length(S) - 2));
  Result := S;
end;

{ ── Section identity ─────────────────────────────────────────────────────── }

type
  TSection = (
    secRoot,
    secAuthor,
    secParams,
    secParamsAuthor,
    secParamsFooterParagraph,
    secParamsFooterContact,
    secParamsFooterCopyright,
    secParamsHeaderLink,      // inside a [[params.header.links]] entry
    secParamsSocialLink,      // inside a [[params.footer.social.links]] entry
    secOther                  // any other section we don't care about
  );

function ClassifySection(const ASectionKey: string): TSection;
var
  K: string;
begin
  K := ASectionKey.ToLower;
  if K = 'author'                      then Exit(secAuthor);
  if K = 'params'                      then Exit(secParams);
  if K = 'params.author'               then Exit(secParamsAuthor);
  if K = 'params.footer.paragraph'     then Exit(secParamsFooterParagraph);
  if K = 'params.footer.contact'       then Exit(secParamsFooterContact);
  if K = 'params.footer.copyright'     then Exit(secParamsFooterCopyright);
  Result := secOther;
end;

{ ── TAppConfig ───────────────────────────────────────────────────────────── }

constructor TAppConfig.Create;
begin
  inherited;
  FSiteData     := TSiteData.Create;
  FThumbWidth   := 350;
  FThumbQuality := 75;
  FColumnCount  := 3;
end;

destructor TAppConfig.Destroy;
begin
  FSiteData.Free;
  inherited;
end;

procedure TAppConfig.SetDefaults;
var
  LBase: string;
begin
  { Default paths relative to the executable location }
  LBase        := TPath.GetDirectoryName(TPath.GetFullPath(ParamStr(0)));
  FConfigPath  := TPath.Combine(LBase, 'WebFramework\config.toml');
  FContentPath := TPath.Combine(LBase, 'WebFramework\content');
  FAssetsPath  := 'E:\web\www.corneliusconcepts.pictures\assets';
  FThemePath   := TPath.Combine(LBase, 'WebFramework\themes\autophugo');
  FOutputPath  := TPath.Combine(LBase, 'output');
end;

procedure TAppConfig.ParseCommandLine;
var
  I: Integer;
  LArg: string;
begin
  I := 1;
  while I <= ParamCount do
  begin
    LArg := ParamStr(I).ToLower;
    if (LArg = '--content') and (I < ParamCount) then
    begin
      Inc(I);
      FContentPath := ParamStr(I);
    end
    else if (LArg = '--assets') and (I < ParamCount) then
    begin
      Inc(I);
      FAssetsPath := ParamStr(I);
    end
    else if (LArg = '--theme') and (I < ParamCount) then
    begin
      Inc(I);
      FThemePath := ParamStr(I);
    end
    else if (LArg = '--output') and (I < ParamCount) then
    begin
      Inc(I);
      FOutputPath := ParamStr(I);
    end
    else if (LArg = '--config') and (I < ParamCount) then
    begin
      Inc(I);
      FConfigPath := ParamStr(I);
    end
    else if LArg = '--dry-run' then
      FDryRun := True
    else if LArg = '--force' then
      FForceRebuild := True;
    Inc(I);
  end;
end;

procedure TAppConfig.LoadToml;
var
  LLines:       TStringList;
  LLine:        string;
  LTrimmed:     string;
  LSection:     TSection;
  LCurrentLink: TLinkItem;
  LKey:         string;
  LValue:       string;
  LEqPos:       Integer;
  LSectionKey:  string;
begin
  if not TFile.Exists(FConfigPath) then
    raise Exception.CreateFmt('Config file not found: %s', [FConfigPath]);

  LLines       := TStringList.Create;
  LSection     := secRoot;
  LCurrentLink := nil;
  try
    LLines.LoadFromFile(FConfigPath, TEncoding.UTF8);

    for LLine in LLines do
    begin
      LTrimmed := LLine.Trim;

      if LTrimmed.IsEmpty or LTrimmed.StartsWith('#') then
        Continue;

      { ── Array-of-tables header [[...]] ─────────────────────────────── }
      if LTrimmed.StartsWith('[[') then
      begin
        LSectionKey := LTrimmed.TrimLeft(['[']).TrimRight([']']).Trim.ToLower;
        LCurrentLink := TLinkItem.Create;
        if LSectionKey = 'params.header.links' then
        begin
          LSection := secParamsHeaderLink;
          FSiteData.HeaderLinks.Add(LCurrentLink);
        end
        else if LSectionKey = 'params.footer.social.links' then
        begin
          LSection := secParamsSocialLink;
          FSiteData.SocialLinks.Add(LCurrentLink);
        end
        else
        begin
          LCurrentLink.Free;
          LCurrentLink := nil;
          LSection := secOther;
        end;
        Continue;
      end;

      { ── Section header [...] ────────────────────────────────────────── }
      if LTrimmed.StartsWith('[') then
      begin
        LCurrentLink := nil;
        LSectionKey  := LTrimmed.TrimLeft(['[']).TrimRight([']']).Trim;
        LSection     := ClassifySection(LSectionKey);
        Continue;
      end;

      { ── Key = value ─────────────────────────────────────────────────── }
      LEqPos := LTrimmed.IndexOf('=');
      if LEqPos < 1 then
        Continue;

      LKey   := LTrimmed.Substring(0, LEqPos).Trim.ToLower;
      LValue := TomlScalar(LTrimmed.Substring(LEqPos + 1));

      case LSection of

        secRoot:
          if LKey = 'title' then
            FSiteData.Title := LValue;

        secAuthor, secParamsAuthor:
          if LKey = 'name' then
            FSiteData.AuthorName := LValue;

        secParams:
          if      LKey = 'description'  then FSiteData.Description := LValue
          else if LKey = 'robots_tags'  then FSiteData.RobotsTags  := LValue
          else if LKey = 'thumb_width'  then FThumbWidth  := StrToIntDef(LValue, FThumbWidth)
          else if LKey = 'thumb_quality' then FThumbQuality := StrToIntDef(LValue, FThumbQuality)
          else if LKey = 'column_count' then FColumnCount := StrToIntDef(LValue, FColumnCount)
          else if LKey = 'theme_path'   then FThemePath   := LValue;

        secParamsFooterParagraph:
          if LKey = 'headline' then
            FSiteData.FooterHeadline := LValue;

        secParamsFooterContact:
          if      LKey = 'formspreeid'  then FSiteData.FormspreeID     := LValue
          else if LKey = 'headline'     then FSiteData.ContactHeadline := LValue
          else if LKey = 'buttontext'   then FSiteData.ContactButton   := LValue
          else if LKey = 'resettext'    then FSiteData.ContactReset    := LValue;

        secParamsFooterCopyright:
          if LKey = 'name' then
            FSiteData.CopyrightName := LValue;

        secParamsHeaderLink:
          if LCurrentLink <> nil then
          begin
            if      LKey = 'name' then LCurrentLink.Name := LValue
            else if LKey = 'url'  then LCurrentLink.URL  := LValue
            else if LKey = 'icon' then LCurrentLink.Icon := LValue;
          end;

        secParamsSocialLink:
          if LCurrentLink <> nil then
          begin
            { social links use "label" not "name" in config.toml }
            if      LKey = 'label' then LCurrentLink.Name := LValue
            else if LKey = 'url'   then LCurrentLink.URL  := LValue
            else if LKey = 'icon'  then LCurrentLink.Icon := LValue;
          end;

      end; { case }
    end; { for }

  finally
    LLines.Free;
  end;
end;

procedure TAppConfig.Initialize;
begin
  SetDefaults;
  ParseCommandLine;
  LoadToml;
end;

end.
