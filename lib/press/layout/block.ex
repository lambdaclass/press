defmodule Press.Layout.Block do
  @moduledoc false

  alias Press.Layout.{Box, Inline}
  alias Press.Style.{Node, Text}

  @doc """
  Lays out a block element or container.
  Returns `{box, next_y, margin_bottom}`.
  """
  def layout_block(%Node{} = node, containing_width, container_x, start_y, images \\ %{}) do
    cond do
      Press.Layout.Visibility.hidden?(node) ->
        {%Box{type: :block, width: 0.0, height: 0.0}, start_y, 0.0}

      node.element.tag == "table" ->
        Press.Layout.Table.layout_table(node, containing_width, container_x, start_y)

      Press.Layout.FlexGrid.grid?(node) ->
        Press.Layout.FlexGrid.layout_grid(node, containing_width, container_x, start_y, images)

      Press.Layout.FlexGrid.flex?(node) ->
        Press.Layout.FlexGrid.layout_flex(node, containing_width, container_x, start_y, images)

      Press.Layout.Grid.grid?(node) ->
        Press.Layout.Grid.layout_grid(node, containing_width, container_x, start_y, images)

      true ->
        do_layout_block(node, containing_width, container_x, start_y, images)
    end
  end

  defp do_layout_block(%Node{} = node, containing_width, container_x, start_y, images) do
    computed = node.computed

    # 1. Resolve box dimensions (percentages against containing_width)
    margin = resolve_box_dimensions(computed.margin, containing_width)
    padding = resolve_box_dimensions(computed.padding, containing_width)
    border_width = resolve_box_dimensions(computed.border_width, containing_width)

    content_width =
      case computed.width do
        {:percent, p} ->
          deduct_box(p / 100.0 * containing_width, computed, padding, border_width)

        n when is_number(n) ->
          deduct_box(n * 1.0, computed, padding, border_width)

        :auto ->
          max(
            0.0,
            containing_width - margin.left - margin.right - padding.left - padding.right -
              border_width.left - border_width.right
          )
      end

    box_x = container_x + margin.left
    box_y = start_y + margin.top

    content_origin_x = box_x + border_width.left + padding.left
    content_origin_y = box_y + border_width.top + padding.top

    # 2. Layout children
    {children_boxes, content_height} =
      layout_children(
        node.children,
        content_width,
        content_origin_x,
        content_origin_y,
        computed.text_align,
        images
      )

    box_height =
      case computed.height do
        {:percent, p} ->
          p / 100.0 * content_height

        n when is_number(n) ->
          n * 1.0

        :auto ->
          content_height
      end

    total_outer_height =
      box_height + padding.top + padding.bottom + border_width.top + border_width.bottom

    children_boxes =
      if Map.get(computed, :vertical_align, :baseline) == :middle and box_height > content_height do
        y_offset = (box_height - content_height) / 2.0
        Enum.map(children_boxes, &shift_box_y(&1, y_offset))
      else
        children_boxes
      end

    box = %Box{
      type: :block,
      tag: node.element.tag,
      x: box_x,
      y: box_y,
      width: content_width,
      height: box_height,
      margin: margin,
      padding: padding,
      border_width: border_width,
      border_color: computed.border_color,
      border_style: computed.border_style,
      background_color: computed.background_color,
      computed: computed,
      children: children_boxes
    }

    next_y = box_y + total_outer_height
    {box, next_y, margin.bottom}
  end

  # Under `box-sizing: border-box` the declared width already covers padding
  # and border, so the content box is what is left of it.
  defp deduct_box(width, computed, padding, border) do
    case Map.get(computed, :box_sizing) do
      :"border-box" ->
        max(0.0, width - padding.left - padding.right - border.left - border.right)

      _ ->
        width
    end
  end

  def layout_children(children, content_width, origin_x, origin_y, text_align, images \\ %{})

  def layout_children([], _content_width, _origin_x, _origin_y, _text_align, _images) do
    {[], 0.0}
  end

  def layout_children(children, content_width, origin_x, origin_y, text_align, images) do
    if all_inline?(children) do
      line_boxes = Inline.wrap(children, content_width, text_align)

      {positioned_lines, total_height} =
        Enum.reduce(line_boxes, {[], 0.0}, fn line, {acc, curr_y} ->
          placed_line = %Box{
            line
            | x: origin_x,
              y: origin_y + curr_y,
              children:
                Enum.map(line.children, fn child ->
                  %Box{child | x: origin_x + child.x, y: origin_y + curr_y + child.y}
                end)
          }

          {[placed_line | acc], curr_y + line.height}
        end)

      {Enum.reverse(positioned_lines), total_height}
    else
      clean_children =
        Enum.reject(children, fn
          %Node{} = child_node ->
            Press.Layout.Visibility.hidden?(child_node)

          %Text{content: c} ->
            String.trim(c) == ""

          _ ->
            false
        end)

      {boxes, total_h, _last_margin} =
        Enum.reduce(clean_children, {[], 0.0, 0.0}, fn child, {acc, curr_y, prev_margin_bottom} ->
          case child do
            %Node{element: %{tag: "img"}} = img_node ->
              curr_top_margin = get_top_margin(img_node.computed.margin, content_width)
              margin_gap = max(prev_margin_bottom, curr_top_margin)
              child_start_y = origin_y + curr_y + margin_gap - curr_top_margin

              {child_box, next_y_abs, child_margin_bottom} =
                Press.Layout.Image.layout_image(
                  img_node,
                  images,
                  content_width,
                  origin_x,
                  child_start_y
                )

              child_consumed_height = next_y_abs - origin_y
              {[child_box | acc], child_consumed_height, child_margin_bottom}

            %Node{} = node ->
              curr_top_margin = get_top_margin(node.computed.margin, content_width)
              margin_gap = max(prev_margin_bottom, curr_top_margin)

              child_start_y = origin_y + curr_y + margin_gap - curr_top_margin

              {child_box, next_y_abs, child_margin_bottom} =
                layout_block(node, content_width, origin_x, child_start_y, images)

              child_consumed_height = next_y_abs - origin_y

              {[child_box | acc], child_consumed_height, child_margin_bottom}

            %Text{} = text ->
              line_boxes = Inline.wrap([text], content_width, text_align)

              {placed_lines, lines_h} =
                Enum.reduce(line_boxes, {[], 0.0}, fn line, {l_acc, l_y} ->
                  placed_line = %Box{
                    line
                    | x: origin_x,
                      y: origin_y + curr_y + l_y,
                      children:
                        Enum.map(line.children, fn c ->
                          %Box{c | x: origin_x + c.x, y: origin_y + curr_y + l_y + c.y}
                        end)
                  }

                  {[placed_line | l_acc], l_y + line.height}
                end)

              {Enum.reverse(placed_lines) ++ acc, curr_y + lines_h, 0.0}
          end
        end)

      {Enum.reverse(boxes), total_h}
    end
  end

  defp all_inline?(children) do
    Enum.all?(children, fn
      %Text{} ->
        true

      %Node{element: %{tag: tag}}
      when tag in ["span", "strong", "b", "em", "i", "a", "small"] ->
        true

      _ ->
        false
    end)
  end

  defp get_top_margin(%{top: {:percent, p}}, containing_width),
    do: p / 100.0 * containing_width

  defp get_top_margin(%{top: n}, _containing_width) when is_number(n), do: n * 1.0
  defp get_top_margin(_, _), do: 0.0

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

  defp shift_box_y(%Box{children: children} = box, y_offset) do
    %Box{
      box
      | y: box.y + y_offset,
        children: Enum.map(children, &shift_box_y(&1, y_offset))
    }
  end
end
