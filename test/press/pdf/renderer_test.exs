defmodule Press.PDF.RendererTest do
  use ExUnit.Case, async: true

  alias Press.Layout.{Box, Page}
  alias Press.PDF.{Document, Renderer}

  defp default_page(boxes) do
    %Page{
      number: 1,
      width: 600.0,
      height: 800.0,
      margin: %{top: 50.0, right: 50.0, bottom: 50.0, left: 50.0},
      boxes: boxes
    }
  end

  describe "render_document/2" do
    test "converts text boxes into PDF text operations in bottom-left coordinate space" do
      text_box = %Box{
        type: :text,
        x: 50.0,
        y: 100.0,
        width: 100.0,
        height: 14.4,
        text: "Invoice",
        font: :helvetica_bold,
        font_size: 24.0,
        color: {1.0, 0.0, 0.0}
      }

      page = default_page([text_box])
      doc = Renderer.render_document([page], %{})

      assert %Document{pages: [pdf_page]} = doc
      assert pdf_page.width == 600.0
      assert pdf_page.height == 800.0

      # In PDF coordinates, y is 800 - 100 - 24*0.8 = 680.8
      assert [
               {:text, 50.0, pdf_y, :helvetica_bold, 24.0, {1.0, +0.0, +0.0}, "Invoice"}
             ] = pdf_page.ops

      assert_in_delta pdf_y, 680.8, 0.1
    end

    test "renders background color and borders as filled rectangles" do
      box = %Box{
        type: :block,
        x: 50.0,
        y: 50.0,
        width: 200.0,
        height: 100.0,
        background_color: {0.9, 0.9, 0.9},
        border_width: %{top: 2.0, right: 2.0, bottom: 2.0, left: 2.0},
        border_color: %{top: {0, 0, 0}, right: {0, 0, 0}, bottom: {0, 0, 0}, left: {0, 0, 0}},
        border_style: %{top: :solid, right: :solid, bottom: :solid, left: :solid}
      }

      page = default_page([box])
      doc = Renderer.render_document([page], %{})

      assert %Document{pages: [pdf_page]} = doc
      # Should contain background rect and border rects
      assert length(pdf_page.ops) >= 1
      assert Enum.any?(pdf_page.ops, fn op -> match?({:rect, _, _, _, _, {0.9, 0.9, 0.9}, _, _}, op) end)
    end
  end
end
