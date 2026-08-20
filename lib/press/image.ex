defmodule Press.Image do
  @moduledoc """
  Represents an image decoded and prepared for PDF embedding.
  """

  @type format :: :jpeg | :png
  @type color_space :: :rgb | :gray

  @type t :: %__MODULE__{
          id: String.t() | nil,
          format: format(),
          width: pos_integer(),
          height: pos_integer(),
          color_space: color_space(),
          data: binary(),
          alpha_data: binary() | nil
        }

  defstruct [
    :id,
    :format,
    :width,
    :height,
    :color_space,
    :data,
    :alpha_data
  ]
end
