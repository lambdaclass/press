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
  def split(%Box{} = box, limit_y) do
    if splittable?(box) do
      do_split(box, limit_y)
    else
      :indivisible
    end
  end

  defp splittable?(%Box{type: type, children: children}) do
    type in @splittable and children != []
  end

  defp do_split(%Box{} = box, limit_y) do
    header = Enum.filter(box.children, & &1.header_row)
    body = Enum.reject(box.children, & &1.header_row)

    # The head can hold children whose bottom edge stays above the limit. A
    # header is only worth carrying if at least one body row follows it.
    {fitting, remaining} = Enum.split_while(body, &fits?(&1, limit_y))

    # The first child that does not fit may still have a break inside it — a
    # paragraph can give up its first lines even when the whole of it cannot
    # stay. Without this the page stops at the last child boundary and leaves
    # the rest of the sheet empty.
    {fitting, remaining} =
      case remaining do
        [first | rest] ->
          case split(first, limit_y) do
            {:split, head, tail} -> {fitting ++ [head], [tail | rest]}
            :indivisible -> {fitting, remaining}
          end

        [] ->
          {fitting, remaining}
      end

    cond do
      remaining == [] ->
        :indivisible

      fitting == [] ->
        :indivisible

      true ->
        {:split, head_box(box, header, fitting), tail_box(box, header, remaining)}
    end
  end

  defp fits?(%Box{} = child, limit_y) do
    child.y + Box.outer_height(child) <= limit_y
  end

  defp head_box(box, header, fitting) do
    children = header ++ fitting
    bottom = children |> Enum.map(&(&1.y + Box.outer_height(&1))) |> Enum.max()
    content_top = box.y + box.margin.top + box.border_width.top + box.padding.top

    %Box{
      box
      | children: children,
        height: max(0.0, bottom - content_top),
        padding: %{box.padding | bottom: 0.0},
        border_width: %{box.border_width | bottom: 0.0},
        margin: %{box.margin | bottom: 0.0}
    }
  end

  defp tail_box(box, header, remaining) do
    header_height = header |> Enum.map(&Box.outer_height/1) |> Enum.sum()
    first_y = remaining |> Enum.map(& &1.y) |> Enum.min()

    # The tail starts at the box's own origin: the paginator shifts the whole
    # fragment to the top of the next page, so children only need to be packed
    # back against it, with room reserved for the repeated header.
    shift = box.y - first_y + header_height

    moved_body = Enum.map(remaining, &shift_y(&1, shift))

    moved_header =
      reflow_header(header, box.y - (header |> Enum.map(& &1.y) |> Enum.min(fn -> box.y end)))

    children = moved_header ++ moved_body
    bottom = children |> Enum.map(&(&1.y + Box.outer_height(&1))) |> Enum.max()

    %Box{
      box
      | children: children,
        height: max(0.0, bottom - box.y),
        padding: %{box.padding | top: 0.0},
        border_width: %{box.border_width | top: 0.0},
        margin: %{box.margin | top: 0.0}
    }
  end

  defp reflow_header([], _shift), do: []
  defp reflow_header(header, shift), do: Enum.map(header, &shift_y(&1, shift))

  @doc """
  Moves a box and its whole subtree down by `dy`.
  """
  def shift_y(%Box{} = box, dy) when dy == 0.0, do: box

  def shift_y(%Box{} = box, dy) do
    %Box{box | y: box.y + dy, children: Enum.map(box.children, &shift_y(&1, dy))}
  end
end
