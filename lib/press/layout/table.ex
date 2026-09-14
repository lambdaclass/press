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

    grid = assign_grid(row_nodes)
    col_count = count_columns(grid)
    col_hints = extract_col_widths(table_node.children, table_width)

    grid =
      if Map.get(computed, :border_collapse) == :collapse,
        do: collapse_borders(grid, col_count),
        else: grid

    column_widths =
      calculate_column_widths(
        grid,
        col_count,
        table_width,
        col_hints,
        Map.get(computed, :table_layout, :auto)
      )

    column_offsets = running_offsets(column_widths)

    {measured, _natural_total} =
      tagged_rows
      |> Enum.zip(grid)
      |> Enum.map_reduce(0.0, fn {{row_node, section}, placements}, curr_y ->
        {cells, natural_height} =
          measure_row(
            row_node,
            placements,
            column_widths,
            column_offsets,
            content_origin_x,
            content_origin_y + curr_y
          )

        {{row_node, section, cells, content_origin_y + curr_y, natural_height},
         curr_y + natural_height}
      end)

    row_heights = expand_for_rowspans(measured)
    row_offsets = running_offsets(row_heights)
    total_height = Enum.sum(row_heights)
    row_width = Enum.sum(column_widths)

    row_boxes =
      measured
      |> Enum.with_index()
      |> Enum.map(fn {{row_node, section, cells, provisional_y, _natural}, r} ->
        final_y = content_origin_y + Enum.at(row_offsets, r, 0.0)

        row_box =
          place_row(
            row_node,
            cells,
            r,
            row_heights,
            final_y,
            final_y - provisional_y,
            content_origin_x,
            row_width
          )

        %Box{row_box | header_row: section == "thead", footer_row: section == "tfoot"}
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
      children: row_boxes
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

  defp extract_rows(children, section \\ "tbody") do
    Enum.flat_map(children, fn
      %Node{element: %{tag: "tr"}} = tr ->
        [{tr, section}]

      %Node{element: %{tag: section}, children: section_children}
      when section in ["thead", "tbody", "tfoot"] ->
        extract_rows(section_children, section)

      _ ->
        []
    end)
  end

  @doc false
  def assign_grid(row_nodes) do
    {rows, _occupied} =
      row_nodes
      |> Enum.with_index()
      |> Enum.map_reduce(MapSet.new(), fn {row_node, r}, occupied ->
        row_node.children
        |> Enum.filter(&is_cell_node/1)
        |> Enum.map_reduce(occupied, fn cell, occ ->
          col = first_free_column(occ, r, 0)
          colspan = get_colspan(cell)
          rowspan = get_rowspan(cell)
          {{cell, col, colspan, rowspan}, occupy(occ, r, col, colspan, rowspan)}
        end)
      end)

    rows
  end

  # `border-collapse: collapse` puts one border on the line two cells share,
  # centred on it, so each of them only reserves half. Reserving a whole border
  # per cell makes every row a pixel taller than a browser draws it.
  defp collapse_borders(grid, col_count) do
    rows = length(grid)

    grid
    |> Enum.with_index()
    |> Enum.map(fn {placements, r} ->
      Enum.map(placements, fn {cell, col, colspan, rowspan} ->
        halved =
          cell.computed.border_width
          |> halve(:top, r > 0)
          |> halve(:bottom, r + rowspan < rows)
          |> halve(:left, col > 0)
          |> halve(:right, col + colspan < col_count)

        {put_in(cell.computed.border_width, halved), col, colspan, rowspan}
      end)
    end)
  end

  defp halve(border, _edge, false), do: border

  defp halve(border, edge, true) do
    case Map.get(border, edge) do
      n when is_number(n) -> Map.put(border, edge, n / 2.0)
      _ -> border
    end
  end

  defp first_free_column(occupied, row, col) do
    if MapSet.member?(occupied, {row, col}),
      do: first_free_column(occupied, row, col + 1),
      else: col
  end

  defp occupy(occupied, row, col, colspan, rowspan) do
    for r <- row..(row + rowspan - 1),
        c <- col..(col + colspan - 1),
        reduce: occupied do
      acc -> MapSet.put(acc, {r, c})
    end
  end

  defp get_rowspan(%Node{element: %{attrs: attrs}}) do
    case Integer.parse(Map.get(attrs, "rowspan", "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp get_rowspan(_), do: 1

  defp count_columns(grid) do
    grid
    |> Enum.flat_map(fn placements ->
      Enum.map(placements, fn {_cell, col, colspan, _rowspan} -> col + colspan end)
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

  defp calculate_column_widths(_grid, 0, table_width, _hints, _layout), do: [table_width]

  defp calculate_column_widths(grid, col_count, table_width, col_hints, table_layout) do
    declared =
      0..(col_count - 1)
      |> Enum.map(fn c -> declared_width(grid, c, table_width) end)
      |> Enum.with_index()
      |> Enum.map(fn {w, i} -> w || Enum.at(col_hints, i) end)

    if table_layout == :fixed do
      fixed_widths(declared, table_width)
    else
      auto_widths(grid, col_count, table_width, declared)
    end
  end

  defp fixed_widths(declared, table_width) do
    known = declared |> Enum.reject(&is_nil/1) |> Enum.sum()
    unknown = Enum.count(declared, &is_nil/1)
    share = if unknown > 0, do: max(0.0, table_width - known) / unknown, else: 0.0

    Enum.map(declared, fn
      nil -> share
      w -> w
    end)
  end

  # CSS 2.1 §17.5.2.2: distributing by max-content as a single weight would give
  # a column holding one long sentence most of the table.
  defp auto_widths(grid, col_count, table_width, declared) do
    bounds =
      0..(col_count - 1)
      |> Enum.map(fn c ->
        {min_c, max_c} = column_bounds(grid, c)

        case Enum.at(declared, c) do
          # Under auto layout a declared width is a preference: taken as a
          # reservation, one `width: 100%` column swallows the table.
          nil -> {min_c, max_c}
          w -> {min_c, max(w, min_c)}
        end
      end)

    mins = Enum.map(bounds, &elem(&1, 0))
    maxs = Enum.map(bounds, &elem(&1, 1))
    total_min = Enum.sum(mins)
    total_max = Enum.sum(maxs)

    cond do
      total_max <= table_width ->
        distribute_free(maxs, declared, table_width - total_max)

      total_min <= table_width ->
        slack = Enum.zip(mins, maxs) |> Enum.map(fn {lo, hi} -> hi - lo end)
        grow_from(mins, slack, table_width - total_min, Enum.sum(slack))

      true ->
        shrink_to(mins, table_width, total_min)
    end
  end

  # With room to spare a declared width stands as written; the slack goes to the
  # columns that did not ask for one.
  defp distribute_free(maxs, declared, extra) do
    weights =
      Enum.zip(maxs, declared)
      |> Enum.map(fn
        {m, nil} -> m
        {_m, _w} -> 0.0
      end)

    case Enum.sum(weights) do
      total when total > 0 -> grow_from(maxs, weights, extra, total)
      _ -> grow_from(maxs, maxs, extra, Enum.sum(maxs))
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

  defp column_bounds(grid, c) do
    grid
    |> Enum.map(fn placements -> cell_bounds_at(placements, c) end)
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

  defp cell_bounds_at(placements, c) do
    Enum.find_value(placements, fn {cell, col, colspan, _rowspan} ->
      if c >= col and c < col + colspan do
        surround = cell_surround(cell)

        {min_cell_text_width(cell) / colspan + surround,
         estimate_cell_text_width(cell) / colspan + surround}
      end
    end)
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

  # Under `white-space: nowrap` there is no wrapping, so the whole run — not its
  # longest word — is what the column cannot go below.
  defp min_cell_text_width(%Node{} = node) do
    {font, fs} = cell_font(node)

    node
    |> collect_text_runs()
    |> Enum.flat_map(fn
      {content, true} -> [String.trim(content)]
      {content, false} -> String.split(content, ~r/\s+/, trim: true)
    end)
    |> Enum.map(&Press.Font.Metrics.text_width(font, &1, fs))
    |> Enum.max(fn -> 0.0 end)
  end

  defp collect_text_runs(%Node{children: children}) do
    Enum.flat_map(children, &collect_text_runs/1)
  end

  defp collect_text_runs(%Press.Style.Text{content: c, computed: computed}) do
    [{c, Map.get(computed, :white_space) in [:nowrap, :pre]}]
  end

  defp collect_text_runs(_), do: []

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

  defp declared_width(grid, c, table_width) do
    Enum.find_value(grid, fn placements ->
      Enum.find_value(placements, fn {cell, col, colspan, _rowspan} ->
        if c >= col and c < col + colspan do
          case cell.computed.width do
            {:percent, p} -> p / 100.0 * table_width / colspan
            n when is_number(n) -> n * 1.0 / colspan
            _ -> nil
          end
        end
      end)
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

  defp running_offsets(sizes) do
    sizes
    |> Enum.scan(0.0, &(&1 + &2))
    |> then(&[0.0 | &1])
  end

  defp measure_row(%Node{} = row_node, placements, column_widths, column_offsets, origin_x, row_y) do
    cells =
      Enum.map(placements, fn {cell_node, col, colspan, rowspan} ->
        col_width = column_widths |> Enum.slice(col, colspan) |> Enum.sum()
        cell_x = origin_x + Enum.at(column_offsets, col, 0.0)

        {cell_box, _next_y, _m} =
          Block.layout_block(put_in(cell_node.computed.width, :auto), col_width, cell_x, row_y)

        box = %Box{
          cell_box
          | type: :table_cell,
            x: cell_x,
            y: row_y,
            background_color:
              cell_node.computed.background_color || row_node.computed.background_color
        }

        {box, col, colspan, rowspan}
      end)

    {cells, natural_height(cells, row_node)}
  end

  defp natural_height(cells, row_node) do
    specified =
      case row_node.computed.height do
        n when is_number(n) -> n * 1.0
        _ -> 0.0
      end

    from_content =
      case Enum.filter(cells, fn {_box, _col, _colspan, rowspan} -> rowspan <= 1 end) do
        [] ->
          cells
          |> Enum.map(fn {box, _col, _colspan, rowspan} -> outer_height(box) / rowspan end)
          |> Enum.max(fn -> 0.0 end)

        single ->
          single |> Enum.map(fn {box, _, _, _} -> outer_height(box) end) |> Enum.max(fn -> 0.0 end)
      end

    max(from_content, specified)
  end

  defp expand_for_rowspans(measured) do
    measured
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_node, _header?, cells, _y, _natural}, r} ->
      for {box, _col, _colspan, rowspan} <- cells, rowspan > 1, do: {r, rowspan, outer_height(box)}
    end)
    |> Enum.sort_by(fn {r, rowspan, _needed} -> r + rowspan end)
    |> Enum.reduce(Enum.map(measured, &elem(&1, 4)), fn {r, rowspan, needed}, heights ->
      span = Enum.slice(heights, r, rowspan)
      deficit = needed - Enum.sum(span)

      if deficit > 0 and span != [],
        do: List.update_at(heights, r + length(span) - 1, &(&1 + deficit)),
        else: heights
    end)
  end

  defp place_row(row_node, cells, r, row_heights, final_y, shift, origin_x, row_width) do
    row_height = Enum.at(row_heights, r, 0.0)

    placed =
      Enum.map(cells, fn {box, _col, _colspan, rowspan} ->
        span_height = row_heights |> Enum.slice(r, rowspan) |> Enum.sum()

        box
        |> shift_box_y(shift)
        |> stretch_cell(span_height)
      end)

    %Box{
      type: :table_row,
      tag: "tr",
      x: origin_x,
      y: final_y,
      width: row_width,
      height: row_height,
      background_color: row_node.computed.background_color,
      computed: row_node.computed,
      children: placed
    }
  end

  # Table cells default to `vertical-align: middle`.
  defp stretch_cell(%Box{} = cell, available) do
    target =
      max(
        0.0,
        available - cell.padding.top - cell.padding.bottom - cell.border_width.top -
          cell.border_width.bottom
      )

    if target > cell.height do
      %Box{
        cell
        | height: target,
          children: Enum.map(cell.children, &shift_box_y(&1, (target - cell.height) / 2.0))
      }
    else
      %Box{cell | height: target}
    end
  end

  defp outer_height(%Box{} = box) do
    box.height + box.padding.top + box.padding.bottom + box.border_width.top +
      box.border_width.bottom
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
