defmodule Press.Layout.FlexGrid do
  @moduledoc false

  alias Press.Font.Metrics
  alias Press.Layout.Box
  alias Press.Style.{Node, Text}

  @doc """
  True when the node is a CSS grid container declared through `display`.
  """
  def grid?(%Node{computed: %{display: d}}) when d in [:grid, :"inline-grid"], do: true
  def grid?(_), do: false

  @doc """
  True when the node is a flex container declared through `display`.
  """
  def flex?(%Node{computed: %{display: d}}) when d in [:flex, :"inline-flex"], do: true
  def flex?(_), do: false

  @doc """
  Lays out a grid container. Children are placed row-major into the tracks from
  `grid-template-columns`; a row is as tall as its tallest cell.

  Returns `{box, next_y, margin_bottom}`.
  """
  def layout_grid(%Node{} = node, containing_width, container_x, start_y, images) do
    geom = geometry(node, containing_width, container_x, start_y)
    computed = node.computed
    children = visual_children(node.children)

    tracks = computed.grid_template_columns || [{:fr, 1.0}]
    col_gap = computed.column_gap
    row_gap = computed.row_gap

    widths = resolve_tracks(tracks, geom.content_width, col_gap, children)
    offsets = track_offsets(widths, col_gap)
    rows = Enum.chunk_every(children, max(1, length(widths)))

    {row_boxes, content_height} =
      Enum.reduce(rows, {[], 0.0}, fn row, {acc, curr_y} ->
        gap = if acc == [], do: 0.0, else: row_gap

        {cells, row_height} =
          layout_row(
            row,
            widths,
            offsets,
            geom.content_origin_x,
            geom.content_origin_y + curr_y + gap,
            computed.align_items,
            images
          )

        {acc ++ cells, curr_y + gap + row_height}
      end)

    finish(node, geom, row_boxes, content_height)
  end

  @doc """
  Lays out a flex container. Single line, no wrapping: `flex-direction` picks the
  main axis, `flex-grow` shares the leftover main-axis space, `justify-content`
  distributes what is still left and `align-items` sizes and places the cross
  axis.

  Returns `{box, next_y, margin_bottom}`.
  """
  def layout_flex(%Node{} = node, containing_width, container_x, start_y, images) do
    geom = geometry(node, containing_width, container_x, start_y)
    computed = node.computed
    children = visual_children(node.children)

    if column?(computed.flex_direction) do
      layout_flex_column(node, geom, children, images)
    else
      layout_flex_row(node, geom, children, images)
    end
  end

  # ---------------------------------------------------------------------------
  # Flex, row direction
  # ---------------------------------------------------------------------------

  defp layout_flex_row(node, geom, children, images) do
    computed = node.computed
    gap = computed.column_gap
    total_gap = gap * max(0, length(children) - 1)
    inner = max(0.0, geom.content_width - total_gap)

    grows = Enum.map(children, &grow_of/1)
    total_grow = Enum.sum(grows)

    base =
      Enum.map(children, fn child ->
        case explicit_width(child, geom.content_width) do
          nil -> max_content_width(child)
          w -> w
        end
      end)

    widths =
      if total_grow > 0 do
        leftover = max(0.0, inner - sum_where(base, grows, &(&1 == 0.0)))

        Enum.zip(base, grows)
        |> Enum.map(fn
          {_b, g} when g > 0 -> leftover * g / total_grow
          {b, _g} -> b
        end)
      else
        Enum.map(base, &min(&1, inner))
      end

    used = Enum.sum(widths) + total_gap
    free = max(0.0, geom.content_width - used)
    {lead, between} = distribute(computed.justify_content, free, length(children), gap)

    {cells, x_end} =
      Enum.zip(children, widths)
      |> Enum.reduce({[], geom.content_origin_x + lead}, fn {child, w}, {acc, x} ->
        {box, _next_y, _mb} = layout_child(child, w, x, geom.content_origin_y, images)
        {acc ++ [{child, box}], x + w + between}
      end)

    _ = x_end
    row_height = Enum.reduce(cells, 0.0, fn {_n, b}, acc -> max(acc, Box.outer_height(b)) end)

    boxes =
      Enum.map(cells, fn {child, box} ->
        align_cross(child, box, row_height, computed.align_items, geom.content_origin_y)
      end)

    finish(node, geom, boxes, row_height)
  end

  # ---------------------------------------------------------------------------
  # Flex, column direction
  # ---------------------------------------------------------------------------

  defp layout_flex_column(node, geom, children, images) do
    computed = node.computed
    gap = computed.row_gap
    align = computed.align_items

    {cells, content_height} =
      Enum.reduce(children, {[], 0.0}, fn child, {acc, curr_y} ->
        lead = if acc == [], do: 0.0, else: gap

        width =
          if align in [:stretch, :baseline] do
            geom.content_width
          else
            explicit_width(child, geom.content_width) ||
              min(max_content_width(child), geom.content_width)
          end

        x = geom.content_origin_x + cross_offset(align, geom.content_width, width)

        {box, _next_y, _mb} =
          layout_child(child, width, x, geom.content_origin_y + curr_y + lead, images)

        {acc ++ [box], curr_y + lead + Box.outer_height(box)}
      end)

    # A flex column is the one place a container's own height can exceed its
    # content and still move it: justify-content distributes the slack, and the
    # height often comes from min-height or from a grid row stretching the cell.
    target = target_height(node, content_height)
    slack = max(0.0, target - content_height)
    {lead, between} = distribute(computed.justify_content, slack, length(cells), 0.0)

    cells =
      cells
      |> Enum.with_index()
      |> Enum.map(fn {box, i} -> shift_y(box, lead + between * i) end)

    finish(node, geom, cells, max(content_height, target))
  end

  # ---------------------------------------------------------------------------
  # Grid tracks
  # ---------------------------------------------------------------------------

  defp resolve_tracks(tracks, content_width, col_gap, children) do
    n = length(tracks)
    gaps = col_gap * max(0, n - 1)
    budget = max(0.0, content_width - gaps)

    autos = auto_widths(tracks, children, n)

    fixed =
      tracks
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {track, i}, acc ->
        case track do
          {:track, _} -> acc + track_length(track, content_width)
          :auto -> acc + Enum.at(autos, i, 0.0)
          _ -> acc
        end
      end)

    fr_total =
      Enum.reduce(tracks, 0.0, fn
        {:fr, n}, acc -> acc + n
        _, acc -> acc
      end)

    free = max(0.0, budget - fixed)

    tracks
    |> Enum.with_index()
    |> Enum.map(fn {track, i} ->
      case track do
        {:fr, f} when fr_total > 0 -> free * f / fr_total
        {:fr, _} -> 0.0
        {:track, _} -> track_length(track, content_width)
        :auto -> Enum.at(autos, i, 0.0)
      end
    end)
  end

  # An `auto` track is as wide as the widest max-content in its column.
  defp auto_widths(tracks, children, n) do
    rows = Enum.chunk_every(children, max(1, n))

    Enum.with_index(tracks)
    |> Enum.map(fn {track, i} ->
      if track == :auto do
        rows
        |> Enum.map(fn row -> row |> Enum.at(i) |> max_content_width() end)
        |> Enum.max(fn -> 0.0 end)
      else
        0.0
      end
    end)
  end

  defp track_length({:track, {:length, v, :percent}}, content_width),
    do: v / 100.0 * content_width

  defp track_length({:track, {:length, v, :px}}, _cw), do: v * 0.75
  defp track_length({:track, {:length, v, :pt}}, _cw), do: v * 1.0
  defp track_length({:track, {:length, v, :in}}, _cw), do: v * 72.0
  defp track_length({:track, {:length, v, :mm}}, _cw), do: v * 72.0 / 25.4
  defp track_length({:track, {:length, v, :cm}}, _cw), do: v * 72.0 / 2.54
  defp track_length({:track, {:length, v, _}}, _cw), do: v * 1.0
  defp track_length(_, _cw), do: 0.0

  defp track_offsets(widths, col_gap) do
    widths
    |> Enum.scan(0.0, fn w, acc -> acc + w + col_gap end)
    |> then(fn scanned -> [0.0 | scanned] end)
    |> Enum.take(length(widths))
  end

  defp layout_row(row, widths, offsets, origin_x, origin_y, align, images) do
    cells =
      row
      |> Enum.with_index()
      |> Enum.map(fn {child, i} ->
        w = Enum.at(widths, i, 0.0)
        x = origin_x + Enum.at(offsets, i, 0.0)
        {box, _next_y, _mb} = layout_child(child, w, x, origin_y, images)
        {child, box}
      end)

    row_height = Enum.reduce(cells, 0.0, fn {_n, b}, acc -> max(acc, Box.outer_height(b)) end)

    boxes =
      Enum.map(cells, fn {child, box} -> align_cross(child, box, row_height, align, origin_y) end)

    {boxes, row_height}
  end

  # ---------------------------------------------------------------------------
  # Cross-axis sizing and placement
  # ---------------------------------------------------------------------------

  # `stretch` grows the cell to the line's height so its border and background
  # cover the full row, and re-runs the cell's own vertical distribution — a
  # centring flex column only knows where its content goes once it has been
  # told how tall it is.
  defp align_cross(child, box, line_height, align, origin_y) do
    outer = Box.outer_height(box)
    slack = line_height - outer

    cond do
      slack <= 0.0 ->
        box

      align in [:stretch, :baseline] ->
        stretch(child, box, slack)

      align == :center ->
        shift_y(box, slack / 2.0)

      align in [:"flex-end", :end] ->
        shift_y(box, slack)

      true ->
        _ = origin_y
        box
    end
  end

  defp stretch(child, box, slack) do
    grown = %Box{box | height: box.height + slack}

    if centering_column?(child) do
      %Box{grown | children: Enum.map(grown.children, &shift_y(&1, slack / 2.0))}
    else
      grown
    end
  end

  defp centering_column?(%Node{computed: computed}) do
    flex_display?(computed.display) and column?(computed.flex_direction) and
      computed.justify_content in [:center, :"space-around", :"space-evenly"]
  end

  defp centering_column?(_), do: false

  defp flex_display?(d), do: d in [:flex, :"inline-flex"]

  defp column?(d), do: d in [:column, :"column-reverse"]

  defp cross_offset(align, available, used) do
    case align do
      :center -> max(0.0, (available - used) / 2.0)
      a when a in [:"flex-end", :end] -> max(0.0, available - used)
      _ -> 0.0
    end
  end

  defp distribute(_justify, free, count, base_gap) when free <= 0.0 or count <= 0,
    do: {0.0, base_gap}

  defp distribute(justify, free, count, base_gap) do
    case justify do
      :center -> {free / 2.0, base_gap}
      j when j in [:"flex-end", :end] -> {free, base_gap}
      :"space-between" when count > 1 -> {0.0, base_gap + free / (count - 1)}
      :"space-around" -> {free / (count * 2), base_gap + free / count}
      :"space-evenly" -> {free / (count + 1), base_gap + free / (count + 1)}
      _ -> {0.0, base_gap}
    end
  end

  # ---------------------------------------------------------------------------
  # Intrinsic widths
  # ---------------------------------------------------------------------------

  @doc """
  Widest the node can get without wrapping, in points.
  """
  def max_content_width(nil), do: 0.0

  def max_content_width(%Text{content: content, computed: computed}) do
    font = Metrics.font_for(computed.font_family, computed.font_weight, computed.font_style)
    Metrics.text_width(
      font,
      String.trim(content),
      computed.font_size,
      Map.get(computed, :letter_spacing, 0.0)
    )
  end

  def max_content_width(%Node{} = node) do
    computed = node.computed
    own = explicit_width(node, 0.0)

    inner =
      if own do
        own
      else
        node.children
        |> visual_children()
        |> Enum.map(&max_content_width/1)
        |> Enum.max(fn -> 0.0 end)
      end

    inner + side(computed.padding, :left) + side(computed.padding, :right) +
      side(computed.border_width, :left) + side(computed.border_width, :right) +
      side(computed.margin, :left) + side(computed.margin, :right)
  end

  defp side(box, key) do
    case box && Map.get(box, key) do
      n when is_number(n) -> n * 1.0
      {:length, v, :px} -> v * 0.75
      {:length, v, :pt} -> v * 1.0
      _ -> 0.0
    end
  end

  defp explicit_width(%Node{computed: %{width: {:percent, p}}}, containing) when containing > 0,
    do: p / 100.0 * containing

  defp explicit_width(%Node{computed: %{width: w}}, _containing) when is_number(w), do: w * 1.0
  defp explicit_width(_node, _containing), do: nil

  defp grow_of(%Node{computed: %{flex_grow: g}}) when is_number(g), do: g * 1.0
  defp grow_of(_), do: 0.0

  defp sum_where(values, keys, pred) do
    Enum.zip(values, keys)
    |> Enum.filter(fn {_v, k} -> pred.(k) end)
    |> Enum.reduce(0.0, fn {v, _k}, acc -> acc + v end)
  end

  # ---------------------------------------------------------------------------
  # Shared box plumbing
  # ---------------------------------------------------------------------------

  defp geometry(%Node{computed: computed}, containing_width, container_x, start_y) do
    margin = resolve_sides(computed.margin, containing_width)
    padding = resolve_sides(computed.padding, containing_width)
    border = resolve_sides(computed.border_width, containing_width)

    {outer, declared?} =
      case computed.width do
        {:percent, p} -> {p / 100.0 * containing_width, true}
        n when is_number(n) -> {n * 1.0, true}
        _ -> {max(0.0, containing_width - margin.left - margin.right), false}
      end

    # A declared width under `border-box` already includes padding and border;
    # otherwise they sit outside it, and an auto width is the space left in the
    # container.
    content_width =
      if declared? and Map.get(computed, :box_sizing) != :"border-box" do
        outer
      else
        max(0.0, outer - padding.left - padding.right - border.left - border.right)
      end

    box_x = container_x + margin.left
    box_y = start_y + margin.top

    %{
      margin: margin,
      padding: padding,
      border: border,
      content_width: content_width,
      box_x: box_x,
      box_y: box_y,
      content_origin_x: box_x + border.left + padding.left,
      content_origin_y: box_y + border.top + padding.top
    }
  end

  defp finish(%Node{} = node, geom, children, content_height) do
    computed = node.computed
    height = clamp_height(computed, content_height)

    total_outer =
      height + geom.padding.top + geom.padding.bottom + geom.border.top + geom.border.bottom

    box = %Box{
      type: :block,
      tag: node.element.tag,
      x: geom.box_x,
      y: geom.box_y,
      width: geom.content_width,
      height: height,
      margin: geom.margin,
      padding: geom.padding,
      border_width: geom.border,
      border_color: computed.border_color,
      border_style: computed.border_style,
      background_color: computed.background_color,
      computed: computed,
      children: children
    }

    {box, geom.box_y + total_outer, geom.margin.bottom}
  end

  defp target_height(%Node{computed: computed}, content_height) do
    clamp_height(computed, content_height)
  end

  defp clamp_height(computed, content_height) do
    base =
      case computed.height do
        n when is_number(n) -> n * 1.0
        _ -> content_height
      end

    base
    |> then(fn h ->
      case Map.get(computed, :min_height) do
        n when is_number(n) -> max(h, n * 1.0)
        _ -> h
      end
    end)
    |> then(fn h ->
      case Map.get(computed, :max_height) do
        n when is_number(n) -> min(h, n * 1.0)
        _ -> h
      end
    end)
  end

  defp layout_child(%Text{} = text, width, x, y, _images) do
    lines = Press.Layout.Inline.wrap([text], width, :left)

    {placed, height} =
      Enum.reduce(lines, {[], 0.0}, fn line, {acc, curr} ->
        box = %Box{
          line
          | x: x,
            y: y + curr,
            children: Enum.map(line.children, fn c -> %Box{c | x: x + c.x, y: y + curr + c.y} end)
        }

        {acc ++ [box], curr + line.height}
      end)

    {%Box{type: :block, x: x, y: y, width: width, height: height, children: placed}, y + height,
     0.0}
  end

  defp layout_child(%Node{} = node, width, x, y, images) do
    Press.Layout.Block.layout_block(node, width, x, y, images)
  end

  defp visual_children(children) do
    Enum.reject(children, fn
      %Node{} = n -> Press.Layout.Visibility.hidden?(n)
      %Text{content: c} -> String.trim(c) == ""
      _ -> true
    end)
  end

  defp shift_y(%Box{} = box, 0.0), do: box

  defp shift_y(%Box{} = box, dy) do
    %Box{box | y: box.y + dy, children: Enum.map(box.children, &shift_y(&1, dy))}
  end

  defp resolve_sides(nil, _containing),
    do: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0}

  defp resolve_sides(box, containing) do
    Map.new([:top, :right, :bottom, :left], fn key ->
      {key, resolve_side_value(Map.get(box, key), containing)}
    end)
  end

  defp resolve_side_value({:percent, p}, containing), do: p / 100.0 * containing
  defp resolve_side_value(n, _containing) when is_number(n), do: n * 1.0
  defp resolve_side_value(_, _containing), do: 0.0
end
