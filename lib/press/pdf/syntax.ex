defmodule Press.PDF.Syntax do
  @moduledoc false

  def number(n) when is_integer(n), do: Integer.to_string(n)

  def number(n) when is_float(n) do
    if n == Float.round(n) do
      n |> trunc() |> Integer.to_string()
    else
      n
      |> :erlang.float_to_binary(decimals: 4)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end

  def escape_string(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end
end
