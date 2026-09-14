defmodule Press.Layout.ImageFitTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Box

  # 40x20 px PNG, aspect ratio 2:1
  defp png do
    "data:image/png;base64," <> Base.encode64(File.read!("test/fixtures/ratio_2to1.png"))
  end

  defp image_box(style) do
    html = """
    <html><head><style>* { margin: 0; padding: 0 }</style></head>
    <body><img style="#{style}" src="#{png()}" /></body></html>
    """

    dom = Press.HTML.Parser.parse(html)
    {page_css, rules} = Press.CSS.Parser.parse("")
    config = Press.Style.Cascade.page_config([], page_css)
    root = Press.Layout.build(Press.Style.Cascade.build(dom, [], rules), config, %{})
    find(root)
  end

  defp find(%Box{type: :image} = box), do: box
  defp find(%Box{children: children}), do: Enum.find_value(children || [], &find/1)
  defp find(_), do: nil

  defp painted(%Box{children: [%Box{type: :image} = inner]}), do: inner
  defp painted(%Box{} = box), do: box

  describe "object-fit" do
    test "by default both declared dimensions are used as given" do
      box = image_box("width: 100px; height: 100px")
      assert_in_delta box.width, 75.0, 0.01
      assert_in_delta box.height, 75.0, 0.01
    end

    test "contain scales the image inside the box without shrinking the box" do
      box = image_box("width: 100px; height: 100px; object-fit: contain")
      assert_in_delta box.width, 75.0, 0.01
      assert_in_delta box.height, 75.0, 0.01

      image = painted(box)
      assert_in_delta image.width, 75.0, 0.01
      assert_in_delta image.height, 37.5, 0.01
      assert_in_delta image.y - box.y, 18.75, 0.01
      assert_in_delta image.x - box.x, 0.0, 0.01
    end

    test "scale-down never enlarges" do
      box = image_box("width: 400px; height: 400px; object-fit: scale-down")
      image = painted(box)
      assert_in_delta image.width, 30.0, 0.01
      assert_in_delta image.height, 15.0, 0.01
    end
  end
end
