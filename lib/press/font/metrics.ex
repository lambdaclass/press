defmodule Press.Font.Metrics do
  @moduledoc false

  @helvetica_widths %{
    32 => 278,
    33 => 278,
    34 => 355,
    35 => 556,
    36 => 556,
    37 => 889,
    38 => 667,
    39 => 222,
    40 => 333,
    41 => 333,
    42 => 389,
    43 => 584,
    44 => 278,
    45 => 333,
    46 => 278,
    47 => 278,
    48 => 556,
    49 => 556,
    50 => 556,
    51 => 556,
    52 => 556,
    53 => 556,
    54 => 556,
    55 => 556,
    56 => 556,
    57 => 556,
    58 => 278,
    59 => 278,
    60 => 584,
    61 => 584,
    62 => 584,
    63 => 556,
    64 => 1015,
    65 => 667,
    66 => 667,
    67 => 722,
    68 => 722,
    69 => 667,
    70 => 611,
    71 => 778,
    72 => 722,
    73 => 278,
    74 => 500,
    75 => 667,
    76 => 556,
    77 => 833,
    78 => 722,
    79 => 778,
    80 => 667,
    81 => 778,
    82 => 722,
    83 => 667,
    84 => 611,
    85 => 722,
    86 => 667,
    87 => 944,
    88 => 667,
    89 => 667,
    90 => 611,
    91 => 278,
    92 => 278,
    93 => 278,
    94 => 469,
    95 => 556,
    96 => 222,
    97 => 556,
    98 => 556,
    99 => 500,
    100 => 556,
    101 => 556,
    102 => 278,
    103 => 556,
    104 => 556,
    105 => 222,
    106 => 222,
    107 => 500,
    108 => 222,
    109 => 833,
    110 => 556,
    111 => 556,
    112 => 556,
    113 => 556,
    114 => 333,
    115 => 500,
    116 => 278,
    117 => 556,
    118 => 500,
    119 => 722,
    120 => 500,
    121 => 500,
    122 => 500,
    123 => 334,
    124 => 260,
    125 => 334,
    126 => 584
  }

  @helvetica_bold_widths %{
    32 => 278,
    33 => 333,
    34 => 474,
    35 => 556,
    36 => 556,
    37 => 889,
    38 => 722,
    39 => 278,
    40 => 333,
    41 => 333,
    42 => 389,
    43 => 584,
    44 => 278,
    45 => 333,
    46 => 278,
    47 => 278,
    48 => 556,
    49 => 556,
    50 => 556,
    51 => 556,
    52 => 556,
    53 => 556,
    54 => 556,
    55 => 556,
    56 => 556,
    57 => 556,
    58 => 333,
    59 => 333,
    60 => 584,
    61 => 584,
    62 => 584,
    63 => 611,
    64 => 975,
    65 => 722,
    66 => 722,
    67 => 722,
    68 => 722,
    69 => 667,
    70 => 611,
    71 => 778,
    72 => 722,
    73 => 278,
    74 => 556,
    75 => 722,
    76 => 611,
    77 => 833,
    78 => 722,
    79 => 778,
    80 => 667,
    81 => 778,
    82 => 722,
    83 => 667,
    84 => 611,
    85 => 722,
    86 => 667,
    87 => 944,
    88 => 667,
    89 => 667,
    90 => 611,
    91 => 333,
    92 => 278,
    93 => 333,
    94 => 584,
    95 => 556,
    96 => 278,
    97 => 556,
    98 => 611,
    99 => 556,
    100 => 611,
    101 => 556,
    102 => 333,
    103 => 611,
    104 => 611,
    105 => 278,
    106 => 278,
    107 => 556,
    108 => 278,
    109 => 889,
    110 => 611,
    111 => 611,
    112 => 611,
    113 => 611,
    114 => 389,
    115 => 556,
    116 => 333,
    117 => 611,
    118 => 556,
    119 => 778,
    120 => 556,
    121 => 556,
    122 => 500,
    123 => 389,
    124 => 280,
    125 => 389,
    126 => 584
  }

  @times_widths %{
    32 => 250,
    33 => 333,
    34 => 408,
    35 => 500,
    36 => 500,
    37 => 833,
    38 => 778,
    39 => 180,
    40 => 333,
    41 => 333,
    42 => 500,
    43 => 564,
    44 => 250,
    45 => 333,
    46 => 250,
    47 => 278,
    48 => 500,
    49 => 500,
    50 => 500,
    51 => 500,
    52 => 500,
    53 => 500,
    54 => 500,
    55 => 500,
    56 => 500,
    57 => 500,
    58 => 278,
    59 => 278,
    60 => 564,
    61 => 564,
    62 => 564,
    63 => 444,
    64 => 921,
    65 => 722,
    66 => 667,
    67 => 667,
    68 => 722,
    69 => 611,
    70 => 556,
    71 => 722,
    72 => 722,
    73 => 333,
    74 => 444,
    75 => 722,
    76 => 611,
    77 => 889,
    78 => 722,
    79 => 722,
    80 => 611,
    81 => 722,
    82 => 667,
    83 => 556,
    84 => 611,
    85 => 722,
    86 => 667,
    87 => 889,
    88 => 667,
    89 => 667,
    90 => 611,
    91 => 333,
    92 => 278,
    93 => 333,
    94 => 441,
    95 => 500,
    96 => 333,
    97 => 444,
    98 => 500,
    99 => 444,
    100 => 500,
    101 => 444,
    102 => 333,
    103 => 500,
    104 => 500,
    105 => 278,
    106 => 278,
    107 => 500,
    108 => 278,
    109 => 778,
    110 => 500,
    111 => 500,
    112 => 500,
    113 => 500,
    114 => 333,
    115 => 389,
    116 => 278,
    117 => 500,
    118 => 500,
    119 => 722,
    120 => 500,
    121 => 500,
    122 => 444,
    123 => 480,
    124 => 200,
    125 => 480,
    126 => 541
  }

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
  def char_width(font, codepoint) when font in [:courier, :courier_bold, :courier_oblique, :courier_bold_oblique] do
    _ = codepoint
    600
  end

  def char_width(font, codepoint) when font in [:helvetica, :helvetica_oblique] do
    Map.get(@helvetica_widths, codepoint, 556)
  end

  def char_width(font, codepoint) when font in [:helvetica_bold, :helvetica_bold_oblique] do
    Map.get(@helvetica_bold_widths, codepoint, 600)
  end

  def char_width(font, codepoint) when font in [:times_roman, :times_italic, :times_bold, :times_bold_italic] do
    Map.get(@times_widths, codepoint, 500)
  end

  def char_width(_other, codepoint) do
    Map.get(@helvetica_widths, codepoint, 556)
  end

  @doc """
  Computes total text width in points.
  """
  def text_width(_font, "", _font_size), do: 0.0

  def text_width(font, text, font_size) when is_binary(text) and is_number(font_size) do
    total_units =
      text
      |> String.to_charlist()
      |> Enum.reduce(0, fn cp, acc -> acc + char_width(font, cp) end)

    total_units * font_size / 1000.0
  end
end
