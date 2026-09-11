defmodule Press.Layout.Whitespace do
  @moduledoc false

  @collapsible [?\s, ?\t, ?\n, ?\r, ?\f, ?\v]

  @doc """
  Whether a run of text collapses away entirely.

  Only the characters CSS treats as collapsible count. `&nbsp;` (U+00A0) is
  whitespace to Unicode but a printing character to CSS: a cell holding nothing
  else still gets a line box, and `String.trim/1` would throw that away.
  """
  def blank?(text) when is_binary(text) do
    text |> String.to_charlist() |> Enum.all?(&(&1 in @collapsible))
  end
end
