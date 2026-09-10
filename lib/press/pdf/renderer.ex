defmodule Press.PDF.Renderer do
  @moduledoc false

  alias Press.Layout.{Box, Page}
  alias Press.PDF.Document

  @doc """
  Transforms a list of layout `Page` structs into a `Press.PDF.Document`.
  """
  def render_document(pages, _page_config) do
    Enum.reduce(pages, Document.new(), fn %Page{} = page, doc ->
      {doc_with_page, page_index} = Document.add_page(doc, page.width, page.height)
      render_boxes(page.boxes, doc_with_page, page_index, page.height)
    end)
  end

  defp render_boxes(boxes, doc, page_index, page_height) do
    Enum.reduce(boxes, doc, fn box, acc_doc ->
      render_box(box, acc_doc, page_index, page_height)
    end)
  end

  defp render_box(%Box{} = box, doc, page_index, page_height) do
    doc
    |> render_background(box, page_index, page_height)
    |> render_borders(box, page_index, page_height)
    |> render_text(box, page_index, page_height)
    |> render_image(box, page_index, page_height)
    |> render_children(box.children, page_index, page_height)
  end

  defp render_children(doc, children, page_index, page_height) do
    render_boxes(children, doc, page_index, page_height)
  end

  defp render_background(doc, %Box{background_color: nil}, _page_idx, _h), do: doc

  defp render_background(doc, %Box{background_color: color} = box, page_idx, page_height) do
    bw = Box.border_box_width(box)
    bh = Box.border_box_height(box)

    pdf_x = box.x
    pdf_y = page_height - (box.y + bh)

    Document.draw_rect(doc, page_idx, pdf_x, pdf_y, bw, bh, fill: color)
  end

  defp render_borders(
         doc,
         %Box{border_width: %{top: +0.0, right: +0.0, bottom: +0.0, left: +0.0}},
         _,
         _
       ),
       do: doc

  defp render_borders(doc, %Box{} = box, page_idx, page_height) do
    bw = Box.border_box_width(box)
    bh = Box.border_box_height(box)
    b_width = box.border_width
    b_color = box.border_color
    b_style = box.border_style

    doc
    |> maybe_draw_border(
      b_width.top,
      b_color.top,
      b_style.top,
      page_idx,
      box.x,
      page_height - (box.y + b_width.top),
      bw,
      b_width.top
    )
    |> maybe_draw_border(
      b_width.right,
      b_color.right,
      b_style.right,
      page_idx,
      box.x + bw - b_width.right,
      page_height - (box.y + bh),
      b_width.right,
      bh
    )
    |> maybe_draw_border(
      b_width.bottom,
      b_color.bottom,
      b_style.bottom,
      page_idx,
      box.x,
      page_height - (box.y + bh),
      bw,
      b_width.bottom
    )
    |> maybe_draw_border(
      b_width.left,
      b_color.left,
      b_style.left,
      page_idx,
      box.x,
      page_height - (box.y + bh),
      b_width.left,
      bh
    )
  end

  defp maybe_draw_border(doc, width, color, style, page_idx, x, y, w, h) do
    if width > 0.0 and style != :none and not is_nil(color) do
      Document.draw_rect(doc, page_idx, x, y, w, h, fill: color)
    else
      doc
    end
  end

  defp render_text(
         doc,
         %Box{type: :text, text: text, font: font, font_size: size, color: color} = box,
         page_idx,
         page_height
       )
       when is_binary(text) and text != "" do
    pdf_x = box.x
    pdf_y = page_height - box.y - baseline_offset(font, size, box.height)

    Document.draw_text(doc, page_idx, pdf_x, pdf_y, text,
      font: font || :helvetica,
      size: size || 12.0,
      color: color || {0, 0, 0},
      letter_spacing: box.letter_spacing || 0.0
    )
  end

  defp render_text(doc, _box, _page_idx, _h), do: doc

  # Distance from the top of the line box down to the baseline: the leading is
  # split evenly above and below the text, so a line taller than the glyphs
  # pushes the baseline down by half the difference.
  defp baseline_offset(font, size, line_height) do
    {ascent, descent} = Press.Font.Widths.ascent_descent(font || :helvetica)
    size = size || 12.0
    ascent_pt = ascent / 1000.0 * size
    glyph_height = (ascent - descent) / 1000.0 * size
    half_leading = ((line_height || glyph_height) - glyph_height) / 2.0

    half_leading + ascent_pt
  end

  defp render_image(
         doc,
         %Box{type: :image, image: %Press.Image{} = img} = box,
         page_idx,
         page_height
       ) do
    pdf_x = box.x
    pdf_y = page_height - (box.y + box.height)
    Document.draw_image(doc, page_idx, pdf_x, pdf_y, box.width, box.height, img)
  end

  defp render_image(doc, _box, _page_idx, _h), do: doc
end
