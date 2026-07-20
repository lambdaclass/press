# Press: HTML+CSS to PDF, pure Elixir — Design

Status: Approved for planning
Date: 2026-07-20

## Goals

Build `press`, a dependency-free Elixir library that renders an HTML+CSS
string into a PDF binary, targeting structured business documents:
invoices, delivery notes, reports.

"Dependency-free" means zero runtime dependencies in `mix.exs` (`deps: []`).
The library may rely on modules that ship with OTP itself (e.g. `:zlib`),
since those are not Hex dependencies. Test-only dependencies (e.g.
`StreamData`) are allowed, declared with `only: :test`.

## Non-goals (v1)

Deferred items are tracked in `TODO.md` at the project root:

- Embedding custom TrueType/OTF fonts (Unicode beyond WinAnsi/Latin-1,
  custom brand typography).
- CSS structural pseudo-classes (`:first-child`, `:last-child`,
  `:nth-child()`).
- CSS combinators beyond descendant (`>`, `+`, `~`) and attribute
  selectors (`[attr=value]`).
- A `default_image:` render option for a fallback image when `src` is
  unresolved.
- Flexbox, grid, floats, absolute positioning — general-purpose web
  layout. This library targets print-style block/table layout only.

## Public API

```elixir
Press.render(html, opts \\ [])

# opts:
#   css: nil | String.t()             — external stylesheet, applied before
#                                        any <style> embedded in `html`
#   images: %{String.t() => binary()} — src -> raw image bytes, used when
#                                        an <img src="..."> is not a data URI

@spec render(String.t(), keyword()) ::
        {:ok, binary()}
      | {:error, Press.Error.t()}
```

Example:

```elixir
html = "<h1>Hello world!</h1>"
css = "h1 { font-size: 14px; }"
Press.render(html, css: css)

logo = File.read!("logo.png")
html = "<img src='img/logo.png'>"
Press.render(html, images: %{"img/logo.png" => logo})
```

`press` never performs I/O (no filesystem or network access). All inputs
(HTML, CSS, image bytes) are passed in by the caller. This keeps the
library pure and avoids SSRF-style risks from following user-supplied
URLs. The caller is responsible for reading files and generating the HTML
string (e.g. via `EEx`, Phoenix/HEEx templates, or plain string
interpolation) — `press` itself does not depend on or compile any
templating engine.

### CSS precedence

When both `opts[:css]` and an embedded `<style>` block are present, `css:`
is treated as an external stylesheet applied first; the embedded `<style>`
is applied after. On equal specificity, the embedded `<style>` wins (same
rule a browser applies for a linked stylesheet followed by inline
`<style>`).

### Errors

`{:ok, pdf_binary}` on success. On error, `{:error, %Press.Error{}}`:

```elixir
%Press.Error{
  stage: :html_parse | :css_parse | :layout | :image | ...,
  reason: term(),
  message: String.t()
}
```

Callers can pattern-match on `stage` or just read `message`. Expected
error cases: unrecoverable HTML/CSS syntax, an `<img src>` that is neither
a data URI nor a key in `images:` (`{:image_not_found, src}`). An unknown
`font-family` is *not* an error — it falls back to Helvetica.

No exceptions are raised for expected/data-driven error cases — only
`{:error, _}`. Exceptions are reserved for genuine internal bugs (states
the library should never reach).

## Architecture

Staged pipeline, each stage a pure function producing a materialized
intermediate tree — chosen over a streaming/no-DOM design because each
stage is independently testable with small fixtures, which matters more
for this project than the memory savings a streaming design would bring
(these are few-page business documents, not huge multi-hundred-page
books). Layout and pagination are two separate stages (not fused into a
single pass) for the same testability reason: each can be tested without
simulating the other.

```
HTML string ─▶ Press.HTML.Parser ─▶ DOM
CSS string(s) ─▶ Press.CSS.Parser ─▶ rule list (selector + specificity + declarations)

DOM + rules ─▶ Press.Style.Cascade ─▶ styled tree
               (resolves cascade/specificity, inherits font-size,
                resolves em/rem/% to points using each node's context)

styled tree ─▶ Press.Layout ─▶ box tree
               (sizes and positions assuming a single infinite-height page;
                block layout algorithm + tables live here)

box tree + @page ─▶ Press.Layout.Paginate ─▶ page list
                     (slices the box tree into pages, repeats header/footer,
                      avoids splitting table rows across pages)

page list ─▶ Press.PDF.Builder ─▶ PDF object model
             (pages, fonts, resources, content streams)

PDF object model ─▶ Press.PDF.Writer ─▶ final PDF binary
                     (serializes objects + xref table + trailer)
```

The HTML parser is custom and lenient (tolerates unclosed tags, implicit
closing) rather than built on OTP's `:xmerl`, since the latter requires
well-formed XML and the project owner prefers not to impose that
constraint on input HTML.

## Data model

```elixir
# DOM (HTML parser output)
%Press.HTML.Element{tag: "div", attrs: %{"class" => "total"}, children: [...]}
%Press.HTML.Text{content: "Hello world!"}

# CSS rule (CSS parser output)
%Press.CSS.Rule{selector: [...], specificity: {0, 1, 0}, declarations: %{"font-size" => "14px"}}

# Styled node (cascade output) — units already resolved to points
%Press.Style.Node{
  element: %Press.HTML.Element{},
  computed: %{font_size: 10.5, color: {0, 0, 0}, margin: %{top: 0, right: 0, bottom: 0, left: 0}, ...},
  children: [...]
}

# Layout box (Press.Layout output)
%Press.Layout.Box{
  x: 20.0, y: 40.0, width: 555.0, height: 14.0,
  kind: :block | :inline | :table | :table_row | :table_cell | :text | :image,
  content: ...,
  children: [...]
}

# Paginated page (Press.Layout.Paginate output)
%Press.Layout.Page{size: {595.0, 842.0}, boxes: [...]}
```

The PDF object model (`Press.PDF.Builder`/`Writer`) follows the standard
PDF structure: numbered indirect objects, dictionaries, streams, and an
xref table.

## HTML/CSS subset (v1)

**HTML tags:** `html`, `head`, `style`, `body`, `div`, `span`, `p`,
`h1`–`h6`, `strong`/`b`, `em`/`i`, `br`, `ul`/`ol`/`li`, `table`/`thead`/
`tbody`/`tfoot`/`tr`/`th`/`td`, `img`, `header`, `footer`, `main`.
Unknown tags are treated as a generic `div` rather than an error, so the
parser is resilient to markup it doesn't yet know about.

**CSS properties:**
- Box: `width`, `height`, `margin(-*)`, `padding(-*)`, `border(-*)`
  (style `solid` only, color, width), `box-sizing`.
- Text: `font-family` (limited to the 14 base fonts; unknown families fall
  back to Helvetica), `font-size`, `font-weight` (`normal`/`bold`),
  `font-style` (`normal`/`italic`), `color`, `text-align`, `line-height`.
- Table: `border-collapse`, `border-spacing`.
- `background-color`.
- `@page` with `size` (`A4`/`Letter`/`Legal` or custom `<width> <height>`)
  and `margin`.
- `page-break-before`/`page-break-after` (`auto`/`always`) as a manual
  override on top of automatic pagination.

Unsupported properties are silently ignored, matching browser behavior
for unrecognized CSS.

**Selectors:** type, class, id, and the descendant combinator only (see
Non-goals for deferred combinators/pseudo-classes).

**Units:** absolute — `mm`, `cm`, `in`, `pt`, `px` (96px = 1in, matching
browser convention); relative — `em`, `rem`, `%`. All are resolved to
points during the cascade stage, using each node's computed font-size
(for `em`) or the root font-size (for `rem`) or the containing block's
size (for `%`).

## Fonts and text measurement

The 14 standard PDF base fonts (Helvetica, Helvetica-Bold,
Helvetica-Oblique, Helvetica-BoldOblique, Times-Roman, Times-Bold,
Times-Italic, Times-BoldItalic, Courier and its variants, Symbol,
ZapfDingbats) don't need to be embedded — every PDF reader ships them.
`Press.Font.Metrics` embeds their per-character width tables (converted
from Adobe's public AFM files) as static Elixir data, compiled into the
library — no runtime download.

`Press.Layout` uses these metrics to measure word/line widths for
line-wrapping and to compute line heights for stacking text. Line
breaking is greedy (add words while they fit; break at the first space
where the next word doesn't fit) — no hyphenation.

## Pagination

```css
@page {
  size: A4; /* or Letter, Legal, or custom: 210mm 297mm */
  margin: 20mm 15mm 25mm 15mm; /* top right bottom left */
}
```

```html
<header>...</header>  <!-- repeated on every page, outside the paginated flow -->
<footer>...</footer>  <!-- same -->
<main>...</main>      <!-- paginated content -->
```

`Press.Layout.Paginate` walks the box tree under `<main>`, accumulating
height. When the next non-splittable box (a table row, a paragraph)
doesn't fit in the remaining space on the current page, it closes the
page (repeating `header`/`footer`) and continues on a new one. Tables
repeat their `<thead>` row at the top of each page they continue onto.

`page-break-before`/`page-break-after: always` forces a manual break
regardless of remaining space.

## Images

```html
<img src="data:image/png;base64,..." width="120" height="40">
<img src="img/logo.png"> <!-- resolved via opts[:images]["img/logo.png"] -->
```

`src` must be either a data URI (`data:image/png;base64,...` or
`data:image/jpeg;base64,...`) or a literal key looked up in `opts[:images]`
— a caller-supplied map of `src -> raw bytes`. If `src` is neither, the
render returns `{:error, %Press.Error{stage: :image, reason: {:image_not_found, src}}}`.
This keeps `press` free of filesystem/network I/O.

- **JPEG**: bytes are copied as-is into the PDF (`DCTDecode`), no
  decoding needed.
- **PNG**: the header (IHDR: width/height/color depth/type) is decoded
  and the pixel stream is recompressed with `:zlib` (built into OTP) into
  the form PDF expects (`FlateDecode` + `DeviceRGB`/`DeviceGray`, with a
  separate `SMask` for alpha channels).

## Testing strategy

- **Per-stage unit tests**, using the intermediate structs as fixtures
  without running the full pipeline: HTML parser input/output fragments,
  CSS parser selector/specificity cases, cascade with small trees,
  `Press.Layout` with hand-built styled nodes, `Press.Layout.Paginate`
  with hand-built box trees and small page heights to force breaks
  easily.
- **End-to-end integration tests**: real HTML+CSS (e.g. a sample invoice)
  through `Press.render/2`, asserting the resulting PDF is syntactically
  valid (parseable) and structurally correct (page count, expected text
  present in a content stream, xref table consistent) — not
  pixel-by-pixel image comparison.
- **Property-based/fuzz testing** (optional, `:test`-only dependency such
  as `StreamData`): generate varied HTML/CSS and assert `Press.render/2`
  never crashes — always returns `{:ok, _}` or `{:error, _}`.
