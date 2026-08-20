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
      |> Enum.count()
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp is_cell_node(%Node{element: %{tag: tag}}), do: tag in ["th", "td"]
  defp is_cell_node(_), do: false

  defp calculate_column_widths(_row_nodes, 0, table_width), do: [table_width]

  defp calculate_column_widths(row_nodes, col_count, table_width) do
    explicit_widths =
      for c <- 0..(col_count - 1) do
        row_nodes
        |> Enum.find_value(nil, fn %Node{children: children} ->
          cells = Enum.filter(children, &is_cell_node/1)

          case Enum.at(cells, c) do
            %Node{computed: %{width: {:percent, p}}} ->
              p / 100.0 * table_width

            %Node{computed: %{width: n}} when is_number(n) ->
              n * 1.0

            _ ->
              nil
          end
        end)
      end

    total_explicit = explicit_widths |> Enum.reject(&is_nil/1) |> Enum.sum()
    unspecified_count = Enum.count(explicit_widths, &is_nil/1)

    default_col_width =
      if unspecified_count > 0 do
        max(0.0, table_width - total_explicit) / unspecified_count
      else
        0.0
      end

    Enum.map(explicit_widths, fn
      nil -> default_col_width
      w -> w
    end)
  end

  defp layout_row(%Node{} = row_node, column_widths, origin_x, row_y) do
    cells = Enum.filter(row_node.children, &is_cell_node/1)

    {cell_boxes, _final_x} =
      cells
      |> Enum.with_index()
      |> Enum.reduce({[], origin_x}, fn {cell_node, c_idx}, {c_acc, curr_x} ->
        col_width = Enum.at(column_widths, c_idx, 0.0)

        {cell_box, _next_y, _m} = Block.layout_block(cell_node, col_width, curr_x, row_y)

        cell_box = %Box{cell_box | type: :table_cell, width: col_width, x: curr_x, y: row_y}

        {[cell_box | c_acc], curr_x + col_width}
      end)

    cell_boxes = Enum.reverse(cell_boxes)
    row_height = Enum.map(cell_boxes, & &1.height) |> Enum.max(fn -> 0.0 end)

    stretched_cells =
      Enum.map(cell_boxes, fn cell ->
        %Box{cell | height: row_height}
      end)

    row_width = Enum.sum(column_widths)

    row_box = %Box{
      type: :table_row,
      tag: "tr",
      x: origin_x,
      y: row_y,
      width: row_width,
      height: row_height,
      children: stretched_cells
    }

    {row_box, row_height}
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
