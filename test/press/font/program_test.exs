defmodule Press.Font.ProgramTest do
  use ExUnit.Case, async: true

  alias Press.Font.Program

  # A minimal sfnt carrying only the tables Program reads. Building one here
  # keeps the parser under test without shipping a font with the suite.
  defp sfnt(tables) do
    count = map_size(tables)
    entries = Map.to_list(tables)
    directory_size = 12 + count * 16

    {records, blobs, _offset} =
      Enum.reduce(entries, {[], [], directory_size}, fn {tag, data}, {recs, blob, off} ->
        padded = data <> String.duplicate(<<0>>, rem(4 - rem(byte_size(data), 4), 4))

        {recs ++ [<<tag::binary-size(4), 0::32, off::32, byte_size(data)::32>>],
         blob ++ [padded], off + byte_size(padded)}
      end)

    IO.iodata_to_binary([
      "OTTO",
      <<count::16, 0::16, 0::16, 0::16>>,
      records,
      blobs
    ])
  end

  defp head(upem, bbox) do
    {x_min, y_min, x_max, y_max} = bbox

    <<0::size(18)-unit(8), upem::16, 0::size(16)-unit(8), x_min::signed-16, y_min::signed-16,
      x_max::signed-16, y_max::signed-16>>
  end

  defp hhea(ascent, descent) do
    <<0::32, ascent::signed-16, descent::signed-16, 0::size(28)-unit(8)>>
  end

  defp os2(version, weight, cap_height) do
    <<version::16, 0::16, weight::16, 0::16, 0::16, 0::size(22)-unit(8), 0::size(32)-unit(8),
      0::size(10)-unit(8), 0::size(14)-unit(8), cap_height::signed-16>>
  end

  defp minimal(opts \\ []) do
    sfnt(%{
      "head" => head(Keyword.get(opts, :upem, 1000), {-100, -250, 1100, 950}),
      "hhea" => hhea(Keyword.get(opts, :ascent, 718), Keyword.get(opts, :descent, -207)),
      "OS/2" => os2(2, Keyword.get(opts, :weight, 400), 700),
      "CFF " => Keyword.get(opts, :cff, "cff-outlines")
    })
  end

  describe "load/1" do
    test "reads the descriptor metrics a PDF font descriptor needs" do
      assert {:ok, program} = Program.load(minimal())
      assert program.ascent == 718
      assert program.descent == -207
      assert program.cap_height == 700
      assert program.bbox == {-100, -250, 1100, 950}
      assert program.italic_angle == 0
    end

    test "scales metrics when the font is not on a 1000 unit em" do
      assert {:ok, program} = Program.load(minimal(upem: 2048, ascent: 1900))
      assert program.ascent == 928
    end

    test "an OpenType font embeds its CFF table on its own" do
      assert {:ok, program} = Program.load(minimal(cff: "the-outlines"))
      assert program.file_key == "FontFile3"
      assert program.subtype == "Type1C"
      assert program.data == "the-outlines"
    end

    test "a TrueType font is embedded whole" do
      data =
        sfnt(%{
          "head" => head(1000, {0, -200, 1000, 900}),
          "hhea" => hhea(750, -250),
          "glyf" => "outlines"
        })

      assert {:ok, program} = Program.load(<<0, 1, 0, 0>> <> binary_part(data, 4, byte_size(data) - 4))
      assert program.file_key == "FontFile2"
      assert program.subtype == nil
    end

    test "a heavier weight declares a heavier stem" do
      assert {:ok, regular} = Program.load(minimal(weight: 400))
      assert {:ok, bold} = Program.load(minimal(weight: 700))
      assert bold.stem_v > regular.stem_v
    end

    test "reports an unreadable file instead of raising" do
      assert {:error, {:unreadable_font, "/no/such/font.otf", :enoent}} =
               Program.load("/no/such/font.otf")
    end

    test "rejects something that is not a font" do
      assert {:error, _} = Program.load("no soy una fuente")
    end
  end

  describe "Press.render/2 with :embed_fonts" do
    @html ~s|<html><head><style>p{font-weight:bold}</style></head><body><p>Hola</p></body></html>|

    test "carries the font program and its descriptor into the PDF" do
      {:ok, pdf} = Press.render(@html, embed_fonts: %{helvetica_bold: minimal()})

      assert pdf =~ "/FontDescriptor"
      assert pdf =~ "/FontFile3"
      assert pdf =~ "/Subtype /Type1C"
      assert pdf =~ "/Widths ["
    end

    test "without the option the reader is asked for a base font" do
      {:ok, pdf} = Press.render(@html)

      refute pdf =~ "/FontDescriptor"
      assert pdf =~ "/BaseFont /Helvetica-Bold"
    end

    test "an unreadable font falls back to the base font instead of failing" do
      {:ok, pdf} = Press.render(@html, embed_fonts: %{helvetica_bold: "/no/such/font.otf"})

      assert pdf =~ "/BaseFont /Helvetica-Bold"
      refute pdf =~ "/FontFile3"
    end

    test "embedding does not move the text" do
      {:ok, plain} = Press.render(@html)
      {:ok, embedded} = Press.render(@html, embed_fonts: %{helvetica_bold: minimal()})

      positions = fn pdf -> Regex.scan(~r/([\d.]+) ([\d.]+) Td/, pdf) end
      assert positions.(plain) == positions.(embedded)
    end
  end

  describe "Fonts.winansi_widths/1" do
    test "covers every code a /Widths array declares, in order" do
      widths = Press.PDF.Fonts.winansi_widths(:helvetica)

      assert length(widths) == 224
      assert Enum.at(widths, 0) == 278
      assert Enum.at(widths, ?A - 32) == 667
      assert Enum.at(widths, 0xF1 - 32) == 556
    end

    test "maps the Windows punctuation block, not the control characters" do
      widths = Press.PDF.Fonts.winansi_widths(:helvetica)
      # 0x80 is the euro sign in WinAnsi, not U+0080.
      assert Enum.at(widths, 0x80 - 32) == Press.Font.Widths.char_width(:helvetica, 0x20AC)
    end
  end
end
