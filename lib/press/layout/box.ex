defmodule Press.Layout.Box do
  @moduledoc """
  A positioned geometric box in the layout tree.
  """

  @typedoc "The structural category of a layout box."
  @type box_type :: :block | :line | :text | :table | :table_row | :table_cell | :image

  @typedoc "A positioned geometric box struct."
  @type t :: %__MODULE__{
          type: box_type(),
          tag: String.t() | nil,
          x: float() | nil,
          y: float() | nil,
          width: float() | nil,
          height: float() | nil,
          text: String.t() | nil,
          font: atom() | nil,
          font_size: float() | nil,
          color: term(),
          image: Press.Image.t() | nil,
          margin: %{top: float(), right: float(), bottom: float(), left: float()},
          padding: %{top: float(), right: float(), bottom: float(), left: float()},
          border_width: %{top: float(), right: float(), bottom: float(), left: float()},
          border_color: %{top: term(), right: term(), bottom: term(), left: term()},
          border_style: %{top: term(), right: term(), bottom: term(), left: term()},
          background_color: term(),
          computed: map() | nil,
          children: [t()]
        }

  defstruct [
    :type,
    :tag,
    :x,
    :y,
    :width,
    :height,
    :text,
    :font,
    :font_size,
    :color,
    :image,
    letter_spacing: 0.0,
    header_row: false,
    margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
    border_color: %{top: nil, right: nil, bottom: nil, left: nil},
    border_style: %{top: :none, right: :none, bottom: :none, left: :none},
    background_color: nil,
    computed: %{},
    children: []
  ]

  @doc """
  Computes total outer width including content width, padding, border, and margin.
  """
  @spec outer_width(t()) :: float()
  def outer_width(%__MODULE__{} = box) do
    (box.width || 0.0) + box.padding.left + box.padding.right +
      box.border_width.left + box.border_width.right +
      box.margin.left + box.margin.right
  end

  @doc """
  Computes total outer height including content height, padding, border, and margin.
  """
  @spec outer_height(t()) :: float()
  def outer_height(%__MODULE__{} = box) do
    (box.height || 0.0) + box.padding.top + box.padding.bottom +
      box.border_width.top + box.border_width.bottom +
      box.margin.top + box.margin.bottom
  end

  @doc """
  Computes border-box width (content width + padding + border).
  """
  @spec border_box_width(t()) :: float()
  def border_box_width(%__MODULE__{} = box) do
    (box.width || 0.0) + box.padding.left + box.padding.right +
      box.border_width.left + box.border_width.right
  end

  @doc """
  Computes border-box height (content height + padding + border).
  """
  @spec border_box_height(t()) :: float()
  def border_box_height(%__MODULE__{} = box) do
    (box.height || 0.0) + box.padding.top + box.padding.bottom +
      box.border_width.top + box.border_width.bottom
  end
end
