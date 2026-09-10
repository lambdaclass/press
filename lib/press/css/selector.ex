defmodule Press.CSS.Selector do
  @moduledoc false

  @interactive ~r/:(?:hover|focus|active|focus-within|focus-visible|visited|target)\b/

  @structural ~r/:(root|first-child|last-child|only-child|first-of-type|last-of-type|only-of-type|nth-child\(([^)]*)\)|nth-of-type\(([^)]*)\))/

  @doc """
  Parses a selector into a list of compounds, outermost first. Every compound
  past the first carries the combinator relating it to the one before it
  (`:descendant`, `:child`, `:next_sibling`, `:subsequent_sibling`).

  Returns nil when the selector cannot be represented — an unparseable
  fragment drops the whole rule rather than weakening it into one that
  matches everything.
  """
  def parse(text) do
    text = String.trim(text)

    unless Regex.match?(@interactive, text) do
      case tokenize(text) do
        [] -> nil
        tokens -> build_compounds(tokens)
      end
    end
  end

  defp tokenize(text) do
    text
    |> String.replace(~r/\s*([>+~])\s*/, " \\1 ")
    |> String.split(~r/\s+/, trim: true)
  end

  defp build_compounds(tokens), do: build_compounds(tokens, :descendant, [])

  defp build_compounds([], _combinator, acc), do: Enum.reverse(acc)

  defp build_compounds([token | rest], _combinator, acc) when token in [">", "+", "~"] do
    build_compounds(rest, combinator_for(token), acc)
  end

  defp build_compounds([token | rest], combinator, acc) do
    case parse_compound(token) do
      nil ->
        nil

      compound ->
        # Descendant is the default relation, so it is left implicit and only a
        # real combinator is recorded.
        compound =
          if acc == [] or combinator == :descendant,
            do: compound,
            else: Map.put(compound, :combinator, combinator)

        build_compounds(rest, :descendant, [compound | acc])
    end
  end

  defp combinator_for(">"), do: :child
  defp combinator_for("+"), do: :next_sibling
  defp combinator_for("~"), do: :subsequent_sibling

  defp parse_compound("*"), do: %{universal: true}

  defp parse_compound(text) do
    {pseudos, cleaned} = extract_pseudos(text)
    cleaned = Regex.replace(~r/::[a-zA-Z-]+/, cleaned, "")

    case Regex.run(~r/^([A-Za-z][A-Za-z0-9_-]*)?((?:[.#][A-Za-z0-9_-]+)*)$/, cleaned) do
      [_, type, rest] when type != "" or rest != "" ->
        %{}
        |> maybe_put_type(type)
        |> apply_class_and_id(rest)
        |> maybe_put_pseudos(pseudos)

      _ ->
        if cleaned == "" and pseudos != [], do: %{pseudos: pseudos}
    end
  end

  defp extract_pseudos(text) do
    # A trailing capture group that did not take part is left out of the scan
    # result, so the functional forms are recognised by their own name rather
    # than by how many groups came back.
    pseudos =
      Regex.scan(@structural, text)
      |> Enum.map(fn [_whole, name | args] ->
        case name do
          "nth-child(" <> _ -> {:nth_child, parse_nth(Enum.at(args, 0, ""))}
          "nth-of-type(" <> _ -> {:nth_of_type, parse_nth(Enum.at(args, 1, Enum.at(args, 0, "")))}
          plain -> String.to_atom(String.replace(plain, "-", "_"))
        end
      end)

    {pseudos, Regex.replace(@structural, text, "")}
  end

  defp parse_nth(arg) do
    case String.trim(arg) |> String.downcase() do
      "even" ->
        {2, 0}

      "odd" ->
        {2, 1}

      other ->
        case Regex.run(~r/^([+-]?\d*)n\s*([+-]\s*\d+)?$/, other) do
          [_, a] -> {nth_coefficient(a), 0}
          [_, a, b] -> {nth_coefficient(a), b |> String.replace(" ", "") |> String.to_integer()}
          nil -> {0, String.to_integer(other)}
        end
    end
  rescue
    _ -> {0, -1}
  end

  defp nth_coefficient(""), do: 1
  defp nth_coefficient("+"), do: 1
  defp nth_coefficient("-"), do: -1
  defp nth_coefficient(a), do: String.to_integer(a)

  defp maybe_put_type(map, ""), do: map
  defp maybe_put_type(map, type), do: Map.put(map, :type, type)

  defp maybe_put_pseudos(map, []), do: map
  defp maybe_put_pseudos(map, pseudos), do: Map.put(map, :pseudos, pseudos)

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
        classes + length(Map.get(compound, :classes, [])) +
          length(Map.get(compound, :pseudos, [])),
        types + bool_to_int(Map.has_key?(compound, :type))
      }
    end)
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0

  @doc """
  Matches a parsed selector against a path of element contexts, nearest first:
  `[self, parent, grandparent, ...]`. Each context is
  `%{element: element, index: zero_based_index, siblings: [element]}`.
  """
  def matches?(compounds, [self_ctx | ancestors]) do
    case Enum.reverse(compounds) do
      [last | rest] ->
        compound_matches?(last, self_ctx) and match_rest(rest, last, self_ctx, ancestors)

      [] ->
        false
    end
  end

  def matches?(_compounds, []), do: false

  # Back-compatible entry point: no sibling context, so structural
  # pseudo-classes on such a call can only be evaluated for the element itself.
  def matches?(compounds, element, ancestors) do
    matches?(compounds, [ctx(element) | Enum.map(ancestors, &ctx/1)])
  end

  defp ctx(element), do: %{element: element, index: 0, siblings: [element]}

  defp match_rest([], _subject_compound, _subject_ctx, _ancestors), do: true

  defp match_rest([compound | rest], subject_compound, subject_ctx, ancestors) do
    case Map.get(subject_compound, :combinator, :descendant) do
      :descendant ->
        match_descendant([compound | rest], ancestors)

      :child ->
        case ancestors do
          [parent | older] ->
            compound_matches?(compound, parent) and match_rest(rest, compound, parent, older)

          [] ->
            false
        end

      :next_sibling ->
        case previous_sibling(subject_ctx) do
          nil ->
            false

          prev ->
            compound_matches?(compound, prev) and match_rest(rest, compound, prev, ancestors)
        end

      :subsequent_sibling ->
        subject_ctx
        |> previous_siblings()
        |> Enum.any?(fn prev ->
          compound_matches?(compound, prev) and match_rest(rest, compound, prev, ancestors)
        end)
    end
  end

  defp match_descendant(_compounds, []), do: false

  defp match_descendant([compound | rest] = compounds, [ancestor | older]) do
    if compound_matches?(compound, ancestor) and match_rest(rest, compound, ancestor, older) do
      true
    else
      match_descendant(compounds, older)
    end
  end

  defp previous_sibling(%{index: 0}), do: nil

  defp previous_sibling(%{index: i, siblings: siblings}) do
    %{element: Enum.at(siblings, i - 1), index: i - 1, siblings: siblings}
  end

  defp previous_siblings(%{index: i, siblings: siblings}) do
    Enum.map((i - 1)..0//-1, fn j ->
      %{element: Enum.at(siblings, j), index: j, siblings: siblings}
    end)
  end

  defp previous_siblings(_), do: []

  defp compound_matches?(%{universal: true} = compound, ctx) do
    pseudos_match?(compound, ctx)
  end

  defp compound_matches?(compound, %{element: element} = ctx) do
    type_matches?(compound, element) and id_matches?(compound, element) and
      class_matches?(compound, element) and pseudos_match?(compound, ctx)
  end

  defp type_matches?(%{type: type}, element), do: element.tag == type
  defp type_matches?(_compound, _element), do: true

  defp id_matches?(%{id: id}, element), do: Map.get(element.attrs, "id") == id
  defp id_matches?(_compound, _element), do: true

  defp class_matches?(%{classes: classes}, element) do
    element_classes = element.attrs |> Map.get("class", "") |> String.split()
    Enum.all?(classes, &(&1 in element_classes))
  end

  defp class_matches?(_compound, _element), do: true

  defp pseudos_match?(%{pseudos: pseudos}, ctx) do
    Enum.all?(pseudos, &pseudo_matches?(&1, ctx))
  end

  defp pseudos_match?(_compound, _ctx), do: true

  defp pseudo_matches?(:root, %{element: element}), do: element.tag == "html"

  defp pseudo_matches?(:first_child, %{index: i}), do: i == 0

  defp pseudo_matches?(:last_child, %{index: i, siblings: siblings}),
    do: i == length(siblings) - 1

  defp pseudo_matches?(:only_child, %{siblings: siblings}), do: length(siblings) == 1

  defp pseudo_matches?({:nth_child, {a, b}}, %{index: i}), do: nth?(i + 1, a, b)

  defp pseudo_matches?(:first_of_type, ctx), do: type_position(ctx) == 1

  defp pseudo_matches?(:last_of_type, ctx), do: type_position(ctx) == type_count(ctx)

  defp pseudo_matches?(:only_of_type, ctx), do: type_count(ctx) == 1

  defp pseudo_matches?({:nth_of_type, {a, b}}, ctx), do: nth?(type_position(ctx), a, b)

  defp pseudo_matches?(_pseudo, _ctx), do: false

  defp type_position(%{element: element, index: i, siblings: siblings}) do
    siblings
    |> Enum.take(i + 1)
    |> Enum.count(&(&1.tag == element.tag))
  end

  defp type_count(%{element: element, siblings: siblings}) do
    Enum.count(siblings, &(&1.tag == element.tag))
  end

  defp nth?(position, 0, b), do: position == b

  defp nth?(position, a, b) do
    diff = position - b
    rem(diff, a) == 0 and div(diff, a) >= 0
  end
end
