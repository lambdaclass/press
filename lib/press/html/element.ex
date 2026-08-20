defmodule Press.HTML.Element do
  @moduledoc """
  An HTML element node in the DOM produced by `Press.HTML.Parser`.

  `tag` and attribute names are always lowercase (see
  `Press.HTML.Parser` moduledoc). `attrs` maps attribute name to its
  (already entity-decoded) string value. `children` holds this
  element's child nodes in document order — a mix of `Press.HTML.Element`
  and `Press.HTML.Text`.
  """

  @typedoc "An HTML element node struct."
  @type t :: %__MODULE__{
          tag: String.t(),
          attrs: %{String.t() => String.t()},
          children: [t() | Press.HTML.Text.t()]
        }

  defstruct tag: nil, attrs: %{}, children: []
end
