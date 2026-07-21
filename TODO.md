# TODO

- Embed custom TrueType/OTF fonts (parse `cmap`, `hmtx`, `glyf`, generate
  subsets) to support full Unicode and custom brand typography. Initial
  scope only supports the 14 standard PDF base fonts (Helvetica, Times,
  Courier and their bold/italic variants), which limits text to the
  WinAnsi/Latin-1 range.

- Support structural pseudo-classes (`:first-child`, `:last-child`,
  `:nth-child()`) in the CSS selector matcher. Initial scope only supports
  type, class, id selectors and the descendant combinator.

- Support combinators beyond descendant (`>` child, `+`/`~` siblings) and
  attribute selectors (`[attr=value]`) in the CSS selector matcher.

- Support a `default_image:` render option (fallback image bytes used when
  an `<img src>` is neither a data URI nor a key in `images:`), instead of
  returning `{:error, {:image_not_found, src}}`:

      Press.render("<img src='logo.png'>", default_image: File.read!("unknown.jpg"))

- Support interlaced (Adam7) PNG decoding. Initial scope only decodes
  non-interlaced PNGs; interlaced ones return
  `{:error, {:unsupported_image, details}}`.

- Support `text-align: justify` (inter-word spacing distribution).
  Initial scope only supports `left`/`right`/`center`; `justify` falls
  back to `left`.

- Validate the `font:` atom passed to `Press.PDF.Document.draw_text/6`
  against `Press.PDF.Fonts.standard_fonts/0` at the call site. Currently
  an invalid atom only surfaces as a `KeyError` deep inside
  `Press.PDF.Writer.to_binary/1`, far from the actual mistake.

- Add `@doc`/`@spec` to the `Press.PDF.Document`/`Press.PDF.Writer` public
  API (`new/0`, `add_page/3`, `draw_text/6`, `draw_rect/6`,
  `to_binary/1`) before later phases (layout, pagination) build heavily
  on top of it.

- `Press.PDF.Document.draw_text/6`/`draw_rect/6` append to a page's `ops`
  list via `page.ops ++ [new_op]` (O(n) per call). Fine at current scale;
  revisit (e.g. prepend + reverse at render time) if a later phase emits
  hundreds of ops per page.
