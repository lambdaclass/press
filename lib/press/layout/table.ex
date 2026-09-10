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
          border_box_deduct(p / 100.0 * containing_width, computed, padding, border_width)

        n when is_number(n) ->
          border_box_deduct(n * 1.0, computed, padding, border_width)

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

    tagged_rows = extract_rows(table_node.children)
    row_nodes = Enum.map(tagged_rows, &elem(&1, 0))

    col_count = count_columns(row_nodes)
    col_hints = extract_col_widths(table_node.children, table_width)

    column_widths =
      calculate_column_widths(
        row_nodes,
        col_count,
        table_width,
        col_hints,
        Map.get(computed, :table_layout, :auto)
      )

    {row_boxes, total_height} =
      Enum.reduce(tagged_rows, {[], 0.0}, fn {row_node, header?}, {r_acc, curr_y} ->
        {row_box, row_height} =
          layout_row(row_node, column_widths, content_origin_x, content_origin_y + curr_y)

        {[%Box{row_box | header_row: header?} | r_acc], curr_y + row_height}
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

  defp border_box_deduct(width, computed, padding, border) do
    case Map.get(computed, :box_sizing) do
      :"border-box" ->
        max(0.0, width - padding.left - padding.right - border.left - border.right)

      _ ->
        width
    end
  end

  defp extract_rows(children, in_header \\ false) do
    Enum.flat_map(children, fn
      %Node{element: %{tag: "tr"}} = tr ->
        [{tr, in_header}]

      %Node{element: %{tag: section}, children: section_children}
      when section in ["thead", "tbody", "tfoot"] ->
        extract_rows(section_children, section == "thead")

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

  @min_column_width 12.0

  defp is_cell_node(%Node{element: %{tag: tag}}), do: tag in ["th", "td"]
  defp is_cell_node(_), do: false

  # `<colgroup><col style="width: …">` sets a column's width without any cell
  # carrying it, so the hints are collected before the cells are consulted.
  defp extract_col_widths(children, table_width) do
    children
    |> Enum.flat_map(fn
      %Node{element: %{tag: "colgroup"}, children: cols} -> cols
      %Node{element: %{tag: "col"}} = col -> [col]
      _ -> []
    end)
    |> Enum.filter(&match?(%Node{element: %{tag: "col"}}, &1))
    |> Enum.flat_map(fn col ->
      span = get_colspan_attr(col, "span")

      width =
        case col.computed.width do
          {:percent, p} -> p / 100.0 * table_width
          n when is_number(n) -> n * 1.0
          _ -> nil
        end

      List.duplicate(width, span)
    end)
  end

  defp get_colspan_attr(%Node{element: %{attrs: attrs}}, name) do
    case Integer.parse(Map.get(attrs, name, "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp calculate_column_widths(_row_nodes, 0, table_width, _hints, _layout), do: [table_width]

  defp calculate_column_widths(row_nodes, col_count, table_width, col_hints, table_layout) do
    declared =
      0..(col_count - 1)
      |> Enum.map(fn c -> declared_width(row_nodes, c, table_width) end)
      |> Enum.with_index()
      |> Enum.map(fn {w, i} -> w || Enum.at(col_hints, i) end)

    if table_layout == :fixed do
      fixed_widths(declared, table_width)
    else
      auto_widths(row_nodes, col_count, table_width, declared)
    end
  end

  # `table-layout: fixed` never measures content: the declared widths stand and
  # whatever is left is split equally between the rest.
  defp fixed_widths(declared, table_width) do
    known = declared |> Enum.reject(&is_nil/1) |> Enum.sum()
    unknown = Enum.count(declared, &is_nil/1)
    share = if unknown > 0, do: max(0.0, table_width - known) / unknown, else: 0.0

    Enum.map(declared, fn
      nil -> share
      w -> w
    end)
  end

  # CSS 2.1 §17.5.2.2. Each column is measured twice — the width it needs to
  # avoid overflowing a word (min-content) and the width it would take with no
  # wrapping at all (max-content) — and the table's space is handed out between
  # those two bounds. Distributing by max-content alone, as a single weight,
  # gives a column holding one long sentence most of the table.
  defp auto_widths(row_nodes, col_count, table_width, declared) do
    bounds =
      0..(col_count - 1)
      |> Enum.map(fn c ->
        case Enum.at(declared, c) do
          nil -> column_bounds(row_nodes, c)
          w -> {w, w}
        end
      end)

    mins = Enum.map(bounds, &elem(&1, 0))
    maxs = Enum.map(bounds, &elem(&1, 1))
    total_min = Enum.sum(mins)
    total_max = Enum.sum(maxs)

    cond do
      total_max <= table_width ->
        grow_from(maxs, maxs, table_width - total_max, total_max)

      total_min <= table_width ->
        slack = Enum.zip(mins, maxs) |> Enum.map(fn {lo, hi} -> hi - lo end)
        grow_from(mins, slack, table_width - total_min, Enum.sum(slack))

      true ->
        shrink_to(mins, table_width, total_min)
    end
  end

  defp grow_from(base, weights, extra, total_weight) when total_weight > 0 do
    Enum.zip(base, weights) |> Enum.map(fn {b, w} -> b + extra * w / total_weight end)
  end

  defp grow_from(base, _weights, extra, _total_weight) do
    share = extra / max(1, length(base))
    Enum.map(base, &(&1 + share))
  end

  defp shrink_to(mins, table_width, total_min) when total_min > 0 do
    Enum.map(mins, &(&1 * table_width / total_min))
  end

  defp shrink_to(mins, _table_width, _total_min), do: mins

  defp column_bounds(row_nodes, c) do
    row_nodes
    |> Enum.map(fn row -> cell_bounds_at(row, c) end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        {@min_column_width, @min_column_width}

      pairs ->
        {
          max(@min_column_width, pairs |> Enum.map(&elem(&1, 0)) |> Enum.max()),
          max(@min_column_width, pairs |> Enum.map(&elem(&1, 1)) |> Enum.max())
        }
    end
  end

  # A cell spanning several columns contributes an even share to each of them.
  defp cell_bounds_at(%Node{children: children}, c) do
    children
    |> Enum.filter(&is_cell_node/1)
    |> Enum.reduce_while(0, fn cell, idx ->
      span = get_colspan(cell)

      if c >= idx and c < idx + span do
        surround = cell_surround(cell)

        {:halt,
         {min_cell_text_width(cell) / span + surround,
          estimate_cell_text_width(cell) / span + surround}}
      else
        {:cont, idx + span}
      end
    end)
    |> case do
      idx when is_integer(idx) -> nil
      bounds -> bounds
    end
  end

  defp cell_surround(%Node{computed: computed}) do
    side = fn box, key ->
      case box && Map.get(box, key) do
        n when is_number(n) -> n * 1.0
        _ -> 0.0
      end
    end

    side.(computed.padding, :left) + side.(computed.padding, :right) +
      side.(computed.border_width, :left) + side.(computed.border_width, :right)
  end

  # Min-content is the longest single word: below that the text overflows
  # instead of wrapping.
  defp min_cell_text_width(%Node{} = node) do
    {font, fs} = cell_font(node)

    node
    |> collect_text_strings()
    |> Enum.flat_map(&String.split(&1, ~r/\s+/, trim: true))
    |> Enum.map(&Press.Font.Metrics.text_width(font, &1, fs))
    |> Enum.max(fn -> 0.0 end)
  end

  defp cell_font(%Node{computed: computed}) do
    fs = (is_number(computed.font_size) && computed.font_size) || 12.0

    font =
      case {computed.font_family, computed.font_weight} do
        {:helvetica, :bold} -> :helvetica_bold
        {:times, :bold} -> :times_bold
        {:courier, :bold} -> :courier_bold
        {f, _} -> f || :helvetica
      end

    {font, fs}
  end

  defp declared_width(row_nodes, c, table_width) do
    row_nodes
    |> Enum.find_value(nil, fn row ->
      row.children
      |> Enum.filter(&is_cell_node/1)
      |> Enum.reduce_while(0, fn cell, idx ->
        span = get_colspan(cell)

        if c >= idx and c < idx + span do
          {:halt,
           case cell.computed.width do
             {:percent, p} -> p / 100.0 * table_width / span
             n when is_number(n) -> n * 1.0 / span
             _ -> nil
           end}
        else
          {:cont, idx + span}
        end
      end)
      |> case do
        idx when is_integer(idx) -> nil
        width -> width
      end
    end)
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
