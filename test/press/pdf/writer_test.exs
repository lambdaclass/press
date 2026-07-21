defmodule Press.PDF.WriterTest do
  use ExUnit.Case, async: true

  alias Press.PDF.{Document, Writer}

  test "starts with the PDF header" do
    binary =
      Document.new()
      |> then(fn doc -> elem(Document.add_page(doc, 595.0, 842.0), 0) end)
      |> Writer.to_binary()

    assert String.starts_with?(binary, "%PDF-1.4\n")
  end

  test "includes a Pages object with the right /Count for multiple pages" do
    doc = Document.new()
    {doc, _} = Document.add_page(doc, 595.0, 842.0)
    {doc, _} = Document.add_page(doc, 595.0, 842.0)

    binary = Writer.to_binary(doc)

    assert binary =~ "/Type /Pages /Kids [3 0 R 5 0 R] /Count 2"
  end

  test "includes exactly one Font object per distinct font used, shared across pages" do
    doc = Document.new()
    {doc, p0} = Document.add_page(doc, 595.0, 842.0)
    {doc, p1} = Document.add_page(doc, 595.0, 842.0)
    doc = Document.draw_text(doc, p0, 0.0, 0.0, "a", font: :helvetica)
    doc = Document.draw_text(doc, p1, 0.0, 0.0, "b", font: :helvetica)

    binary = Writer.to_binary(doc)

    assert length(Regex.scan(~r{/BaseFont /Helvetica\b}, binary)) == 1
  end

  test "Font objects declare WinAnsiEncoding so accented characters render correctly" do
    doc = Document.new()
    {doc, p} = Document.add_page(doc, 595.0, 842.0)
    doc = Document.draw_text(doc, p, 0.0, 0.0, "café", font: :helvetica)

    binary = Writer.to_binary(doc)

    assert binary =~ "/Encoding /WinAnsiEncoding"
  end

  test "every xref offset points at the matching \"N 0 obj\"" do
    doc = Document.new()
    {doc, p} = Document.add_page(doc, 595.0, 842.0)
    doc = Document.draw_text(doc, p, 10.0, 20.0, "Hello world!", font: :helvetica_bold, size: 24)

    binary = Writer.to_binary(doc)

    [_before, xref_and_trailer] = String.split(binary, "xref\n", parts: 2)
    [entries_block, _trailer] = String.split(xref_and_trailer, "trailer\n", parts: 2)
    ["0 " <> _count | entry_lines] = String.split(entries_block, "\r\n", trim: true)

    entry_lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, obj_num} ->
      offset = line |> String.slice(0, 10) |> String.to_integer()
      following = binary |> String.slice(offset, byte_size("#{obj_num} 0 obj"))
      assert following == "#{obj_num} 0 obj"
    end)
  end

  test "ends with a valid trailer pointing at object 1 as Root" do
    doc = Document.new()
    {doc, _} = Document.add_page(doc, 595.0, 842.0)

    binary = Writer.to_binary(doc)

    assert binary =~ "trailer\n<< /Size"
    assert binary =~ "/Root 1 0 R"
    assert String.ends_with?(binary, "%%EOF")
  end

  test "handles a zero-page document without crashing, producing an empty /Kids array" do
    binary = Writer.to_binary(Document.new())

    assert binary =~ "/Kids [] /Count 0"
  end
end
