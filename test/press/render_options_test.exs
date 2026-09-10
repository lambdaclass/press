defmodule Press.RenderOptionsTest do
  use ExUnit.Case, async: true

  defp page_size(pdf) do
    [_, w, h] = Regex.run(~r|/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]|, pdf)
    {number(w), number(h)}
  end

  # A whole number is written without a decimal part, so both forms turn up.
  defp number(str) do
    {value, ""} = Float.parse(if String.contains?(str, "."), do: str, else: str <> ".0")
    round(value)
  end

  defp content(pdf) do
    Regex.scan(~r/stream\r?\n(.*?)endstream/s, pdf)
    |> Enum.map(fn [_, s] ->
      try do
        :zlib.uncompress(s)
      rescue
        _ -> s
      end
    end)
    |> Enum.join("\n")
  end

  @html ~s|<html><head><style>p{font-weight:bold}</style></head><body><p>Hola</p></body></html>|

  describe ":page option" do
    test "a named size is used instead of the CSS default" do
      {:ok, pdf} = Press.render(@html, page: [size: :letter])
      assert page_size(pdf) == {612, 792}
    end

    test "an explicit pair of points is used verbatim" do
      {:ok, pdf} = Press.render(@html, page: [size: {400.0, 300.0}])
      assert page_size(pdf) == {400, 300}
    end

    test "landscape swaps the resolved pair" do
      {:ok, pdf} = Press.render(@html, page: [size: :a4, landscape: true])
      {w, h} = page_size(pdf)
      assert w > h
    end

    test "a margin moves the content without changing the page" do
      {:ok, tight} = Press.render(@html, page: [size: :a4, margin: 0.0])
      {:ok, roomy} = Press.render(@html, page: [size: :a4, margin: 100.0])

      assert page_size(tight) == page_size(roomy)
      assert content(tight) != content(roomy)
    end

    test "a margin map only overrides the sides it names" do
      {:ok, pdf} = Press.render(@html, page: [size: :a4, margin: %{left: 120.0}])
      assert content(pdf) =~ "120"
    end
  end

  describe ":bold_boost option" do
    test "is off by default, so no stroke is emitted" do
      {:ok, pdf} = Press.render(@html)
      refute content(pdf) =~ "2 Tr"
    end

    test "strokes bold glyphs to synthesise a heavier weight" do
      {:ok, pdf} = Press.render(@html, bold_boost: 0.02)
      assert content(pdf) =~ "2 Tr"
    end

    test "leaves regular text alone" do
      regular = ~s|<html><body><p>Hola</p></body></html>|
      {:ok, pdf} = Press.render(regular, bold_boost: 0.02)
      refute content(pdf) =~ "2 Tr"
    end

    test "does not change where the text sits" do
      {:ok, plain} = Press.render(@html)
      {:ok, bold} = Press.render(@html, bold_boost: 0.02)

      positions = fn pdf -> Regex.scan(~r/([\d.]+) ([\d.]+) Td/, content(pdf)) end
      assert positions.(plain) == positions.(bold)
    end
  end
end
