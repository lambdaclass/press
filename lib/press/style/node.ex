defmodule Press.Style.Node do
  @moduledoc """
  A styled element node, as produced by `Press.Style.Cascade.build/3`.

  `computed` maps property name (as an atom, e.g. `:font_size`,
  `:margin`) to its resolved value: colors are `{r, g, b}` floats in
  `0.0..1.0`; lengths are a point float, except `%`-valued lengths,
  which stay `{:percent, n}` since resolving them needs the containing
  block's width — a layout-time concept `Press.Style.Cascade` doesn't
  have. See the design spec for the full computed-property list.
  """

  @typedoc "A styled DOM element node struct with computed CSS properties."
  @type t :: %__MODULE__{
          element: Press.HTML.Element.t(),
          computed: map(),
          children: [t() | Press.Style.Text.t()]
        }

  defstruct element: nil, computed: %{}, children: []
end
