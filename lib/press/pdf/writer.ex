defmodule Press.PDF.Writer do
  @moduledoc false

  alias Press.Image
  alias Press.PDF.{ContentStream, Document, Fonts, Syntax}

  def to_binary(%Document{pages: pages}) do
    page_count = length(pages)
    fonts = collect_fonts(pages)
    images = collect_images(pages)

    first_free_obj_num = page_obj_num(page_count)

    font_resource_names =
      fonts |> Enum.with_index(1) |> Map.new(fn {font, i} -> {font, "/F#{i}"} end)

    font_obj_numbers =
      fonts |> Enum.with_index(first_free_obj_num) |> Map.new()

    after_fonts_obj_num = first_free_obj_num + length(fonts)

    {image_resource_names, image_obj_numbers, _smask_obj_numbers, image_objects} =
      build_image_objects(images, after_fonts_obj_num)

    resources =
      resources_dict(
        fonts,
        font_resource_names,
        font_obj_numbers,
        images,
        image_resource_names,
        image_obj_numbers
      )

    page_obj_numbers =
      if page_count == 0, do: [], else: for(i <- 0..(page_count - 1), do: page_obj_num(i))

    page_and_content_objects =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {page, i} ->
        page_obj_num = page_obj_num(i)
        contents_obj_num = contents_obj_num(i)

        content_bytes =
          ContentStream.render(page.ops, font_resource_names, image_resource_names)

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
      ([catalog, pages_obj] ++ page_and_content_objects ++ font_objects ++ image_objects)
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

  defp collect_images(pages) do
    pages
    |> Enum.flat_map(fn page ->
      Enum.flat_map(page.ops, fn
        {:image, _x, _y, _w, _h, %Image{} = img} -> [img]
        _other -> []
      end)
    end)
    |> Enum.uniq_by(& &1.id)
  end

  defp build_image_objects(images, start_obj_num) do
    {img_res, img_objs, smask_objs, objects, _next_obj} =
      images
      |> Enum.with_index(1)
      |> Enum.reduce(
        {%{}, %{}, %{}, [], start_obj_num},
        fn {img, idx}, {res_acc, obj_acc, smask_acc, objs_acc, curr_obj} ->
          res_name = "/Im#{idx}"
          img_id = img.id || "img_#{idx}"
          img_obj_num = curr_obj
          color_space = if img.color_space == :gray, do: "DeviceGray", else: "DeviceRGB"

          case img.format do
            :jpeg ->
              body =
                "<< /Type /XObject /Subtype /Image /Width #{img.width} /Height #{img.height} " <>
                  "/ColorSpace /#{color_space} /BitsPerComponent 8 /Filter /DCTDecode /Length #{byte_size(img.data)} >>\n" <>
                  "stream\n#{img.data}\nendstream"

              {
                Map.put(res_acc, img_id, res_name),
                Map.put(obj_acc, img_id, img_obj_num),
                smask_acc,
                [{img_obj_num, body} | objs_acc],
                curr_obj + 1
              }

            :png ->
              if img.alpha_data do
                mask_obj_num = curr_obj + 1

                mask_body =
                  "<< /Type /XObject /Subtype /Image /Width #{img.width} /Height #{img.height} " <>
                    "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /Length #{byte_size(img.alpha_data)} >>\n" <>
                    "stream\n#{img.alpha_data}\nendstream"

                img_body =
                  "<< /Type /XObject /Subtype /Image /Width #{img.width} /Height #{img.height} " <>
                    "/ColorSpace /#{color_space} /BitsPerComponent 8 /Filter /FlateDecode /SMask #{mask_obj_num} 0 R /Length #{byte_size(img.data)} >>\n" <>
                    "stream\n#{img.data}\nendstream"

                {
                  Map.put(res_acc, img_id, res_name),
                  Map.put(obj_acc, img_id, img_obj_num),
                  Map.put(smask_acc, img_id, mask_obj_num),
                  [{img_obj_num, img_body}, {mask_obj_num, mask_body} | objs_acc],
                  curr_obj + 2
                }
              else
                img_body =
                  "<< /Type /XObject /Subtype /Image /Width #{img.width} /Height #{img.height} " <>
                    "/ColorSpace /#{color_space} /BitsPerComponent 8 /Filter /FlateDecode /Length #{byte_size(img.data)} >>\n" <>
                    "stream\n#{img.data}\nendstream"

                {
                  Map.put(res_acc, img_id, res_name),
                  Map.put(obj_acc, img_id, img_obj_num),
                  smask_acc,
                  [{img_obj_num, img_body} | objs_acc],
                  curr_obj + 1
                }
              end
          end
        end
      )

    {img_res, img_objs, smask_objs, objects}
  end

  defp resources_dict(
         fonts,
         font_resource_names,
         font_obj_numbers,
         images,
         image_resource_names,
         image_obj_numbers
       ) do
    font_entries =
      Enum.map_join(fonts, " ", fn font ->
        "#{font_resource_names[font]} #{font_obj_numbers[font]} 0 R"
      end)

    image_entries =
      Enum.map_join(images, " ", fn img ->
        "#{image_resource_names[img.id]} #{image_obj_numbers[img.id]} 0 R"
      end)

    font_dict = if font_entries != "", do: "/Font << #{font_entries} >>", else: ""
    xobject_dict = if image_entries != "", do: "/XObject << #{image_entries} >>", else: ""

    parts = [font_dict, xobject_dict] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
    "<< #{parts} >>"
  end

  defp stream_body(content_bytes) do
    length = IO.iodata_length(content_bytes)
    "<< /Length #{length} >>\nstream\n#{IO.iodata_to_binary(content_bytes)}\nendstream"
  end

  defp assemble(header, objects) do
    initial = {[], %{}, byte_size(header)}

    {body_iodata, offsets, xref_offset} =
      Enum.reduce(objects, initial, fn {num, body}, {acc, offsets, current_offset} ->
        chunk = "#{num} 0 obj\n#{body}\nendobj\n"
        {[acc, chunk], Map.put(offsets, num, current_offset), current_offset + byte_size(chunk)}
      end)

    max_num = objects |> Enum.map(&elem(&1, 0)) |> Enum.max(fn -> 0 end)
    xref_table = format_xref(offsets, max_num)
    trailer = "<< /Size #{max_num + 1} /Root 1 0 R >>"

    IO.iodata_to_binary([
      header,
      body_iodata,
      "xref\n0 #{max_num + 1}\n",
      xref_table,
      "trailer\n",
      trailer,
      "\nstartxref\n#{xref_offset}\n%%EOF"
    ])
  end

  defp format_xref(offsets, max_num) do
    for num <- 0..max_num do
      case Map.get(offsets, num) do
        nil ->
          "0000000000 65535 f\r\n"

        offset ->
          padded = offset |> Integer.to_string() |> String.pad_leading(10, "0")
          "#{padded} 00000 n\r\n"
      end
    end
  end

  defp page_obj_num(index), do: 3 + 2 * index
  defp contents_obj_num(index), do: 4 + 2 * index
end
