examples_dir = __DIR__

for name <- ["invoice", "delivery_note", "payslip"] do
  html_path = Path.join(examples_dir, "#{name}.html")
  pdf_path = Path.join(examples_dir, "#{name}.pdf")

  IO.puts("Rendering #{name}.html → #{name}.pdf")

  html = File.read!(html_path)

  # Collect image references from the HTML
  images =
    Regex.scan(~r/src="([^"]+)"/, html)
    |> Enum.map(fn [_full, src] -> src end)
    |> Enum.reduce(%{}, fn src, acc ->
      abs_path = Path.join(examples_dir, src)

      case File.read(abs_path) do
        {:ok, data} -> Map.put(acc, src, data)
        {:error, _} -> acc
      end
    end)

  # Extract embedded <style> CSS
  css =
    case Regex.run(~r/<style>(.*?)<\/style>/s, html) do
      [_, css_content] -> css_content
      nil -> ""
    end

  {:ok, pdf} = Press.render(html, css: css, images: images)
  File.write!(pdf_path, pdf)
  IO.puts("  ✓ #{pdf_path}")
end

IO.puts("\nDone! All examples rendered successfully.")
