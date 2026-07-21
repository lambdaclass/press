# Press

Press is a dependency-free Elixir library for rendering HTML+CSS into PDF,
targeting structured business documents: invoices, delivery notes, reports.
"Dependency-free" means zero runtime dependencies — only modules that ship
with OTP itself (e.g. `:zlib`) are used.

See `docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md` for the
full design (HTML/CSS subset, architecture, roadmap) and `TODO.md` for
features deferred to later phases.

## Status

Under active development, phase by phase:

- ✅ **Phase 1 — PDF writer core**: place text with the 14 standard PDF
  fonts and draw filled/stroked rectangles, producing a valid PDF binary.
  No HTML/CSS yet — see the example below.
- ⏳ **Phase 2 onward** (HTML parser, CSS cascade, layout, pagination,
  images, the public `Press.render/2` HTML+CSS API): not implemented yet.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `press` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:press, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/press>.

## Example

The high-level `Press.render/2` (HTML+CSS string → PDF) described in the
design spec doesn't exist yet. What's available today is the low-level PDF
writer built in Phase 1:

```elixir
doc = Press.PDF.Document.new()
{doc, page} = Press.PDF.Document.add_page(doc, 595.0, 842.0)

doc =
  doc
  |> Press.PDF.Document.draw_rect(page, 50.0, 700.0, 200.0, 80.0,
    fill: {0.9, 0.9, 0.9},
    stroke: {0, 0, 0},
    stroke_width: 1.0
  )
  |> Press.PDF.Document.draw_text(page, 60.0, 750.0, "Hello world!",
    font: :helvetica_bold,
    size: 24
  )

pdf_binary = Press.PDF.Writer.to_binary(doc)
File.write!("hello.pdf", pdf_binary)
```

This writes a one-page A4 PDF with a light-gray bordered box and bold
"Hello world!" text inside it.

## License

Press is licensed under the [MIT License](LICENSE).
