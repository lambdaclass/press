defmodule Press.Layout.Margins do
  @moduledoc false

  alias Press.Style.{Node, Text}

  @doc """
  The top margin a block contributes to the flow, with its first child's top
  margin collapsed in.

  When nothing separates a block's top edge from its first child — no border,
  no padding — CSS collapses the two margins into one and places it outside the
  parent. Without this, a wrapper like `<section><h2 …>` adds the heading's
  margin *inside* the section, on top of whatever gap the section already had.
  """
  def collapsed_top(node, containing_width) do
    own = side(node, :margin, :top, containing_width)

    if collapsible_top?(node) do
      case first_flow_child(node) do
        nil -> own
        child -> max(own, collapsed_top(child, containing_width))
      end
    else
      own
    end
  end

  @doc """
  True when a block's top margin collapses with its first child's — i.e. when
  it has no top border or padding of its own to keep them apart.
  """
  def collapsible_top?(%Node{} = node) do
    side(node, :border_width, :top, 0.0) == 0.0 and side(node, :padding, :top, 0.0) == 0.0
  end

  def collapsible_top?(_), do: false

  @doc """
  The first child that takes part in the parent's margin collapsing. Text
  content stops the collapse: a block whose first child is a line of text has
  nothing to collapse with.
  """
  def first_flow_child(%Node{children: children}) do
    Enum.find_value(children, fn
      %Text{content: c} -> if String.trim(c) == "", do: nil, else: :text
      %Node{} = child -> if Press.Layout.Visibility.hidden?(child), do: nil, else: child
      _ -> nil
    end)
    |> case do
      :text -> nil
      other -> other
    end
  end

  def first_flow_child(_), do: nil

  defp side(%Node{computed: computed}, box_key, side_key, containing_width) do
    computed
    |> Map.get(box_key)
    |> case do
      nil -> 0.0
      box -> resolve(Map.get(box, side_key), containing_width)
    end
  end

  defp side(_node, _box_key, _side_key, _containing_width), do: 0.0

  defp resolve({:percent, p}, containing_width) when is_number(containing_width),
    do: p / 100.0 * containing_width

  defp resolve(n, _containing_width) when is_number(n), do: n * 1.0
  defp resolve(_, _containing_width), do: 0.0
end
