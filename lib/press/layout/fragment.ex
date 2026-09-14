defmodule Press.Layout.Fragment do
  @moduledoc false

  alias Press.Layout.Box

  @splittable [:block, :table, :table_row_group]

  @doc """
  Splits a box so that everything before `limit_y` stays on the current page and
  the rest continues on the next one.

  Returns `{:split, head, tail}`, or `:indivisible` when the box has no break
  opportunity above `limit_y` — a single line of text, an image, or a first
  child that is itself too tall to fit.

  The head keeps the box's top margin, border and padding and drops the bottom
  ones; the tail does the reverse, so a bordered container reads as one box
  interrupted by the page edge rather than two stacked boxes. A table repeats
  its `<thead>` rows at the top of the tail.
  """
  def split(%Box{} = box, limit_y, honour_avoid? \\ true) do
    if splittable?(box) and not (honour_avoid? and keep_whole?(box)) do
      do_split(box, limit_y)
    else
      :indivisible
    end
  end

  @doc """
  Whether the box asked not to be broken across pages.
  """
  def keep_whole?(%Box{computed: computed}) when is_map(computed) do
    Map.get(computed, :page_break_inside) == :avoid
  end

  def keep_whole?(_box), do: false

  defp splittable?(%Box{type: type, children: children}) do
    type in @splittable and children != []
  end

  defp do_split(%Box{} = box, limit_y) do
    header = Enum.filter(box.children, & &1.header_row)
    footer = Enum.filter(box.children, & &1.footer_row)
    body = Enum.reject(box.children, &(&1.header_row or &1.footer_row))

    # A repeated `<tfoot>` has to be on the page before the break too, so the
    # body only gets what is left above it.
    body_limit = limit_y - outer_heights(footer)

    {fitting, remaining} = Enum.split_while(body, &fits?(&1, body_limit))

    # The first child that does not fit may still have a break inside it — a
    # paragraph can give up its first lines even when the whole of it cannot
    # stay. Without this the page stops at the last child boundary and leaves
    # the rest of the sheet empty.
    {fitting, remaining} =
      case remaining do
        [first | rest] ->
          case split(first, body_limit) do
            {:split, head, tail} -> {fitting ++ [head], [tail | rest]}
            :indivisible -> {fitting, remaining}
          end

        [] ->
          {fitting, remaining}
      end

    if remaining == [] or fitting == [] do
      :indivisible
    else
      {:split, head_box(box, header, fitting, footer), tail_box(box, header, remaining, footer)}
    end
  end

  defp outer_heights(boxes), do: boxes |> Enum.map(&Box.outer_height/1) |> Enum.sum()

  defp move_to(boxes, top) do
    case boxes do
      [] -> []
      rows -> Enum.map(rows, &shift_y(&1, top - Enum.min(Enum.map(rows, fn r -> r.y end))))
    end
  end

  defp fits?(%Box{} = child, limit_y) do
    child.y + Box.outer_height(child) <= limit_y
  end

  defp head_box(box, header, fitting, footer) do
    body_bottom = fitting |> Enum.map(&(&1.y + Box.outer_height(&1))) |> Enum.max()
    children = header ++ fitting ++ move_to(footer, body_bottom)
    bottom = children |> Enum.map(&(&1.y + Box.outer_height(&1))) |> Enum.max()
    content_top = box.y + box.border_width.top + box.padding.top

    %Box{
      box
      | children: children,
        height: max(0.0, bottom - content_top),
        padding: %{box.padding | bottom: 0.0},
        border_width: %{box.border_width | bottom: 0.0},
        margin: %{box.margin | bottom: 0.0}
    }
  end

  # The tail keeps the y its children already had, so the siblings that follow
  # it on the page stay the same distance away as the layout gave them. Only the
  # repeated header moves, into the space just above the first surviving child.
  defp tail_box(box, header, remaining, footer) do
    top = Enum.min(Enum.map(remaining, & &1.y)) - outer_heights(header)
    children = move_to(header, top) ++ remaining ++ footer
    bottom = children |> Enum.map(&(&1.y + Box.outer_height(&1))) |> Enum.max()

    %Box{
      box
      | y: top,
        children: children,
        height: max(0.0, bottom - top),
        padding: %{box.padding | top: 0.0},
        border_width: %{box.border_width | top: 0.0},
        margin: %{box.margin | top: 0.0}
    }
  end

  @doc """
  Moves a box and its whole subtree down by `dy`.
  """
  def shift_y(%Box{} = box, dy) when dy == 0.0, do: box

  def shift_y(%Box{} = box, dy) do
    %Box{box | y: box.y + dy, children: Enum.map(box.children, &shift_y(&1, dy))}
  end
end
