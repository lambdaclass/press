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
