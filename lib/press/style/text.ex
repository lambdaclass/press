defmodule Press.Style.Text do
  @moduledoc """
  A styled text node, as produced by `Press.Style.Cascade.build/3`.

  Text has no properties or selectors of its own, but still carries a
  `computed` map — a copy of whatever it inherited from its parent
  element — since properties like `color`/`font-size` must reach text
  for Layout to render it correctly.
  """

  @type t :: %__MODULE__{content: String.t(), computed: map()}

  defstruct content: "", computed: %{}
end
