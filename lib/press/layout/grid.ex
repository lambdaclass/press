defmodule Press.Layout.Grid do
  @moduledoc false

  alias Press.Layout.{Block, Box}
  alias Press.Style.{Node, Text}

  @doc """
  Lays out a CSS Grid container (e.g. 12-column grid with col-span and gaps).
  Returns `{box, next_y, margin_bottom}`.
  """
  def layout_grid(%Node{} = node, containing_width, container_x, start_y, images \\ %{}) do
    computed = node.computed
    classes = Map.get(node.element.attrs, "class", "") |> String.split()

    margin = resolve_box_dimensions(computed.margin, containing_width)
    padding = resolve_box_dimensions(computed.padding, containing_width)
    border_width = resolve_box_dimensions(computed.border_width, containing_width)

    content_width =
      max(
        0.0,
        containing_width - margin.left - margin.right - padding.left - padding.right -
          border_width.left - border_width.right
      )

    box_x = container_x + margin.left
    box_y = start_y + margin.top

    content_origin_x = box_x + border_width.left + padding.left
    content_origin_y = box_y + border_width.top + padding.top

    total_cols = parse_grid_cols(classes)
    col_gap = parse_gap(classes, ~r/gap-x-(\d+)/, ~r/gap-(\d+)/, 12.0)
    row_gap = parse_gap(classes, ~r/gap-y-(\d+)/, ~r/gap-(\d+)/, 18.0)

    col_unit_width = max(0.0, content_width - (total_cols - 1) * col_gap) / total_cols

    visual_children = filter_visual_children(node.children)
    rows = group_grid_rows(visual_children, total_cols)

    {row_boxes, content_height} =
      Enum.reduce(rows, {[], 0.0}, fn row_items, {r_acc, curr_y} ->
        {cell_boxes, row_h} =
          layout_grid_row(
            row_items,
            col_unit_width,
            col_gap,
            content_origin_x,
            content_origin_y + curr_y,
            images
          )

        {cell_boxes ++ r_acc, curr_y + row_h + row_gap}
      end)

    actual_content_height = max(0.0, content_height - if(rows != [], do: row_gap, else: 0.0))

    total_outer_height =
      actual_content_height + padding.top + padding.bottom + border_width.top +
        border_width.bottom

    box = %Box{
      type: :block,
      tag: node.element.tag,
      x: box_x,
      y: box_y,
      width: content_width,
      height: actual_content_height,
      margin: margin,
      padding: padding,
      border_width: border_width,
      border_color: computed.border_color,
      border_style: computed.border_style,
      background_color: computed.background_color,
      computed: computed,
      children: Enum.reverse(row_boxes)
    }

    next_y = box_y + total_outer_height
    {box, next_y, margin.bottom}
  end

  def grid?(%Node{} = node) do
    classes = Map.get(node.element.attrs, "class", "") |> String.split()
    "grid" in classes
  end

  def grid?(_), do: false

  defp filter_visual_children(children) do
    Enum.reject(children, fn
      %Node{element: %{tag: tag}} -> tag in ~w(head style link meta script title iframe)
      %Text{content: c} -> String.trim(c) == ""
      _ -> false
    end)
  end

  defp parse_grid_cols(classes) do
    class_str = Enum.join(classes, " ")

    case Regex.run(~r/grid-cols-(\d+)/, class_str) do
      [_, val] ->
        case Integer.parse(val) do
          {n, ""} when n > 0 -> n
          _ -> 12
        end

      _ ->
        12
    end
  end

  defp parse_gap(classes, specific_regex, generic_regex, default) do
    class_str = Enum.join(classes, " ")

    case Regex.run(specific_regex, class_str) do
      [_, val] ->
        elem(Float.parse(val), 0) * 3.0

      _ ->
        case Regex.run(generic_regex, class_str) do
          [_, val] -> elem(Float.parse(val), 0) * 3.0
          _ -> default
        end
    end
  end

  defp get_span(%Node{} = n) do
    cls = Map.get(n.element.attrs, "class", "")

    case Regex.run(~r/col-span-(\d+)/, cls) do
      [_, s] -> elem(Integer.parse(s), 0)
      _ -> 12
    end
  end

  defp get_span(_), do: 12

  defp group_grid_rows(children, total_cols) do
    {rows, current_row, _cur_span} =
      Enum.reduce(children, {[], [], 0}, fn child, {rows_acc, row_acc, span_acc} ->
        span = min(total_cols, get_span(child))

        if span_acc + span <= total_cols do
          {rows_acc, row_acc ++ [{child, span, span_acc}], span_acc + span}
        else
          new_rows = if row_acc != [], do: rows_acc ++ [row_acc], else: rows_acc
          {new_rows, [{child, span, 0}], span}
        end
      end)

    if current_row != [], do: rows ++ [current_row], else: rows
  end

  defp layout_grid_row(row_items, col_unit_width, col_gap, origin_x, row_y, images) do
    {boxes, max_h} =
      Enum.reduce(row_items, {[], 0.0}, fn {child, span, col_offset}, {acc, h_acc} ->
        cell_w = span * col_unit_width + (span - 1) * col_gap
        cell_x = origin_x + col_offset * (col_unit_width + col_gap)

        {child_box, next_y, _} =
          case child do
            %Node{element: %{tag: "table"}} = table_node ->
              Press.Layout.Table.layout_table(table_node, cell_w, cell_x, row_y)

            %Node{element: %{tag: "img"}} = img_node ->
              Press.Layout.Image.layout_image(img_node, images, cell_w, cell_x, row_y)

            %Node{} = block_node ->
              Block.layout_block(block_node, cell_w, cell_x, row_y, images)

            %Text{} = text ->
              line_boxes = Press.Layout.Inline.wrap([text], cell_w, :left)

              {placed, h} =
                Enum.reduce(line_boxes, {[], 0.0}, fn line, {l_acc, y} ->
                  placed_line = %Box{
                    line
                    | x: cell_x,
                      y: row_y + y,
                      children:
                        Enum.map(line.children, fn c ->
                          %Box{c | x: cell_x + c.x, y: row_y + y + c.y}
                        end)
                  }

                  {[placed_line | l_acc], y + line.height}
                end)

              box = %Box{
                type: :block,
                x: cell_x,
                y: row_y,
                width: cell_w,
                height: h,
                children: Enum.reverse(placed)
              }

              {box, row_y + h, 0.0}
          end

        child_h = next_y - row_y
        {[child_box | acc], max(h_acc, child_h)}
      end)

    explicit_h = find_explicit_height(row_items)

    stretched_boxes =
      if explicit_h && explicit_h > 0.0 do
        Enum.map(boxes, &stretch_grid_item(&1, max_h))
      else
        boxes
      end

    {stretched_boxes, max_h}
  end

  defp find_explicit_height(row_items) do
    Enum.find_value(row_items, nil, fn {child, _span, _offset} ->
      node_explicit_height(child)
    end)
  end

  defp node_explicit_height(%Node{computed: %{height: n}}) when is_number(n) and n > 0.0,
    do: n * 1.0

  defp node_explicit_height(%Node{computed: %{min_height: n}}) when is_number(n) and n > 0.0,
    do: n * 1.0

  defp node_explicit_height(%Node{children: children}) do
    Enum.find_value(children, nil, &node_explicit_height/1)
  end

  defp node_explicit_height(_), do: nil

  defp stretch_grid_item(
         %Box{type: :block, tag: "div", children: [%Box{type: :table} = tbl_box]} = div_box,
         max_h
       ) do
    stretched_tbl = stretch_table(tbl_box, max_h)
    %Box{div_box | height: max_h, children: [stretched_tbl]}
  end

  defp stretch_grid_item(%Box{type: :table} = tbl_box, max_h) do
    stretch_table(tbl_box, max_h)
  end

  defp stretch_grid_item(%Box{type: :block} = box, max_h) do
    %Box{box | height: max_h}
  end

  defp stretch_grid_item(box, _max_h), do: box

  defp stretch_table(%Box{type: :table, children: row_boxes} = tbl_box, max_h) do
    row_count = length(row_boxes)

    if row_count > 0 and max_h > tbl_box.height do
      target_row_h = max_h / row_count

      stretched_rows =
        row_boxes
        |> Enum.with_index()
        |> Enum.map(fn {row, idx} ->
          new_row_y = tbl_box.y + idx * target_row_h

          stretched_cells =
            Enum.map(row.children, fn cell ->
              target_content_h =
                max(
                  0.0,
                  target_row_h - cell.padding.top - cell.padding.bottom - cell.border_width.top -
                    cell.border_width.bottom
                )

              y_offset = max(0.0, (target_content_h - cell.height) / 2.0)
              adj_cell_children = Enum.map(cell.children, &shift_box_y(&1, y_offset))
              %Box{cell | y: new_row_y, height: target_content_h, children: adj_cell_children}
            end)

          %Box{row | y: new_row_y, height: target_row_h, children: stretched_cells}
        end)

      %Box{tbl_box | height: max_h, children: stretched_rows}
    else
      tbl_box
    end
  end

  defp shift_box_y(%Box{children: children} = box, y_offset) do
    %Box{
      box
      | y: box.y + y_offset,
        children: Enum.map(children, &shift_box_y(&1, y_offset))
    }
  end

  defp resolve_box_dimensions(%{top: t, right: r, bottom: b, left: l}, containing_width) do
    %{
      top: resolve_dimension(t, containing_width),
      right: resolve_dimension(r, containing_width),
      bottom: resolve_dimension(b, containing_width),
      left: resolve_dimension(l, containing_width)
    }
  end

  defp resolve_dimension({:percent, p}, containing_width), do: p / 100.0 * containing_width
  defp resolve_dimension(n, _containing_width) when is_number(n), do: n * 1.0
  defp resolve_dimension(_, _), do: 0.0
end
