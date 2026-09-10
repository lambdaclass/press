defmodule Press.CSS.DefaultStylesheetTest do
  use ExUnit.Case, async: true

  alias Press.CSS.DefaultStylesheet

  test "produces rules for the tags the general spec's default stylesheet covers" do
    rules = DefaultStylesheet.rules()

    assert Enum.any?(rules, &(&1.selector == [%{type: "strong"}]))
    assert Enum.any?(rules, &(&1.selector == [%{type: "h1"}]))
    assert Enum.any?(rules, &(&1.selector == [%{type: "ol"}]))
  end

  test "h1 gets the expected font-size and margin declarations" do
    rules = DefaultStylesheet.rules()
    h1_rule = Enum.find(rules, &(&1.selector == [%{type: "h1"}]))

    assert h1_rule.declarations["font-size"] == {:length, 2.0, :em}
    assert h1_rule.declarations["margin-top"] == {:length, 0.67, :em}
  end

  test "produces no @page rules" do
    assert DefaultStylesheet.page_rules() == []
  end
end
