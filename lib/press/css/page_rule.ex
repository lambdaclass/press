defmodule Press.CSS.PageRule do
  @moduledoc """
  A parsed `@page { ... }` rule, as produced by `Press.CSS.Parser.parse/1`.

  Unlike `Press.CSS.Rule`, there is no selector or specificity — `@page`
  rules apply globally and the last one (in source/origin order) to set
  a given property wins outright. `declarations["margin"]`, if present,
  is already expanded into a `%{top:, right:, bottom:, left:}` map (not
  split into separate keys the way `Press.CSS.Rule` splits `margin`) —
  see the design spec's "@page parsing" section for why.
  """

  @type t :: %__MODULE__{declarations: %{String.t() => term()}, source_index: non_neg_integer()}

  defstruct declarations: %{}, source_index: 0
end
