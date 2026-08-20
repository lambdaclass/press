defmodule Press.Layout.BoxTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Box

  test "instantiates a default box" do
    box = %Box{type: :block, width: 100.0, height: 50.0}

    assert box.type == :block
    assert box.width == 100.0
    assert box.height == 50.0
    assert box.margin == %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0}
    assert box.padding == %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0}
    assert box.children == []
  end

  test "outer_width/1 and outer_height/1 include margin, border, and padding" do
    box = %Box{
      type: :block,
      width: 100.0,
      height: 50.0,
      margin: %{top: 10.0, right: 15.0, bottom: 10.0, left: 15.0},
      padding: %{top: 5.0, right: 8.0, bottom: 5.0, left: 8.0},
      border_width: %{top: 1.0, right: 2.0, bottom: 1.0, left: 2.0}
    }

    # Width: 100 + 15*2 (margin) + 8*2 (padding) + 2*2 (border) = 150
    assert Box.outer_width(box) == 150.0
    # Height: 50 + 10*2 (margin) + 5*2 (padding) + 1*2 (border) = 82
    assert Box.outer_height(box) == 82.0
  end

  test "border_box dimensions include padding and border without margin" do
    box = %Box{
      type: :block,
      width: 100.0,
      height: 50.0,
      margin: %{top: 10.0, right: 15.0, bottom: 10.0, left: 15.0},
      padding: %{top: 5.0, right: 8.0, bottom: 5.0, left: 8.0},
      border_width: %{top: 1.0, right: 2.0, bottom: 1.0, left: 2.0}
    }

    assert Box.border_box_width(box) == 120.0
    assert Box.border_box_height(box) == 62.0
  end
end
