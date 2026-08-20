defmodule Press.CSS.Selector do
  @moduledoc false

  @doc """
  Parses a selector string into a list of compound selectors.
  Returns nil if the selector is invalid or should be skipped (e.g. interactive states).
  """
  def parse(text) do
    text = String.trim(text)

    if Regex.match?(~r/:(?:hover|focus|active|focus-within|focus-visible|visited|target)\b/, text) do
      nil
    else
      compounds =
        text
        |> String.split(~r/\s+/)
        |> Enum.map(&parse_compound/1)

      if Enum.all?(compounds, &(&1 != nil)) and compounds != [] do
        compounds
      else
        nil
      end
    end
  end

  defp parse_compound("*"), do: %{universal: true}

  defp parse_compound(text) do
    cleaned = Regex.replace(~r/::[a-zA-Z-]+/, text, "")

    case Regex.run(~r/^([A-Za-z][A-Za-z0-9_-]*)?((?:[.#][A-Za-z0-9_-]+)*)$/, cleaned) do
      [_, type, rest] when type != "" or rest != "" ->
        res =
          %{}
          |> maybe_put_type(type)
          |> apply_class_and_id(rest)

        if map_size(res) == 0, do: nil, else: res

      _ ->
        nil
    end
  end

  defp maybe_put_type(map, ""), do: map
  defp maybe_put_type(map, type), do: Map.put(map, :type, type)

  defp apply_class_and_id(map, rest) do
    ~r/([.#])([A-Za-z0-9_-]+)/
    |> Regex.scan(rest)
    |> Enum.reduce(map, fn
      [_, ".", name], acc -> Map.update(acc, :classes, [name], &(&1 ++ [name]))
      [_, "#", name], acc -> Map.put(acc, :id, name)
    end)
  end

  def specificity(compounds) do
    Enum.reduce(compounds, {0, 0, 0}, fn compound, {ids, classes, types} ->
      {
        ids + bool_to_int(Map.has_key?(compound, :id)),
        classes + length(Map.get(compound, :classes, [])),
        types + bool_to_int(Map.has_key?(compound, :type))
      }
    end)
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0

  def matches?(compounds, element, ancestors) do
    case Enum.reverse(compounds) do
      [last | rest] -> compound_matches?(last, element) and match_ancestors(rest, ancestors)
      [] -> false
    end
  end

  defp match_ancestors([], _ancestors), do: true
  defp match_ancestors([_compound | _rest], []), do: false

  defp match_ancestors([compound | rest] = compounds, [ancestor | older]) do
    if compound_matches?(compound, ancestor) do
      match_ancestors(rest, older)
    else
      match_ancestors(compounds, older)
    end
  end

  defp compound_matches?(%{universal: true}, _element), do: true

  defp compound_matches?(compound, element) do
    type_matches?(compound, element) and id_matches?(compound, element) and
      class_matches?(compound, element)
  end

  defp type_matches?(%{type: type}, element), do: element.tag == type
  defp type_matches?(_compound, _element), do: true

  defp id_matches?(%{id: id}, element), do: Map.get(element.attrs, "id") == id
  defp id_matches?(_compound, _element), do: true

  defp class_matches?(%{classes: classes}, element) do
    element_classes =
      element.attrs
      |> Map.get("class", "")
      |> String.split()

    Enum.all?(classes, &(&1 in element_classes))
  end

  defp class_matches?(_compound, _element), do: true
end
