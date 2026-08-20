defmodule Press.Layout.PageTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Page

  test "instantiates a page struct with dimensions and margin" do
    page = %Page{
      number: 1,
      width: 595.28,
      height: 841.89,
      margin: %{top: 56.69, right: 56.69, bottom: 56.69, left: 56.69},
      boxes: []
    }

    assert page.number == 1
    assert page.width == 595.28
    assert page.height == 841.89
    assert page.margin.top == 56.69
    assert page.boxes == []
  end
end
