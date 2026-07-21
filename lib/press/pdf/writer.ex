defmodule Press.PDF.Writer do
  @moduledoc false

  alias Press.PDF.{ContentStream, Document, Fonts, Syntax}

  def to_binary(%Document{pages: pages}) do
    page_count = length(pages)
    fonts = collect_fonts(pages)
    # One past the last contents object number.
    first_font_obj_num = page_obj_num(page_count)

    font_resource_names =
      fonts |> Enum.with_index(1) |> Map.new(fn {font, i} -> {font, "/F#{i}"} end)

    font_obj_numbers = fonts |> Enum.with_index(first_font_obj_num) |> Map.new()

    resources = resources_dict(fonts, font_resource_names, font_obj_numbers)

    page_obj_numbers =
      if page_count == 0, do: [], else: for(i <- 0..(page_count - 1), do: page_obj_num(i))

    page_and_content_objects =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {page, i} ->
        page_obj_num = page_obj_num(i)
        contents_obj_num = contents_obj_num(i)
        content_bytes = ContentStream.render(page.ops, font_resource_names)

        page_body =
          "<< /Type /Page /Parent 2 0 R " <>
            "/MediaBox [0 0 #{Syntax.number(page.width)} #{Syntax.number(page.height)}] " <>
            "/Resources #{resources} /Contents #{contents_obj_num} 0 R >>"

        [{page_obj_num, page_body}, {contents_obj_num, stream_body(content_bytes)}]
      end)

    catalog = {1, "<< /Type /Catalog /Pages 2 0 R >>"}

    kids = Enum.map_join(page_obj_numbers, " ", &"#{&1} 0 R")
    pages_obj = {2, "<< /Type /Pages /Kids [#{kids}] /Count #{page_count} >>"}

    font_objects =
      for font <- fonts do
        {font_obj_numbers[font],
         "<< /Type /Font /Subtype /Type1 /BaseFont /#{Fonts.base_font_name(font)} " <>
           "/Encoding /WinAnsiEncoding >>"}
      end

    objects =
      ([catalog, pages_obj] ++ page_and_content_objects ++ font_objects)
      |> Enum.sort_by(&elem(&1, 0))

    assemble("%PDF-1.4\n", objects)
  end

  defp collect_fonts(pages) do
    pages
    |> Enum.flat_map(fn page ->
      Enum.flat_map(page.ops, fn
        {:text, _x, _y, font, _size, _color, _text} -> [font]
        _other -> []
      end)
    end)
    |> Enum.uniq()
  end

  defp resources_dict(fonts, font_resource_names, font_obj_numbers) do
    entries =
      Enum.map_join(fonts, " ", fn font ->
        "#{font_resource_names[font]} #{font_obj_numbers[font]} 0 R"
      end)

    "<< /Font << #{entries} >> >>"
  end

  defp stream_body(content_bytes) do
    length = IO.iodata_length(content_bytes)
    "<< /Length #{length} >>\nstream\n#{IO.iodata_to_binary(content_bytes)}\nendstream"
  end

  defp assemble(header, objects) do
    initial = {[], %{}, byte_size(header)}

    {body_iodata, offsets, xref_offset} =
      Enum.reduce(objects, initial, fn {num, body}, {acc, offsets, running_offset} ->
        obj_iodata = "#{num} 0 obj\n#{body}\nendobj\n"
        new_offset = running_offset + IO.iodata_length(obj_iodata)
        {[acc, obj_iodata], Map.put(offsets, num, running_offset), new_offset}
      end)

    max_obj_num = objects |> Enum.map(&elem(&1, 0)) |> Enum.max()

    xref_entries =
      for num <- 1..max_obj_num do
        pad_offset(Map.fetch!(offsets, num)) <> " 00000 n\r\n"
      end

    xref =
      "xref\n0 #{max_obj_num + 1}\n" <>
        "0000000000 65535 f\r\n" <>
        Enum.join(xref_entries)

    trailer =
      "trailer\n<< /Size #{max_obj_num + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF"

    IO.iodata_to_binary([header, body_iodata, xref, trailer])
  end

  defp pad_offset(offset), do: offset |> Integer.to_string() |> String.pad_leading(10, "0")

  defp page_obj_num(i), do: 3 + i * 2
  defp contents_obj_num(i), do: 4 + i * 2
end
