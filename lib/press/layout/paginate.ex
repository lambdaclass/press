defmodule Press.Layout.Paginate do
  @moduledoc false

  alias Press.Layout.{Box, Page}

  @doc """
  Splits a laid out root box into discrete pages.
  """
  def paginate(%Box{children: children}, page_config) do
    {_page_width, page_height} = page_config.size
    margin = page_config.margin

    header_box = Enum.find(children, &(&1.tag == "header"))
    footer_box = Enum.find(children, &(&1.tag == "footer"))

    header_h = if header_box, do: Box.outer_height(header_box), else: 0.0
    footer_h = if footer_box, do: Box.outer_height(footer_box), else: 0.0

    usable_height = max(10.0, page_height - margin.top - margin.bottom)
    flow_height = max(10.0, usable_height - header_h - footer_h)
    flow_start_y = margin.top + header_h
    footer_y = page_height - margin.bottom - footer_h

    flow_items = Enum.reject(children, &(&1.tag in ["header", "footer"]))

    do_paginate(
      flow_items,
      flow_height,
      flow_start_y,
      [],
      0.0,
      [],
      1,
      header_box,
      footer_box,
      footer_y,
      page_config
    )
  end

  defp do_paginate(
         [],
         _flow_h,
         _flow_start_y,
         current_page_boxes,
         _current_y,
         pages_acc,
         page_num,
         header,
         footer,
         footer_y,
         page_config
       ) do
    if current_page_boxes != [] or pages_acc == [] do
      page =
        build_page(
          current_page_boxes,
          page_num,
          header,
          footer,
          footer_y,
          page_config
        )

      Enum.reverse([page | pages_acc])
    else
      Enum.reverse(pages_acc)
    end
  end

  defp do_paginate(
         [box | rest],
         flow_h,
         flow_start_y,
         current_page_boxes,
         current_y,
         pages_acc,
         page_num,
         header,
         footer,
         footer_y,
         page_config
       ) do
    box_h = Box.outer_height(box)

    is_break_before = get_page_break(box, "page-break-before") == :always

    if is_break_before and current_page_boxes != [] do
      page =
        build_page(
          current_page_boxes,
          page_num,
          header,
          footer,
          footer_y,
          page_config
        )

      do_paginate(
        [box | rest],
        flow_h,
        flow_start_y,
        [],
        0.0,
        [page | pages_acc],
        page_num + 1,
        header,
        footer,
        footer_y,
        page_config
      )
    else
      if current_y + box_h <= flow_h or current_page_boxes == [] do
        placed_box = shift_box_y(box, flow_start_y + current_y - box.y)
        new_current_boxes = current_page_boxes ++ [placed_box]
        new_current_y = current_y + box_h

        is_break_after = get_page_break(box, "page-break-after") == :always

        if is_break_after do
          page =
            build_page(
              new_current_boxes,
              page_num,
              header,
              footer,
              footer_y,
              page_config
            )

          do_paginate(
            rest,
            flow_h,
            flow_start_y,
            [],
            0.0,
            [page | pages_acc],
            page_num + 1,
            header,
            footer,
            footer_y,
            page_config
          )
        else
          do_paginate(
            rest,
            flow_h,
            flow_start_y,
            new_current_boxes,
            new_current_y,
            pages_acc,
            page_num,
            header,
            footer,
            footer_y,
            page_config
          )
        end
      else
        page =
          build_page(
            current_page_boxes,
            page_num,
            header,
            footer,
            footer_y,
            page_config
          )

        do_paginate(
          [box | rest],
          flow_h,
          flow_start_y,
          [],
          0.0,
          [page | pages_acc],
          page_num + 1,
          header,
          footer,
          footer_y,
          page_config
        )
      end
    end
  end

  defp build_page(boxes, number, header, footer, footer_y, page_config) do
    {page_width, page_height} = page_config.size

    page_boxes = []

    page_boxes =
      if header do
        header_placed = shift_box_y(header, page_config.margin.top - header.y)
        page_boxes ++ [header_placed]
      else
        page_boxes
      end

    page_boxes = page_boxes ++ boxes

    page_boxes =
      if footer do
        footer_placed = shift_box_y(footer, footer_y - footer.y)
        page_boxes ++ [footer_placed]
      else
        page_boxes
      end

    %Page{
      number: number,
      width: page_width,
      height: page_height,
      margin: page_config.margin,
      boxes: page_boxes
    }
  end

  defp shift_box_y(%Box{} = box, delta_y) do
    %Box{
      box
      | y: box.y + delta_y,
        children: Enum.map(box.children, &shift_box_y(&1, delta_y))
    }
  end

  defp get_page_break(%Box{computed: computed}, key) when is_map(computed) do
    Map.get(computed, key)
  end

  defp get_page_break(_, _), do: nil
end
