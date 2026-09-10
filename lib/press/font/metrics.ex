defmodule Press.Font.Metrics do
  @moduledoc false

  @doc """
  Returns the matching PDF base font atom for the given font family, weight, and style.
  """
  def font_for(family, weight \\ :normal, style \\ :normal)

  def font_for(:helvetica, :normal, :normal), do: :helvetica
  def font_for(:helvetica, :bold, :normal), do: :helvetica_bold
  def font_for(:helvetica, :normal, :italic), do: :helvetica_oblique
  def font_for(:helvetica, :bold, :italic), do: :helvetica_bold_oblique

  def font_for(:times, :normal, :normal), do: :times_roman
  def font_for(:times, :bold, :normal), do: :times_bold
  def font_for(:times, :normal, :italic), do: :times_italic
  def font_for(:times, :bold, :italic), do: :times_bold_italic

  def font_for(:courier, :normal, :normal), do: :courier
  def font_for(:courier, :bold, :normal), do: :courier_bold
  def font_for(:courier, :normal, :italic), do: :courier_oblique
  def font_for(:courier, :bold, :italic), do: :courier_bold_oblique

  def font_for(font, _weight, _style)
      when font in [
             :helvetica,
             :helvetica_bold,
             :helvetica_oblique,
             :helvetica_bold_oblique,
             :times_roman,
             :times_bold,
             :times_italic,
             :times_bold_italic,
             :courier,
             :courier_bold,
             :courier_oblique,
             :courier_bold_oblique,
             :symbol,
             :zapf_dingbats
           ],
      do: font

  def font_for(_other, weight, style), do: font_for(:helvetica, weight, style)

  @doc """
  Returns the advance width of a character in 1/1000 em units.
  """
  defdelegate char_width(font, codepoint), to: Press.Font.Widths

  @doc """
  Computes total text width in points.
  """
  def text_width(font, text, font_size, letter_spacing \\ 0.0)

  def text_width(_font, "", _font_size, _letter_spacing), do: 0.0

  def text_width(font, text, font_size, letter_spacing)
      when is_binary(text) and is_number(font_size) do
    chars = String.to_charlist(text)
    total_units = Enum.reduce(chars, 0, fn cp, acc -> acc + char_width(font, cp) end)

    total_units * font_size / 1000.0 + length(chars) * letter_spacing
  end
end
