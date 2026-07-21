defmodule Press.PDF.DocumentTest do
  use ExUnit.Case, async: true

  alias Press.PDF.Document

  test "new/0 starts with no pages" do
    assert Document.new().pages == []
  end

  test "add_page/3 appends a page and returns its index" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)

    assert index == 0
    assert [%Press.PDF.Page{width: 595.0, height: 842.0, ops: []}] = doc.pages
  end

  test "add_page/3 returns increasing indexes for successive pages" do
    {doc, index0} = Document.new() |> Document.add_page(595.0, 842.0)
    {doc, index1} = Document.add_page(doc, 595.0, 842.0)

    assert index0 == 0
    assert index1 == 1
    assert length(doc.pages) == 2
  end

  test "draw_text/6 appends a text op to the given page" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)

    doc =
      Document.draw_text(doc, index, 10.0, 20.0, "Hello world!", font: :helvetica_bold, size: 24)

    assert [
             %Press.PDF.Page{
               ops: [{:text, 10.0, 20.0, :helvetica_bold, 24, {0, 0, 0}, "Hello world!"}]
             }
           ] =
             doc.pages
  end

  test "draw_text/6 defaults to helvetica, size 12, black" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)
    doc = Document.draw_text(doc, index, 0.0, 0.0, "x")

    assert [%Press.PDF.Page{ops: [{:text, 0.0, 0.0, :helvetica, 12, {0, 0, 0}, "x"}]}] = doc.pages
  end

  test "draw_rect/6 appends a rect op with fill and stroke" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)

    doc =
      Document.draw_rect(doc, index, 1.0, 2.0, 3.0, 4.0,
        fill: {0.9, 0.9, 0.9},
        stroke: {0, 0, 0},
        stroke_width: 1.5
      )

    assert [%Press.PDF.Page{ops: [{:rect, 1.0, 2.0, 3.0, 4.0, {0.9, 0.9, 0.9}, {0, 0, 0}, 1.5}]}] =
             doc.pages
  end

  test "draw_rect/6 defaults to no fill, no stroke, stroke_width 1.0" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)
    doc = Document.draw_rect(doc, index, 0.0, 0.0, 1.0, 1.0)

    assert [%Press.PDF.Page{ops: [{:rect, 0.0, 0.0, 1.0, 1.0, nil, nil, 1.0}]}] = doc.pages
  end

  test "draw_text/6 raises on an out-of-range page index" do
    {doc, _index} = Document.new() |> Document.add_page(595.0, 842.0)

    assert_raise ArgumentError, fn ->
      Document.draw_text(doc, 5, 0.0, 0.0, "x")
    end
  end
end
