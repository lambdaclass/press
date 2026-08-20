html_path = Path.join(__DIR__, "invoice.html")
logo_path = Path.join(__DIR__, "assets/novatech_logo.png")
pdf_path = Path.join(__DIR__, "invoice.pdf")

html = File.read!(html_path)
logo = File.read!(logo_path)

{:ok, pdf} = Press.render(html, images: %{"./assets/novatech_logo.png" => logo})
File.write!(pdf_path, pdf)

IO.puts("Generated: #{pdf_path}")
