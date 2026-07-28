defmodule Press.CSS.Shorthand do
  @moduledoc false

  alias Press.CSS.Value

  def expand_box(property, raw_value, parse_fun) do
    with {:ok, [top, right, bottom, left]} <- expand_sides(String.split(raw_value)),
         {:ok, t} <- parse_fun.(top),
         {:ok, r} <- parse_fun.(right),
         {:ok, b} <- parse_fun.(bottom),
         {:ok, l} <- parse_fun.(left) do
      {:ok,
       %{
         "#{property}-top" => t,
         "#{property}-right" => r,
         "#{property}-bottom" => b,
         "#{property}-left" => l
       }}
    else
      :error -> :error
    end
  end

  def expand_page_margin(raw_value) do
    with {:ok, [top, right, bottom, left]} <- expand_sides(String.split(raw_value)),
         {:ok, t} <- Value.parse_length(top),
         {:ok, r} <- Value.parse_length(right),
         {:ok, b} <- Value.parse_length(bottom),
         {:ok, l} <- Value.parse_length(left) do
      {:ok, %{top: t, right: r, bottom: b, left: l}}
    else
      :error -> :error
    end
  end

  @sides ~w(top right bottom left)

  def expand_border(raw_value) do
    case raw_value |> String.split() |> Enum.reduce({:ok, %{}}, &expand_border_part/2) do
      {:ok, parts} -> {:ok, fan_out_to_sides(parts)}
      :error -> :error
    end
  end

  # The `border` shorthand always applies the same width/style/color to
  # all four sides (unlike `margin`/`padding`, there's no 1/2/3/4-value
  # per-side form of the compound `border` shorthand in CSS). Still fan
  # each resolved property out to "<property>-top/right/bottom/left" so
  # Press.Style.Cascade's per-property merge (which only ever looks for
  # longhand keys, same as every other box property) sees it correctly
  # instead of a flat "border-width"/"border-style"/"border-color" key
  # nothing else in the pipeline reads.
  defp fan_out_to_sides(parts) do
    Enum.reduce(parts, %{}, fn {property, value}, acc ->
      Enum.reduce(@sides, acc, fn side, acc2 -> Map.put(acc2, "#{property}-#{side}", value) end)
    end)
  end

  defp expand_border_part(_part, :error), do: :error

  defp expand_border_part(part, {:ok, acc}) do
    cond do
      match?({:ok, _}, Value.parse_length(part)) ->
        {:ok, v} = Value.parse_length(part)
        {:ok, Map.put(acc, "border-width", v)}

      match?({:ok, _}, Value.parse_keyword(part, [:solid])) ->
        {:ok, Map.put(acc, "border-style", :solid)}

      match?({:ok, _}, Value.parse_color(part)) ->
        {:ok, v} = Value.parse_color(part)
        {:ok, Map.put(acc, "border-color", v)}

      true ->
        :error
    end
  end

  defp expand_sides([a]), do: {:ok, [a, a, a, a]}
  defp expand_sides([a, b]), do: {:ok, [a, b, a, b]}
  defp expand_sides([a, b, c]), do: {:ok, [a, b, c, b]}
  defp expand_sides([a, b, c, d]), do: {:ok, [a, b, c, d]}
  defp expand_sides(_other), do: :error
end
