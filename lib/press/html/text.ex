defmodule Press.HTML.Text do
  @moduledoc """
  A text node in the DOM produced by `Press.HTML.Parser`.

  `content` has HTML entities already decoded (see `Press.HTML.Parser`
  moduledoc for the supported entity set).
  """

  @type t :: %__MODULE__{content: String.t()}

  defstruct content: ""
end
