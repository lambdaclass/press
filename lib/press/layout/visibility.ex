defmodule Press.Layout.Visibility do
  @moduledoc false

  alias Press.Style.Node

  @non_visual_tags ~w(head style link meta script title iframe)

  def non_visual_tags, do: @non_visual_tags

  @doc """
  True when the node must not produce any box: a non-rendering tag, or
  `display: none`, which also removes its whole subtree.
  """
  def hidden?(%Node{element: %{tag: tag}}) when tag in @non_visual_tags, do: true
  def hidden?(%Node{computed: %{display: :none}}), do: true
  def hidden?(_), do: false
end
