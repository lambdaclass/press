# Press Phase 6: Image Support (`<img>`) — Design

Status: Approved for planning
Date: 2026-08-20

This is Phase 6 of the `press` pure-Elixir HTML+CSS-to-PDF engine (see
`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md` for the
overall architecture and roadmap). It implements:

1. `Press.Image`: image data model and metadata.
2. `Press.Image.JPEG`: pure-Elixir JPEG header parser (SOF dimensions & color channels).
3. `Press.Image.PNG`: pure-Elixir PNG decoder (IHDR, IDAT uncompression via `:zlib`, scanline unfiltering, and alpha `/SMask` separation).
4. `Press.Image.Parser`: unified image loader (data URIs and binary lookup).
5. `Press.Layout`: layout box creation for `<img>` elements with intrinsic and explicit scaling.
6. `Press.PDF.Writer`: XObject image serialization (`/DCTDecode` for JPEG, `/FlateDecode` + `/SMask` for PNG).

---

## 1. Image Data Model (`Press.Image`)

```elixir
defmodule Press.Image do
  @type format :: :jpeg | :png
  @type color_space :: :rgb | :gray

  @type t :: %__MODULE__{
          id: String.t(),
          format: format(),
          width: pos_integer(),
          height: pos_integer(),
          color_space: color_space(),
          data: binary(),
          alpha_data: binary() | nil
        }

  defstruct [:id, :format, :width, :height, :color_space, :data, :alpha_data]
end
```

---

## 2. Image Decoding

### JPEG (`Press.Image.JPEG`)
- Direct pass-through: raw bytes are copied into the PDF stream as `/Filter /DCTDecode`.
- Header parsing: scans for `SOF0` (`0xFF, 0xC0`), `SOF1` (`0xFF, 0xC1`), or `SOF2` (`0xFF, 0xC2`) marker segments to extract:
  - Pixel width (16-bit integer).
  - Pixel height (16-bit integer).
  - Number of components (1 for grayscale `/DeviceGray`, 3 for RGB `/DeviceRGB`).

### PNG (`Press.Image.PNG`)
- Signature validation: `<<137, 80, 78, 71, 13, 10, 26, 10>>`.
- Chunk parsing: reads `IHDR`, `PLTE`, `tRNS`, and `IDAT` chunks.
- Scanline unfiltering:
  - Decompresses `IDAT` with `:zlib.uncompress/1`.
  - Reconstructs scanline filters:
    - 0: None
    - 1: Sub
    - 2: Up
    - 3: Average
    - 4: Paeth
- Alpha channel handling:
  - If PNG has alpha (color types 4, 6, or indexed with transparency):
    - Color channels (RGB / Grayscale) are separated from Alpha.
    - Alpha channel is emitted as an 8-bit `/DeviceGray` mask (`/SMask`).
  - Recompresses pixel payloads with `:zlib.compress/1` for `/Filter /FlateDecode`.

---

## 3. Image Sizing & Layout

Intrinsic dimensions in points:
$$\text{intrinsic\_width} = \text{width\_px} \times 0.75$$
$$\text{intrinsic\_height} = \text{height\_px} \times 0.75$$

Given specified dimensions in HTML attributes (`width="..."`, `height="..."`) or CSS:
- Both `width` and `height` specified: use specified values.
- Only `width` specified: $\text{height} = \frac{\text{width}}{\text{intrinsic\_width}} \times \text{intrinsic\_height}$.
- Only `height` specified: $\text{width} = \frac{\text{height}}{\text{intrinsic\_height}} \times \text{intrinsic\_width}$.
- Neither specified: use intrinsic dimensions.

`<img>` boxes are treated as atomic inline/block content with margin, border, and padding.

---

## 4. PDF XObject Generation

In `Press.PDF.Document` and `Press.PDF.Writer`:
- Unique image objects are assigned XObject names (`/Im1`, `/Im2`, ...).
- Content stream uses the Current Transformation Matrix (CTM) to place images:
  ```
  q
  w 0 0 h x y cm
  /Im1 Do
  Q
  ```
  where $(x, y)$ is the bottom-left corner in PDF coordinate space ($y_{\text{pdf}} = H_{\text{page}} - (y_{\text{layout}} + h)$).
- PDF Resources dictionary declares `/XObject << /Im1 ... >>`.
