defmodule Press.Font.Program do
  @moduledoc false

  @typedoc """
  A font file prepared for embedding: the program bytes to write into the PDF,
  which entry of the font descriptor they go under, and the metrics the
  descriptor has to declare.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          data: binary(),
          file_key: String.t(),
          subtype: String.t() | nil,
          bbox: {integer(), integer(), integer(), integer()},
          italic_angle: number(),
          ascent: integer(),
          descent: integer(),
          cap_height: integer(),
          stem_v: integer(),
          flags: integer()
        }

  defstruct [
    :name,
    :data,
    :file_key,
    :subtype,
    :bbox,
    :italic_angle,
    :ascent,
    :descent,
    :cap_height,
    :stem_v,
    :flags
  ]

  @doc """
  Reads a TrueType or OpenType file and prepares it for embedding.

  An OpenType font carries its outlines in a `CFF ` table; that table is
  extracted and embedded on its own as `/FontFile3 /Type1C`, which every reader
  since PDF 1.2 understands and which drops the layout tables (`GSUB`, `GPOS`,
  `cmap`) that a PDF never consults. A TrueType font is embedded whole as
  `/FontFile2`.

  No subsetting: the whole outline set goes in. That keeps this a few dozen
  lines instead of a glyph-renumbering exercise, at the cost of carrying glyphs
  the document never uses — which is a fair trade for a compact font and a
  terrible one for a large Unicode font.
  """
  @spec load(binary() | Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path_or_binary) do
    with {:ok, data} <- read(path_or_binary),
         {:ok, tables} <- table_directory(data) do
      {:ok, build(data, tables)}
    end
  end

  defp read(<<"OTTO", _::binary>> = data), do: {:ok, data}
  defp read(<<0, 1, 0, 0, _::binary>> = data), do: {:ok, data}
  defp read(<<"true", _::binary>> = data), do: {:ok, data}

  defp read(path) when is_binary(path) do
    case File.read(path) do
      {:ok, data} -> read(data)
      {:error, reason} -> {:error, {:unreadable_font, path, reason}}
    end
  end

  defp read(other), do: {:error, {:unsupported_font, other}}

  defp table_directory(<<_tag::binary-size(4), count::16, _::binary-size(6), rest::binary>>) do
    tables =
      for i <- 0..max(0, count - 1),
          entry = binary_part(rest, i * 16, 16),
          <<tag::binary-size(4), _checksum::32, offset::32, length::32>> = entry,
          into: %{} do
        {tag, {offset, length}}
      end

    {:ok, tables}
  rescue
    _ -> {:error, :malformed_font}
  end

  defp table_directory(_), do: {:error, :malformed_font}

  defp build(data, tables) do
    upem = read_u16(data, tables, "head", 18) || 1000
    scale = fn value -> round(value * 1000 / upem) end

    {file_key, subtype, program} =
      case Map.fetch(tables, "CFF ") do
        {:ok, {offset, length}} ->
          {"FontFile3", "Type1C", binary_part(data, offset, length)}

        :error ->
          {"FontFile2", nil, data}
      end

    ascent = read_s16(data, tables, "hhea", 4) || 800
    descent = read_s16(data, tables, "hhea", 6) || -200
    weight = read_u16(data, tables, "OS/2", 4) || 400
    # panose[1] is bSerifStyle; 2..10 are the serif classes.
    serif? = (read_u8(data, tables, "OS/2", 33) || 0) in 2..10

    %__MODULE__{
      name: postscript_name(data, tables),
      data: program,
      file_key: file_key,
      subtype: subtype,
      bbox: {
        scale.(read_s16(data, tables, "head", 36) || 0),
        scale.(read_s16(data, tables, "head", 38) || -200),
        scale.(read_s16(data, tables, "head", 40) || 1000),
        scale.(read_s16(data, tables, "head", 42) || 900)
      },
      italic_angle: italic_angle(data, tables),
      ascent: scale.(ascent),
      descent: scale.(descent),
      cap_height: cap_height(data, tables, scale, ascent),
      stem_v: stem_v(weight),
      flags: if(serif?, do: 34, else: 32)
    }
  end

  # Bit 6 (32) marks a font that uses a standard Latin text encoding; bit 2 (2)
  # adds "has serifs". A reader only leans on these when it has to substitute,
  # which an embedded font never asks it to do.
  defp cap_height(data, tables, scale, ascent) do
    case read_u16(data, tables, "OS/2", 0) do
      version when is_integer(version) and version >= 2 ->
        scale.(read_s16(data, tables, "OS/2", 88) || ascent)

      _ ->
        scale.(ascent)
    end
  end

  # There is no stem width in the tables; it is estimated from the weight, and
  # only matters for synthetic substitution, which embedding rules out.
  defp stem_v(weight) when weight >= 700, do: 165
  defp stem_v(weight) when weight >= 600, do: 140
  defp stem_v(_weight), do: 80

  defp italic_angle(data, tables) do
    case read_s32(data, tables, "post", 4) do
      nil -> 0
      fixed -> Float.round(fixed / 65_536, 1)
    end
  end

  defp postscript_name(data, tables) do
    with {:ok, {offset, _length}} <- Map.fetch(tables, "name"),
         <<_format::16, count::16, storage::16>> <- binary_part(data, offset, 6) do
      Enum.find_value(0..max(0, count - 1), "EmbeddedFont", fn i ->
        <<platform::16, _encoding::16, _language::16, name_id::16, length::16, name_offset::16>> =
          binary_part(data, offset + 6 + i * 12, 12)

        if name_id == 6 do
          raw = binary_part(data, offset + storage + name_offset, length)
          decode_name(raw, platform) |> sanitise()
        end
      end)
    else
      _ -> "EmbeddedFont"
    end
  rescue
    _ -> "EmbeddedFont"
  end

  defp decode_name(raw, 3), do: :unicode.characters_to_binary(raw, {:utf16, :big})
  defp decode_name(raw, _platform), do: raw

  # A PostScript name has to survive being written as a PDF name token.
  defp sanitise(name) when is_binary(name), do: String.replace(name, ~r/[^\w.-]/, "")
  defp sanitise(_), do: "EmbeddedFont"

  defp read_u8(data, tables, table, offset), do: read_int(data, tables, table, offset, 1, false)
  defp read_u16(data, tables, table, offset), do: read_int(data, tables, table, offset, 2, false)
  defp read_s16(data, tables, table, offset), do: read_int(data, tables, table, offset, 2, true)
  defp read_s32(data, tables, table, offset), do: read_int(data, tables, table, offset, 4, true)

  defp read_int(data, tables, table, offset, size, signed?) do
    with {:ok, {table_offset, length}} <- Map.fetch(tables, table),
         true <- offset + size <= length do
      case binary_part(data, table_offset + offset, size) do
        <<value::signed-integer-size(size)-unit(8)>> when signed? -> value
        <<value::unsigned-integer-size(size)-unit(8)>> -> value
      end
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
