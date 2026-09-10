defmodule Press.Layout do
  @moduledoc """
  Transforms a styled tree into a positioned geometric box tree.
  """

  alias Press.Layout.{Block, Box, Table}
  alias Press.Style.{Node, Text}

  @non_visual_tags ~w(head style link meta script title iframe)

  @doc """
  Lays out a styled tree according to page dimensions and margins.
  """
  @spec build([Node.t() | Text.t()], map(), map()) :: Box.t()
  def build(styled_tree, page_config, images \\ %{}) do
    {page_width, _page_height} = page_config.size
    margin = page_config.margin

    page_box_width = max(0.0, page_width - margin.left - margin.right)

    # `<html>` and `<body>` are flattened away rather than laid out, so their
    # own box has to be folded into the page's content area — a document with
    # `body { padding: 20px }` expects everything inside it to be that much
    # narrower, and every column width is measured against it.
    inset = wrapper_inset(styled_tree, page_box_width)

    content_width = max(0.0, page_box_width - inset.left - inset.right)
    origin_x = margin.left + inset.left
    origin_y = margin.top + inset.top

    visual_nodes = filter_visual_nodes(styled_tree)

    {top_boxes, total_height, _last_margin} =
      Enum.reduce(visual_nodes, {[], 0.0, 0.0}, fn child, {acc, curr_y, prev_margin_bottom} ->
        case child do
          %Node{element: %{tag: "table"}} = table_node ->
            collapsed_top = Press.Layout.Margins.collapsed_top(table_node, content_width)
              own_top_margin = get_top_margin(table_node.computed.margin, content_width)
            margin_gap = max(prev_margin_bottom, collapsed_top)
            child_start_y = origin_y + curr_y + margin_gap - own_top_margin

            {table_box, next_y_abs, child_margin_bottom} =
              Table.layout_table(table_node, content_width, origin_x, child_start_y)

            consumed_height = next_y_abs - origin_y
            {[table_box | acc], consumed_height, child_margin_bottom}

          %Node{element: %{tag: "img"}} = img_node ->
            collapsed_top = Press.Layout.Margins.collapsed_top(img_node, content_width)
              own_top_margin = get_top_margin(img_node.computed.margin, content_width)
            margin_gap = max(prev_margin_bottom, collapsed_top)
            child_start_y = origin_y + curr_y + margin_gap - own_top_margin

            {img_box, next_y_abs, child_margin_bottom} =
              Press.Layout.Image.layout_image(
                img_node,
                images,
                content_width,
                origin_x,
                child_start_y
              )

            consumed_height = next_y_abs - origin_y
            {[img_box | acc], consumed_height, child_margin_bottom}

          %Node{} = node ->
            collapsed_top = Press.Layout.Margins.collapsed_top(node, content_width)
              own_top_margin = get_top_margin(node.computed.margin, content_width)
            margin_gap = max(prev_margin_bottom, collapsed_top)
            child_start_y = origin_y + curr_y + margin_gap - own_top_margin

            {block_box, next_y_abs, child_margin_bottom} =
              Block.layout_block(node, content_width, origin_x, child_start_y, images)

            consumed_height = next_y_abs - origin_y
            {[block_box | acc], consumed_height, child_margin_bottom}

          %Text{} = text ->
            line_boxes = Press.Layout.Inline.wrap([text], content_width, :left)

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

    %Box{
      type: :root,
      x: origin_x,
      y: origin_y,
      width: content_width,
      height: total_height,
      # The wrapper's bottom edge is not a box the paginator walks, so it
      # travels here: every page has to stop that much short of its margin.
      padding: %{top: 0.0, right: 0.0, bottom: inset.bottom, left: 0.0},
      children: Enum.reverse(top_boxes)
    }
  end

  @wrapper_tags ["html", "body"]

  defp wrapper_inset(nodes, containing_width) do
    Enum.reduce(nodes, %{left: 0.0, right: 0.0, top: 0.0, bottom: 0.0}, fn node, acc ->
      case node do
        %Node{element: %{tag: tag}, children: children} when tag in @wrapper_tags ->
          own = box_inset(node, containing_width)
          inner = wrapper_inset(children, max(0.0, containing_width - own.left - own.right))

          %{
            left: acc.left + own.left + inner.left,
            right: acc.right + own.right + inner.right,
            top: acc.top + own.top + inner.top,
            bottom: acc.bottom + own.bottom + inner.bottom
          }

        _ ->
          acc
      end
    end)
  end

  defp box_inset(%Node{computed: computed}, containing_width) do
    side = fn key, edge ->
      computed
      |> Map.get(key)
      |> case do
        nil -> 0.0
        box -> resolve_side(Map.get(box, edge), containing_width)
      end
    end

    %{
      left: side.(:margin, :left) + side.(:border_width, :left) + side.(:padding, :left),
      right: side.(:margin, :right) + side.(:border_width, :right) + side.(:padding, :right),
      top: side.(:margin, :top) + side.(:border_width, :top) + side.(:padding, :top),
      bottom: side.(:margin, :bottom) + side.(:border_width, :bottom) + side.(:padding, :bottom)
    }
  end

  defp resolve_side({:percent, p}, containing_width), do: p / 100.0 * containing_width
  defp resolve_side(n, _containing_width) when is_number(n), do: n * 1.0
  defp resolve_side(_, _containing_width), do: 0.0

  defp filter_visual_nodes(nodes) do
    filtered = Enum.flat_map(nodes, &filter_node/1)
    clean_whitespace_nodes(filtered)
  end

  defp filter_node(%Node{} = node) when node.element.tag in @non_visual_tags, do: []

  defp filter_node(%Node{computed: %{display: :none}}), do: []

  defp filter_node(%Node{element: %{tag: tag}, children: children})
       when tag in ["html", "body"] do
    filter_visual_nodes(children)
  end

  defp filter_node(%Node{children: children} = node) do
    [%Node{node | children: filter_visual_nodes(children)}]
  end

  defp filter_node(%Text{} = text), do: [text]

  defp clean_whitespace_nodes(nodes) do
    has_blocks = Enum.any?(nodes, &is_block_node/1)

    if has_blocks do
      Enum.reject(nodes, fn
        %Text{content: c} -> String.trim(c) == ""
        _ -> false
      end)
    else
      nodes
    end
  end

  defp is_block_node(%Node{element: %{tag: tag}})
       when tag in [
              "div",
              "p",
              "h1",
              "h2",
              "h3",
              "h4",
              "h5",
              "h6",
              "table",
              "thead",
              "tbody",
              "tfoot",
              "tr",
              "ul",
              "ol",
              "li",
              "header",
              "footer",
              "main",
              "section",
              "article",
              "blockquote",
              "form"
            ],
       do: true

  defp is_block_node(_), do: false

  defp get_top_margin(%{top: {:percent, p}}, containing_width),
    do: p / 100.0 * containing_width

  defp get_top_margin(%{top: n}, _containing_width) when is_number(n), do: n * 1.0
  defp get_top_margin(_, _), do: 0.0
end
