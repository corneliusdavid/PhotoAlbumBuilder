program PhotoAlbumBuilder;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  PhotoAlbum.StencilData in 'PhotoAlbum.StencilData.pas',
  PhotoAlbum.Config      in 'PhotoAlbum.Config.pas',
  PhotoAlbum.Content     in 'PhotoAlbum.Content.pas',
  PhotoAlbum.Images      in 'PhotoAlbum.Images.pas',
  PhotoAlbum.Manifest    in 'PhotoAlbum.Manifest.pas',
  PhotoAlbum.Columns     in 'PhotoAlbum.Columns.pas',
  PhotoAlbum.Generator   in 'PhotoAlbum.Generator.pas';

procedure PrintUsage;
begin
  Writeln('Usage: PhotoAlbumBuilder [options]');
  Writeln;
  Writeln('Options:');
  Writeln('  --config    <path>  Path to config.toml  (default: .\config.toml)');
  Writeln('  --content   <path>  Path to content root (default: .\content)');
  Writeln('  --assets    <path>  Path to photo assets (default: .\assets)');
  Writeln('  --theme     <path>  Hugo theme root      (default: .\themes\autophugo)');
  Writeln('  --templates <path>  HTML template root   (default: .\templates)');
  Writeln('  --output    <path>  Output directory     (default: .\output)');
  Writeln('  --force            Rebuild all pages + copy static assets (CSS/JS/fonts)');
  Writeln('  --dry-run          Parse and plan without writing any files');
end;

var
  Config:    TAppConfig;
  Tree:      TContentTree;
  Generator: TGenerator;
begin
  try
    if (ParamCount > 0) and (ParamStr(1).ToLower = '--help') then
    begin
      PrintUsage;
      Readln;
      Exit;
    end;

    Config := TAppConfig.Create;
    Tree   := TContentTree.Create;
    try
      Config.Initialize;

      Writeln('PhotoAlbumBuilder');
      Writeln(StringOfChar('-', 40));
      Writeln('Site title : ', Config.SiteData.Title);
      Writeln('Content    : ', Config.ContentPath);
      Writeln('Assets     : ', Config.AssetsPath);
      Writeln('Theme      : ', Config.ThemePath);
      Writeln('Templates  : ', Config.TemplatesPath);
      Writeln('Output     : ', Config.OutputPath);
      Writeln('Thumb      : ', Config.ThumbWidth, 'px @ ', Config.ThumbQuality, '%');
      Writeln('Columns    : ', Config.ColumnCount);
      Writeln('Dry run    : ', BoolToStr(Config.DryRun, True));
      Writeln('Force      : ', BoolToStr(Config.ForceRebuild, True));
      Writeln(StringOfChar('-', 40));

      Writeln('Loading content tree...');
      Tree.Load(Config.ContentPath);
      Writeln('Categories : ', Tree.Categories.Count);
      var LAlbumTotal := 0;
      var LCat: TCategoryMeta;
      for LCat in Tree.Categories do
        Inc(LAlbumTotal, LCat.Albums.Count);
      Writeln('Albums     : ', LAlbumTotal);
      Writeln(StringOfChar('-', 40));

      Generator := TGenerator.Create(Config, Tree);
      try
        Generator.Run;
      finally
        Generator.Free;
      end;
    finally
      Tree.Free;
      Config.Free;
    end;

  except
    on E: Exception do
    begin
      Writeln('Error: ', E.Message);
      Writeln;
      PrintUsage;
      ExitCode := 1;
    end;
  end;
end.
