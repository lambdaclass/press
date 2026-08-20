defmodule Press.Layout.Table do
  @moduledoc false

  alias Press.Layout.{Block, Box}
  alias Press.Style.Node

  @doc """
  Lays out a <table> node.
  Returns `{table_box, next_y, margin_bottom}`.
  """
  def layout_table(%Node{} = table_node, containing_width, container_x, start_y) do
    computed = table_node.computed

    margin = resolve_box_dimensions(computed.margin, containing_width)
    padding = resolve_box_dimensions(computed.padding, containing_width)
    border_width = resolve_box_dimensions(computed.border_width, containing_width)

    table_width =
      case computed.width do
        {:percent, p} ->
          p / 100.0 * containing_width

        n when is_number(n) ->
          n * 1.0

        :auto ->
          max(
            0.0,
            containing_width - margin.left - margin.right - padding.left - padding.right -
              border_width.left - border_width.right
          )
      end

    table_x = container_x + margin.left
    table_y = start_y + margin.top

    content_origin_x = table_x + border_width.left + padding.left
    content_origin_y = table_y + border_width.top + padding.top

    row_nodes = extract_rows(table_node.children)

    col_count = count_columns(row_nodes)
    column_widths = calculate_column_widths(row_nodes, col_count, table_width)

    {row_boxes, total_height} =
      Enum.reduce(row_nodes, {[], 0.0}, fn row_node, {r_acc, curr_y} ->
        {row_box, row_height} =
          layout_row(row_node, column_widths, content_origin_x, content_origin_y + curr_y)

        {[row_box | r_acc], curr_y + row_height}
      end)

    table_box = %Box{
      type: :table,
      tag: "table",
      x: table_x,
      y: table_y,
      width: table_width,
      height: total_height,
      margin: margin,
      padding: padding,
      border_width: border_width,
      border_color: computed.border_color,
      border_style: computed.border_style,
      background_color: computed.background_color,
      computed: computed,
      children: Enum.reverse(row_boxes)
    }

    next_y =
      table_y + total_height + padding.top + padding.bottom + border_width.top +
        border_width.bottom

    {table_box, next_y, margin.bottom}
  end

  defp extract_rows(children) do
    Enum.flat_map(children, fn
      %Node{element: %{tag: "tr"}} = tr ->
        [tr]

      %Node{element: %{tag: section}, children: section_children}
      when section in ["thead", "tbody", "tfoot"] ->
        extract_rows(section_children)

      _ ->
        []
    end)
  end

  defp count_columns(row_nodes) do
    row_nodes
    |> Enum.map(fn row_node ->
      row_node.children
      |> Enum.filter(&is_cell_node/1)
      |> Enum.map(&get_colspan/1)
      |> Enum.sum()
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp get_colspan(%Node{element: %{attrs: %{"colspan" => str}}}) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp get_colspan(_), do: 1

  defp is_cell_node(%Node{element: %{tag: tag}}), do: tag in ["th", "td"]
  defp is_cell_node(_), do: false

  defp calculate_column_widths(_row_nodes, 0, table_width), do: [table_width]

  defp calculate_column_widths(row_nodes, col_count, table_width) do
    explicit_widths =
      for c <- 0..(col_count - 1) do
        row_nodes
        |> Enum.find_value(nil, fn %Node{children: children} ->
          cells = Enum.filter(children, &is_cell_node/1)

          cells
          |> Enum.reduce_while({0, nil}, fn cell, {idx, _val} ->
            span = get_colspan(cell)

            if c >= idx and c < idx + span do
              w =
                case cell.computed.width do
                  {:percent, p} -> p / 100.0 * table_width / span
                  n when is_number(n) -> n * 1.0 / span
                  _ -> nil
                end

              {:halt, w}
            else
              {:cont, {idx + span, nil}}
            end
          end)
        end)
      end

    content_weights =
      for c <- 0..(col_count - 1) do
        if Enum.at(explicit_widths, c) do
          nil
        else
          max_w =
            row_nodes
            |> Enum.map(fn %Node{children: children} ->
              cells = Enum.filter(children, &is_cell_node/1)

              cells
              |> Enum.reduce_while({0, 10.0}, fn cell, {idx, _val} ->
                span = get_colspan(cell)

                if c >= idx and c < idx + span do
                  {:halt, estimate_cell_text_width(cell) / span}
                else
                  {:cont, {idx + span, 10.0}}
                end
              end)
            end)
            |> Enum.max(fn -> 10.0 end)

          max(25.0, max_w + 16.0)
        end
      end

    total_explicit = explicit_widths |> Enum.reject(&is_nil/1) |> Enum.sum()
    unspecified_weights = Enum.reject(content_weights, &is_nil/1)
    total_unspecified_weight = Enum.sum(unspecified_weights)
    remaining_table_width = max(0.0, table_width - total_explicit)

    resolved_unspecified =
      if total_unspecified_weight > 0 do
        Enum.map(unspecified_weights, fn w ->
          w / total_unspecified_weight * remaining_table_width
        end)
      else
        count = max(1, length(unspecified_weights))
        Enum.map(unspecified_weights, fn _ -> remaining_table_width / count end)
      end

    {final_widths, _} =
      Enum.reduce(explicit_widths, {[], resolved_unspecified}, fn
        w, {acc, unspec} when not is_nil(w) ->
          {[w | acc], unspec}

        nil, {acc, [u | rest_u]} ->
          {[u | acc], rest_u}
      end)

    Enum.reverse(final_widths)
  end

  defp estimate_cell_text_width(%Node{} = node) do
    texts =
      node
      |> collect_text_strings()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    fs = (is_number(node.computed.font_size) && node.computed.font_size) || 12.0

    font =
      case {node.computed.font_family, node.computed.font_weight} do
        {:helvetica, :bold} -> :helvetica_bold
        {:times, :bold} -> :times_bold
        {:courier, :bold} -> :courier_bold
        {f, _} -> f || :helvetica
      end

    Enum.map(texts, fn t ->
      Press.Font.Metrics.text_width(font, t, fs)
    end)
    |> Enum.max(fn -> 10.0 end)
  end

  defp collect_text_strings(%Node{children: children}) do
    Enum.flat_map(children, &collect_text_strings/1)
  end

  defp collect_text_strings(%Press.Style.Text{content: c}), do: [c]
  defp collect_text_strings(_), do: []

  defp layout_row(%Node{} = row_node, column_widths, origin_x, row_y) do
    cells = Enum.filter(row_node.children, &is_cell_node/1)

    {cell_boxes, _final_x, _final_c_idx} =
      cells
      |> Enum.reduce({[], origin_x, 0}, fn cell_node, {c_acc, curr_x, c_idx} ->
        span = get_colspan(cell_node)
        col_width = column_widths |> Enum.slice(c_idx, span) |> Enum.sum()

        cell_node_unconstrained = put_in(cell_node.computed.width, :auto)

        {cell_box, _next_y, _m} =
          Block.layout_block(cell_node_unconstrained, col_width, curr_x, row_y)

        cell_bg = cell_node.computed.background_color || row_node.computed.background_color

        cell_box = %Box{
          cell_box
          | type: :table_cell,
            x: curr_x,
            y: row_y,
            background_color: cell_bg
        }

        {[cell_box | c_acc], curr_x + col_width, c_idx + span}
      end)

    cell_boxes = Enum.reverse(cell_boxes)

    content_row_height =
      Enum.map(cell_boxes, fn c ->
        c.height + c.padding.top + c.padding.bottom + c.border_width.top + c.border_width.bottom
      end)
      |> Enum.max(fn -> 0.0 end)

    specified_row_height =
      case row_node.computed.height do
        n when is_number(n) -> n * 1.0
        _ -> 0.0
      end

    row_height = max(content_row_height, specified_row_height)

    stretched_cells =
      Enum.map(cell_boxes, fn cell ->
        target_content_h =
          max(
            0.0,
            row_height - cell.padding.top - cell.padding.bottom - cell.border_width.top -
              cell.border_width.bottom
          )

        if target_content_h > cell.height do
          y_offset = (target_content_h - cell.height) / 2.0
          adjusted_children = Enum.map(cell.children, &shift_box_y(&1, y_offset))
          %Box{cell | height: target_content_h, children: adjusted_children}
        else
          %Box{cell | height: target_content_h}
        end
      end)

    row_width = Enum.sum(column_widths)

    row_box = %Box{
      type: :table_row,
      tag: "tr",
      x: origin_x,
      y: row_y,
      width: row_width,
      height: row_height,
      background_color: row_node.computed.background_color,
      children: stretched_cells
    }

    {row_box, row_height}
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
