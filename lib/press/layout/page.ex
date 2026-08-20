defmodule Press.Layout.Page do
  @moduledoc """
  A paginated page containing dimensions, margins, and positioned layout boxes.
  """

  @typedoc "A paginated page struct with dimensions and layout boxes."
  @type t :: %__MODULE__{
          number: pos_integer(),
          width: float(),
          height: float(),
          margin: %{top: float(), right: float(), bottom: float(), left: float()},
          boxes: [Press.Layout.Box.t()]
        }

  defstruct [
    :number,
    :width,
    :height,
    margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    boxes: []
  ]
end
