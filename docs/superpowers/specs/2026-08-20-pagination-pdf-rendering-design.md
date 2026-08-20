# Press Phase 5: Pagination + PDF Rendering — Design

Status: Approved for planning
Date: 2026-08-20

This is Phase 5 of the `press` HTML+CSS-to-PDF engine (see
`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md` for the
overall architecture and roadmap). It implements:

1. `Press.Layout.Page`: the paginated page container struct.
2. `Press.Layout.Paginate`: page-breaking and header/footer distribution
   engine.
3. `Press.PDF.Renderer`: conversion of positioned layout boxes into PDF
   drawing operations (`:text`, `:rect`, backgrounds, borders) in PDF
   bottom-left coordinate space.
4. `Press.render/2`: the public top-level API connecting all stages from
   HTML/CSS strings to PDF binary output.

---

## 1. Page Data Model (`Press.Layout.Page`)

```elixir
defmodule Press.Layout.Page do
  @type t :: %__MODULE__{
          number: pos_integer(),
          width: float(),
          height: float(),
          margin: %{top: float(), right: float(), bottom: float(), left: float()},
          boxes: [Press.Layout.Box.t()]
        }

  defstruct [:number, :width, :height, :margin, boxes: []]
end
```

---

## 2. Pagination Engine (`Press.Layout.Paginate`)

### Header, Footer, and Main Content Flow
The layout tree is partitioned into three conceptual sections:
- `<header>`: fixed at $y = \text{margin.top}$ on every page.
- `<footer>`: fixed at $y = \text{page\_height} - \text{margin.bottom} - \text{footer.height}$ on every page.
- `<main>` / Flow: paginated flow occupying the remaining height:
  $$H_{\text{flow}} = \text{page\_height} - \text{margin.top} - \text{margin.bottom} - \text{header.height} - \text{footer.height}$$
  $$y_{\text{flow\_start}} = \text{margin.top} + \text{header.height}$$

If no explicit `<header>` / `<footer>` tags exist, all content flows within the
usable page area ($H_{\text{usable}} = \text{page\_height} - \text{margin.top} - \text{margin.bottom}$).

### Page Breaking Algorithm
1. **Flow traversal**: Flow boxes (blocks, lines, tables) are consumed sequentially.
2. **Height accumulation**:
   - Each box's height is added to the page flow cursor.
   - If a box fits in the remaining page flow height:
     - Shift box's $y$ coordinate to match current page flow position.
     - Append to current page.
   - If a box exceeds remaining page flow height:
     - **Table splitting**:
       - If the box is a `<table>` with rows, the table splits across pages:
       - The `<thead>` row (if present) is repeated at the top of each page the
         table continues onto.
       - As many `<tr>` body rows as fit on the current page are placed.
       - A new page is opened, `<thead>` placed at the top, and remaining rows
         continue.
     - **Atomic block boxes**:
       - Non-splittable block boxes (headings, paragraphs, single lines) move to
         the next page.
       - If a single atomic box is taller than $H_{\text{flow}}$ on a blank page,
         it is placed on the fresh page and allowed to overflow rather than
         looping indefinitely.
3. **Manual Page Breaks**:
   - `page-break-before: always`: closes current page immediately before
     placing the box.
   - `page-break-after: always`: closes current page immediately after placing
     the box.

---

## 3. PDF Coordinate & Drawing Renderer (`Press.PDF.Renderer`)

### Coordinate System Transformation
PDF coordinates use $(0,0)$ at the **bottom-left** of the page with $y$
increasing upwards, whereas Layout coordinates use $(0,0)$ at the **top-left**
with $y$ increasing downwards.

For a page with total height $H$:
- **Text**:
  $$\text{pdf\_x} = x_{\text{box}}$$
  $$\text{pdf\_y} = H - y_{\text{box}} - (\text{font\_size} \times 0.8)$$
- **Rectangles (Backgrounds & Borders)**:
  $$\text{pdf\_x} = x_{\text{box}}$$
  $$\text{pdf\_y} = H - (y_{\text{box}} + h_{\text{box}})$$
  $$\text{pdf\_w} = w_{\text{box}}$$
  $$\text{pdf\_h} = h_{\text{box}}$$

### Drawing Generation
For every box in each page:
1. **Background**: If `background_color` is non-nil, emit a filled rectangle
   spanning the border-box.
2. **Borders**: If `border_width` is non-zero, emit filled rectangular strips for
   active borders (top, right, bottom, left) with `border_color`.
3. **Text**: For `:text` leaf boxes, emit a text drawing operation with `font`,
   `font_size`, `color`, and text content.
4. **Recursion**: Recursively render child boxes.

---

## 4. Top-Level Entry Point (`Press.render/2`)

```elixir
@spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
```

Connects the full pipeline:
1. `Press.HTML.Parser.parse(html)` → DOM.
2. Extract embedded `<style>` text.
3. `Press.CSS.Parser.parse/1` on external & embedded CSS → rules.
4. `Press.Style.Cascade.page_config/2` → page size & margins.
5. `Press.Style.Cascade.build/3` → styled tree.
6. `Press.Layout.build/2` → box tree.
7. `Press.Layout.Paginate.paginate/2` → list of pages.
8. `Press.PDF.Renderer.render/2` → `Press.PDF.Document`.
9. `Press.PDF.Writer.to_binary/1` → `%PDF-1.4...` binary.
