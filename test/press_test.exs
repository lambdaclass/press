defmodule PressTest do
  use ExUnit.Case
  doctest Press

  test "greets the world" do
    assert Press.hello() == :world
  end
end
