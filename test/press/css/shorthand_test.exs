defmodule Press.CSS.ShorthandTest do
  use ExUnit.Case, async: true

  alias Press.CSS.{Shorthand, Value}

  describe "expand_box/3" do
    test "1 value applies to all four sides" do
      assert Shorthand.expand_box("margin", "1em", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 1.0, :em},
                  "margin-right" => {:length, 1.0, :em},
                  "margin-bottom" => {:length, 1.0, :em},
                  "margin-left" => {:length, 1.0, :em}
                }}
    end

    test "2 values: top/bottom, left/right" do
      assert Shorthand.expand_box("margin", "1em 2em", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 1.0, :em},
                  "margin-right" => {:length, 2.0, :em},
                  "margin-bottom" => {:length, 1.0, :em},
                  "margin-left" => {:length, 2.0, :em}
                }}
    end

    test "3 values: top, left/right, bottom" do
      assert Shorthand.expand_box("margin", "1pt 2pt 3pt", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 1.0, :pt},
                  "margin-right" => {:length, 2.0, :pt},
                  "margin-bottom" => {:length, 3.0, :pt},
                  "margin-left" => {:length, 2.0, :pt}
                }}
    end

    test "4 values: top, right, bottom, left" do
      assert Shorthand.expand_box("margin", "20mm 15mm 25mm 15mm", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 20.0, :mm},
                  "margin-right" => {:length, 15.0, :mm},
                  "margin-bottom" => {:length, 25.0, :mm},
                  "margin-left" => {:length, 15.0, :mm}
                }}
    end

    test "rejects more than 4 values" do
      assert Shorthand.expand_box("margin", "1pt 2pt 3pt 4pt 5pt", &Value.parse_length/1) ==
               :error
    end

    test "rejects a value that fails the given parser" do
      assert Shorthand.expand_box("margin", "1pt notalength", &Value.parse_length/1) == :error
    end
  end

  describe "expand_page_margin/1" do
    test "expands into a single top/right/bottom/left map" do
      assert Shorthand.expand_page_margin("20mm 15mm 25mm 15mm") ==
               {:ok,
                %{
                  top: {:length, 20.0, :mm},
                  right: {:length, 15.0, :mm},
                  bottom: {:length, 25.0, :mm},
                  left: {:length, 15.0, :mm}
                }}
    end

    test "1 value applies to all four sides" do
      assert Shorthand.expand_page_margin("20mm") ==
               {:ok,
                %{
                  top: {:length, 20.0, :mm},
                  right: {:length, 20.0, :mm},
                  bottom: {:length, 20.0, :mm},
                  left: {:length, 20.0, :mm}
                }}
    end
  end

  describe "expand_border/1" do
    test "expands width, style, and color to all four sides, regardless of order" do
      expected =
        {:ok,
         %{
           "border-width-top" => {:length, 1.0, :px},
           "border-width-right" => {:length, 1.0, :px},
           "border-width-bottom" => {:length, 1.0, :px},
           "border-width-left" => {:length, 1.0, :px},
           "border-style-top" => :solid,
           "border-style-right" => :solid,
           "border-style-bottom" => :solid,
           "border-style-left" => :solid,
           "border-color-top" => {0.0, 0.0, 0.0},
           "border-color-right" => {0.0, 0.0, 0.0},
           "border-color-bottom" => {0.0, 0.0, 0.0},
           "border-color-left" => {0.0, 0.0, 0.0}
         }}

      assert Shorthand.expand_border("1px solid #000000") == expected
      assert Shorthand.expand_border("solid #000000 1px") == expected
    end

    test "accepts a subset of the three parts" do
      assert Shorthand.expand_border("1px solid") ==
               {:ok,
                %{
                  "border-width-top" => {:length, 1.0, :px},
                  "border-width-right" => {:length, 1.0, :px},
                  "border-width-bottom" => {:length, 1.0, :px},
                  "border-width-left" => {:length, 1.0, :px},
                  "border-style-top" => :solid,
                  "border-style-right" => :solid,
                  "border-style-bottom" => :solid,
                  "border-style-left" => :solid
                }}
    end

    test "rejects a part that isn't a valid width, style, or color" do
      assert Shorthand.expand_border("1px solid dashed") == :error
    end
  end

  describe "background" do
    test "the shorthand sets the background colour" do
      decls = Press.CSS.Parser.parse_declarations("background: #f4f4f5")
      assert {r, g, b} = decls["background-color"]
      assert_in_delta r, 244 / 255, 0.001
      assert_in_delta g, 244 / 255, 0.001
      assert_in_delta b, 245 / 255, 0.001
    end

    test "a background carrying something Press cannot paint is dropped whole" do
      decls = Press.CSS.Parser.parse_declarations("background: url(x.png) no-repeat")
      refute Map.has_key?(decls, "background-color")
    end
  end
end
