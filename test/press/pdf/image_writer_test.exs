defmodule Press.PDF.ImageWriterTest do
  use ExUnit.Case, async: true

  alias Press.Image
  alias Press.PDF.{Document, Writer}

  @sample_jpeg <<
    0xFF, 0xD8,
    0xFF, 0xE0, 0x00, 0x10, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0,
    0xFF, 0xC0, 0x00, 0x11, 8, 0x00, 0x14, 0x00, 0x0A, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0,
    0xFF, 0xD9
  >>

  test "writes a PDF document containing a JPEG image XObject" do
    {:ok, img} = Press.Image.JPEG.parse(@sample_jpeg)
    img = %{img | id: "img_1"}

    {doc, idx} = Document.new() |> Document.add_page(600.0, 800.0)
    doc = Document.draw_image(doc, idx, 50.0, 700.0, 100.0, 50.0, img)

    pdf_binary = Writer.to_binary(doc)

    assert String.starts_with?(pdf_binary, "%PDF-1.4")
    assert pdf_binary =~ "/XObject << /Im1"
    assert pdf_binary =~ "/Subtype /Image"
    assert pdf_binary =~ "/Filter /DCTDecode"
    assert pdf_binary =~ "/Width 10 /Height 20"
    assert pdf_binary =~ "/Im1 Do"
  end

  test "writes a PDF document containing a PNG image with /SMask" do
    img = %Image{
      id: "png_1",
      format: :png,
      width: 2,
      height: 1,
      color_space: :rgb,
      data: :zlib.compress(<<255, 0, 0, 0, 0, 255>>),
      alpha_data: :zlib.compress(<<128, 255>>)
    }

    {doc, idx} = Document.new() |> Document.add_page(600.0, 800.0)
    doc = Document.draw_image(doc, idx, 50.0, 700.0, 100.0, 50.0, img)

    pdf_binary = Writer.to_binary(doc)

    assert String.starts_with?(pdf_binary, "%PDF-1.4")
    assert pdf_binary =~ "/Filter /FlateDecode"
    assert pdf_binary =~ "/SMask"
    assert pdf_binary =~ "/Im1 Do"
  end
end
