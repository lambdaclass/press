defmodule Press.HTML.EntitiesTest do
  use ExUnit.Case, async: true

  alias Press.HTML.Entities

  test "decodes the 5 XML entities" do
    assert Entities.decode("&amp;") == "&"
    assert Entities.decode("&lt;") == "<"
    assert Entities.decode("&gt;") == ">"
    assert Entities.decode("&quot;") == "\""
    assert Entities.decode("&apos;") == "'"
  end

  test "decodes decimal numeric entities" do
    assert Entities.decode("&#233;") == "é"
  end

  test "decodes hex numeric entities, case-insensitively on the x" do
    assert Entities.decode("&#xE9;") == "é"
    assert Entities.decode("&#Xe9;") == "é"
  end

  test "decodes multiple entities in one string" do
    assert Entities.decode("Ben &amp; Jerry&#39;s") == "Ben & Jerry's"
  end

  test "leaves an unrecognized entity name as literal text" do
    assert Entities.decode("&nbsp;") == "&nbsp;"
  end

  test "leaves a malformed entity (no terminating ;) as literal text" do
    assert Entities.decode("&amp") == "&amp"
    assert Entities.decode("&#233") == "&#233"
  end

  test "leaves a bare & as literal text" do
    assert Entities.decode("Ben & Jerry's") == "Ben & Jerry's"
  end

  test "leaves text with no entities untouched" do
    assert Entities.decode("Hello world!") == "Hello world!"
  end
end
