# Press Phase 4: Font Metrics + Layout — Design

Status: Approved for planning
Date: 2026-08-20

This is Phase 4 of the `press` HTML+CSS-to-PDF project (see
`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md` for the
overall architecture and roadmap). It implements:

1. `Press.Font.Metrics`: character and string width measurement using AFM
   metrics for the 14 standard PDF base fonts.
2. `Press.Layout.Box`: the box tree data structure representing placed
   geometric rectangles, lines, and text fragments.
3. `Press.Layout.Inline`: whitespace collapsing, word measurement, greedy
   line-wrapping, and text alignment (`left`, `center`, `right`).
4. `Press.Layout.Block`: block formatting context, vertical stacking,
   margin collapsing, and containing-block percentage resolution.
5. `Press.Layout.Table`: column width distribution, cell layout, and
   row height synchronization.
6. `Press.Layout.build/2`: public entry point transforming a styled tree
   (`[Press.Style.Node.t() | Press.Style.Text.t()]`) + `page_config` into a
   laid-out box tree.

---

## 1. Font Metrics (`Press.Font.Metrics`)

The 14 standard PDF base fonts are supported without external font files:
- **Helvetica**: `:helvetica`, `:helvetica_bold`, `:helvetica_oblique`, `:helvetica_bold_oblique`
- **Times**: `:times_roman`, `:times_bold`, `:times_italic`, `:times_bold_italic`
- **Courier**: `:courier`, `:courier_bold`, `:courier_oblique`, `:courier_bold_oblique`
- **Symbol**: `:symbol`
- **ZapfDingbats**: `:zapf_dingbats`

### Character Width Tables
Adobe Font Metrics (AFM) define glyph advance widths in units of 1/1000 of an
em (`units_per_em = 1000`).
- Courier is fixed-width: every glyph is 600 units.
- Helvetica and Times have variable character widths compiled into module
  lookup tables.

### Font Selection
`Press.Font.Metrics.font_for(family, weight, style)` maps computed CSS font
properties to the exact PDF base font atom:
```elixir
font_for(:helvetica, :bold, :normal)       # => :helvetica_bold
font_for(:times, :normal, :italic)         # => :times_italic
font_for(:courier, :bold, :italic)         # => :courier_bold_oblique
font_for(:unknown, :normal, :normal)       # => :helvetica (default fallback)
```

### Width Calculation
```elixir
Press.Font.Metrics.text_width(font, text, font_size)
# points = (sum of glyph advance widths) * font_size / 1000.0
```

---

## 2. Box Data Model (`Press.Layout.Box`)

```elixir
defmodule Press.Layout.Box do
  @type box_type :: :block | :line | :text | :table | :table_row | :table_cell

  defstruct [
    :type,
    :tag,
    :x,
    :y,
    :width,
    :height,
    margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    border_color: %{top: nil, right: nil, bottom: nil, left: nil},
    border_style: %{top: :none, right: :none, bottom: :none, left: :none},
    background_color: nil,
    computed: %{},
    children: [],
    # For text boxes:
    :text,
    :font,
    :font_size,
    :color
  ]
end
```

---

## 3. Inline Layout & Line Wrapping (`Press.Layout.Inline`)

### Whitespace Handling
- Sequences of whitespace characters (`\s`, `\t`, `\n`, `\r`) are collapsed into
  a single space `" "`.
- Leading whitespace at the start of a line is stripped.
- Trailing whitespace at the end of a line is stripped.

### Greedy Line-Breaking Algorithm
1. Flatten inline children (nested `<span>`, `<strong>`, `<em>`, plain text)
   into a sequence of styled words and spaces.
2. Maintain `current_line` and `current_width`.
3. For each word:
   - Calculate `word_width = text_width(word.font, word.text, word.font_size)`.
   - If `current_width + word_width <= available_width` or `current_line` is empty:
     - Append word to `current_line`.
     - Update `current_width`.
   - Else:
     - Close `current_line` as a line box.
     - Start new line with `word`.
4. Wrap lines into `:line` boxes with `height = max_line_height`.

### Text Alignment
For each line box within containing content width $W$:
- `:left`: items positioned starting at $x = 0$.
- `:center`: offset $x_0 = (W - \text{line\_width}) / 2$.
- `:right`: offset $x_0 = W - \text{line\_width}$.

---

## 4. Block Layout (`Press.Layout.Block`)

### Containing Block & Percentage Resolution
- Top-level containing block has width = $W_{\text{page}} - \text{margin.left} - \text{margin.right}$.
- Percentage widths (`{:percent, p}`) and margins resolve against the containing
  block's content width:
  $$\text{length} = \frac{p}{100.0} \times W_{\text{containing}}$$
- If `width == :auto`:
  $$W_{\text{content}} = W_{\text{containing}} - \text{margin.left} - \text{margin.right} - \text{padding.left} - \text{padding.right} - \text{border.left} - \text{border.right}$$

### Vertical Flow & Margin Collapsing
- Sibling block elements stack vertically.
- Vertical margins between adjacent block siblings collapse:
  $$\text{margin\_gap} = \max(\text{margin\_bottom}_{\text{prev}}, \text{margin\_top}_{\text{curr}})$$
- Box position coordinates:
  - Outer top-left: $(x_{\text{outer}}, y_{\text{outer}})$.
  - Content origin:
    $$x_{\text{content}} = x_{\text{outer}} + \text{margin.left} + \text{border.left} + \text{padding.left}$$
    $$y_{\text{content}} = y_{\text{outer}} + \text{margin.top} + \text{border.top} + \text{padding.top}$$
- Box height equals sum of children heights + padding + border.

---

## 5. Table Layout (`Press.Layout.Table`)

- Supported tags: `<table>`, `<thead>`, `<tbody>`, `<tfoot>`, `<tr>`, `<th>`, `<td>`.
- Column widths:
  - If cells define explicit widths (`pt`, `px`, `%`), those widths are assigned
    to the respective columns.
  - Remaining table width is divided equally among unspecified columns.
- Row layout:
  - Cells in each `<tr>` are laid out horizontally at the assigned column widths.
  - Row height = $\max(\text{cell heights})$.
  - Every cell in the row expands to the full row height for consistent borders
    and backgrounds.

---

## 6. Non-Visual Elements

Elements with tags `"head"`, `"style"`, `"link"`, `"meta"`, `"script"`, `"title"`
are ignored during layout and emit no boxes.

---

## 7. Public API (`Press.Layout.build/2`)

```elixir
@spec build([Press.Style.Node.t() | Press.Style.Text.t()], map()) :: Press.Layout.Box.t()
```

Accepts the styled tree and the page configuration (from `Press.Style.Cascade.page_config/2`),
and returns the root containing `:block` box containing all laid out children.
