# PhotoAlbumBuilder

A fast, incremental static site generator for family photo albums, written in Delphi.  
Built as a replacement for a Hugo-based photo site that had grown to 26,000 files and multi-hour build times.

> Note: Except for this paragraph, the entire application and this README were written by Claude Code with very few corrections (used `published` instead of `public` in project-level classes; didn't use `CharInSet` for checking characters in a set; remove `inline` in a couple of places).

---

## Features

- **Incremental builds** — a JSON manifest tracks source modification times; only albums whose photos have changed are rebuilt
- **Fast image processing** — generates exactly two output images per photo (a resized thumbnail and a full-size copy), compared to the seven variants Hugo's image pipeline produced
- **WebStencils templates** — uses the Delphi 13.1 Florence template engine for HTML generation; templates are plain HTML files with `@` expressions
- **Masonry column layout** — photos and album cards are distributed across columns using a shortest-column greedy algorithm based on actual image pixel heights
- **Taxonomy pages** — automatically builds `/tags/` and `/locations/` index pages from album metadata
- **Fully relative URLs** — every `href` and `src` in the generated HTML is relative, so the site can be deployed in a sub-folder of any domain
- **Hugo content compatibility** — reads existing Hugo `_index.md` front matter (TOML config + YAML content) without modification
- **Cross-platform goal** — image processing uses Skia4Delphi, which targets both Windows and Linux

---

## Requirements

| Requirement | Notes |
|---|---|
| RAD Studio 13.1 Florence (Delphi 12.1+) | Uses WebStencils and Skia4Delphi, both bundled with Florence |
| [VSoft.YAML](https://github.com/VSoftTechnologies/VSoft.YAML) | YAML front matter parsing; add to your library path |
| Hugo theme (autophugo or similar) | Provides the CSS, JS, and web fonts copied to the output |

---

## Content Structure

PhotoAlbumBuilder expects a two-level Hugo content tree:

```
content/
  _index.md                  ← site description
  <category>/
    _index.md                ← category title, description, albumthumb, weight
    <album>/
      _index.md              ← album title, description, albumthumb, tags, locations, resources
```

### Front Matter Keys Used

**Category `_index.md`:**
```yaml
---
title: "Misc"
description: "Miscellaneous photos"
albumthumb: "gallery_icons/noun-misc-512.png"
weight: 10
draft: false
---
```

**Album `_index.md`:**
```yaml
---
title: "Cannon Beach 2010"
description: "A weekend trip to the Oregon coast."
albumthumb: "beach/cover.jpg"
date: 2010-08-14
weight: 0
draft: false
tags: ["vacation", "beach"]
locations: ["Oregon"]
resources:
  - IMG_0001.jpg
  - IMG_0002.jpg
  - 100_3319.jpg
---
```

> **Note:** The `resources` list is read with a hand-rolled parser rather than through the YAML library. This works around a VSoft.YAML 1.1 lexer bug that silently strips underscores from filenames that look like numeric literals (e.g. `100_3319.jpg` → `1003319.jpg`).

---

## Output Structure

```
output/
  index.html                  ← root category grid
  404.html
  tags/index.html
  locations/index.html
  assets/
    css/                      ← copied from theme on --force
    js/                       ← copied from theme on --force
    fonts/                    ← copied from theme on --force
    icons/                    ← category icon PNGs, copied on --force
  <category>/
    index.html                ← album grid for this category
    <album>/
      index.html              ← photo masonry page
      thumbs/
        <filename>.jpg        ← resized thumbnails
      <filename>.jpg          ← full-size copies
```

---

## Usage

```
PhotoAlbumBuilder [options]

Options:
  --config  <path>   Path to config.toml                (default: .\WebFramework\config.toml)
  --content <path>   Path to content root               (default: .\WebFramework\content)
  --assets  <path>   Path to photo assets               (default: site-specific)
  --theme   <path>   Hugo theme root                    (default: .\WebFramework\themes\autophugo)
  --output  <path>   Output directory                   (default: .\output)
  --force            Rebuild all pages + copy static assets (CSS/JS/fonts/icons)
  --dry-run          Parse and plan without writing any files
```

### Typical workflow

**First run or after template/CSS changes:**
```
PhotoAlbumBuilder --force
```

**Incremental rebuild after adding photos to one or more albums:**
```
PhotoAlbumBuilder
```

**Check what would be built without touching any files:**
```
PhotoAlbumBuilder --dry-run
```

---

## Configuration (`config.toml`)

PhotoAlbumBuilder reads a subset of Hugo's `config.toml`. Recognised keys:

```toml
title = "My Family Photos"

[params]
description   = "A collection of family memories."
robots_tags   = "noindex, nofollow"
thumb_width   = 350        # thumbnail width in pixels (default 350)
thumb_quality = 75         # JPEG quality 1–100 (default 75)
column_count  = 3          # masonry columns (default 3)
theme_path    = ""         # override theme root (optional)

[params.footer.paragraph]
headline = "About this site"

[params.footer.contact]
formspreeid = "your-id"
headline    = "Get in touch"
buttontext  = "Send"
resettext   = "Reset"

[params.footer.copyright]
name = "Your Name"

[[params.header.links]]
name = "Tags"
url  = "tags/"
icon = "fa-tags"

[[params.footer.social.links]]
label = "Instagram"
url   = "https://instagram.com/yourhandle"
icon  = "fa-instagram"
```

---

## Templates

Templates live in a `templates/` folder alongside the executable.

| File | Purpose |
|---|---|
| `base.html` | Outer HTML shell; imports header/footer, renders CSS/JS links |
| `_header.html` | Site title, breadcrumb trail, nav links |
| `_footer.html` | Description, social links, taxonomy links, contact form |
| `cards.html` | Masonry grid of album or category cards (root and category pages) |
| `album.html` | Masonry grid of photos for a single album |
| `taxonomy.html` | Tags or Locations index with per-term card grids |
| `404.html` | Not-found page |

Templates use WebStencils syntax: `@page.Title`, `@ForEach(var item in page.Items) { }`, `@if cond { }`, `@Import _partial.html`, `@LayoutPage "base.html"`.

Asset paths in templates use the `@base` variable, which is depth-adjusted so the site works in a sub-folder:
```html
<link rel="stylesheet" href="@base.Assets/css/main.css">
<a href="@base.Root">Home</a>
<a href="@base.Tags/">All Tags</a>
```

---

## Architecture

| Unit | Responsibility |
|---|---|
| `PhotoAlbum.Config` | Parses `config.toml` (hand-rolled TOML reader) and CLI arguments |
| `PhotoAlbum.Content` | Walks the content tree; parses YAML front matter via VSoft.YAML |
| `PhotoAlbum.Images` | Thumbnail generation and original copy via Skia4Delphi; EXIF rotation |
| `PhotoAlbum.Manifest` | Incremental build manifest (JSON); timestamp comparison with 1-second FAT tolerance |
| `PhotoAlbum.StencilData` | Data model classes exposed to WebStencils templates via RTTI |
| `PhotoAlbum.Columns` | Shortest-column greedy masonry balancer |
| `PhotoAlbum.Generator` | Orchestrates the build; renders templates; copies static assets |

---

## Static Assets

The CSS, JavaScript, web fonts, and category icons are **not** generated — they come from your Hugo theme and must be present in `output/assets/` for the site to display correctly.

Run `PhotoAlbumBuilder --force` once after setting up your output folder and the builder will copy everything automatically:

- `{theme}/assets/css/` → `output/assets/css/`
- `{theme}/assets/js/` → `output/assets/js/`
- `{theme}/static/fonts/` → `output/assets/fonts/`
- `{assets}/gallery_icons/` → `output/assets/icons/`

---

## License

MIT — see [LICENSE](LICENSE) for details.
