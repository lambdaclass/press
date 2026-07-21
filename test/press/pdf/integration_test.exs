defmodule Press.PDF.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.PDF.{Document, Writer}

  test "produces a structurally valid PDF with a box and text on it" do
    doc = Document.new()
    {doc, page} = Document.add_page(doc, 595.0, 842.0)

    doc =
      doc
      |> Document.draw_rect(page, 50.0, 700.0, 200.0, 80.0,
        fill: {0.9, 0.9, 0.9},
        stroke: {0, 0, 0},
        stroke_width: 1.0
      )
      |> Document.draw_text(page, 60.0, 750.0, "Hello world!", font: :helvetica_bold, size: 24)

    binary = Writer.to_binary(doc)

    assert String.starts_with?(binary, "%PDF-1.4\n")
    assert binary =~ "/BaseFont /Helvetica-Bold"
    assert binary =~ "(Hello world!) Tj"
    assert binary =~ "trailer"
    assert String.ends_with?(binary, "%%EOF")

    tmp_path = Path.join(System.tmp_dir!(), "press_integration_test.pdf")
    File.write!(tmp_path, binary)
    on_exit(fn -> File.rm(tmp_path) end)
  end
end
