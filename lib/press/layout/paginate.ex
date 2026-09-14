defmodule Press.Layout.Paginate do
  @moduledoc false

  alias Press.Layout.{Box, Fragment, Page}

  @doc """
  Splits a laid out root box into discrete pages.
  """
  def paginate(%Box{children: children} = root, page_config) do
    {_page_width, page_height} = page_config.size
    margin = page_config.margin

    header_box = Enum.find(children, &(&1.tag == "header"))
    footer_box = Enum.find(children, &(&1.tag == "footer"))

    header_h = if header_box, do: Box.outer_height(header_box), else: 0.0
    footer_h = if footer_box, do: Box.outer_height(footer_box), else: 0.0

    # `<html>`/`<body>` are one box spanning every page: their top padding
    # indents the first page only, their bottom padding the last.
    top_of_page = margin.top + header_h

    ctx = %{
      page_top: top_of_page,
      flow_start_y: top_of_page + root.padding.top,
      page_bottom:
        max(
          top_of_page + 10.0,
          page_height - margin.bottom - footer_h - root.padding.bottom
        ),
      header: header_box,
      footer: footer_box,
      footer_y: page_height - margin.bottom - footer_h,
      page_config: page_config
    }

    flow_items = Enum.reject(children, &(&1.tag in ["header", "footer"]))

    do_paginate(flow_items, ctx, [], 0.0, [], 1)
  end

  defp do_paginate([], ctx, current_page_boxes, _page_shift, pages_acc, page_num) do
    if current_page_boxes != [] or pages_acc == [] do
      Enum.reverse([build_page(current_page_boxes, page_num, ctx) | pages_acc])
    else
      Enum.reverse(pages_acc)
    end
  end

  defp do_paginate([box | rest], ctx, current_page_boxes, page_shift, pages_acc, page_num) do
    page_empty? = current_page_boxes == []

    # A page keeps the y the layout gave each box and moves the whole page by a
    # single offset. Re-stacking them by height would add back the margins that
    # collapsed between siblings.
    shift = if page_empty?, do: ctx.flow_start_y - margin_box_top(box), else: page_shift

    next_page = fn queue, page ->
      do_paginate(
        queue,
        %{ctx | flow_start_y: ctx.page_top},
        [],
        0.0,
        [page | pages_acc],
        page_num + 1
      )
    end

    emit = fn boxes -> build_page(boxes, page_num, ctx) end

    place = fn ->
      placed = current_page_boxes ++ [shift_box_y(box, shift)]

      if get_page_break(box, :page_break_after) == :always do
        next_page.(rest, emit.(placed))
      else
        do_paginate(rest, ctx, placed, shift, pages_acc, page_num)
      end
    end

    cond do
      get_page_break(box, :page_break_before) == :always and not page_empty? ->
        next_page.([box | rest], emit.(current_page_boxes))

      margin_box_top(box) + shift + Box.outer_height(box) <= ctx.page_bottom ->
        place.()

      # `page-break-inside: avoid` only asks to be kept whole. A box that no
      # page can hold has to break anyway, so the request is honoured by moving
      # it to a fresh page, not by refusing to place it.
      Fragment.keep_whole?(box) and not page_empty? ->
        next_page.([box | rest], emit.(current_page_boxes))

      true ->
        # Too tall for what is left. Break inside it if it has a break
        # opportunity above the page edge, otherwise push it whole to the next
        # page — and if the page is already empty, place it anyway rather than
        # loop forever on a box no page can hold.
        # A box asking to be kept whole has already been moved to a page of its
        # own by the clause above. Reaching here means no page can hold it, so
        # the request is dropped rather than letting it run off the sheet.
        case Fragment.split(box, ctx.page_bottom - shift, not page_empty?) do
          {:split, head, tail} ->
            next_page.([tail | rest], emit.(current_page_boxes ++ [shift_box_y(head, shift)]))

          :indivisible when page_empty? ->
            place.()

          :indivisible ->
            next_page.([box | rest], emit.(current_page_boxes))
        end
    end
  end

  defp build_page(boxes, number, ctx) do
    {page_width, page_height} = ctx.page_config.size
    margin = ctx.page_config.margin

    header =
      if ctx.header, do: [shift_box_y(ctx.header, margin.top - ctx.header.y)], else: []

    footer =
      if ctx.footer, do: [shift_box_y(ctx.footer, ctx.footer_y - ctx.footer.y)], else: []

    %Page{
      number: number,
      width: page_width,
      height: page_height,
      margin: margin,
      boxes: header ++ boxes ++ footer
    }
  end

  defp margin_box_top(%Box{y: y, margin: %{top: t}}) when is_number(t), do: y - t
  defp margin_box_top(%Box{y: y}), do: y

  defp shift_box_y(%Box{} = box, delta_y) do
    %Box{box | y: box.y + delta_y, children: Enum.map(box.children, &shift_box_y(&1, delta_y))}
  end

  defp get_page_break(%Box{computed: computed}, key) when is_map(computed) do
    Map.get(computed, key)
  end

  defp get_page_break(_, _), do: nil
end
