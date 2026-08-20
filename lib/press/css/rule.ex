defmodule Press.CSS.Rule do
  @moduledoc """
  A parsed CSS style rule (`selector { declarations }`), as produced by
  `Press.CSS.Parser.parse/1`.

  `selector` is a list of compound-selector maps in left-to-right
  (outermost-to-innermost) order — see the internal selector parser for the
  shape and matching logic. `declarations` maps CSS property name to an
  already-parsed, typed value — box shorthands (`margin`, `padding`,
  `border-*`) are already expanded into longhand keys here, never left
  as a combined shorthand key. `source_index` is this rule's position
  among the other rules produced by the same `parse/1` call; used by
  `Press.Style.Cascade` to break ties between rules of equal
  specificity from the same stylesheet source.
  """

  @typedoc "A parsed CSS style rule struct."
  @type t :: %__MODULE__{
          selector: [map()],
          specificity: {non_neg_integer(), non_neg_integer(), non_neg_integer()},
          declarations: %{String.t() => term()},
          source_index: non_neg_integer()
        }

  defstruct selector: [], specificity: {0, 0, 0}, declarations: %{}, source_index: 0
end
