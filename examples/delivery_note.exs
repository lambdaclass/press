html_path = Path.join(__DIR__, "delivery_note.html")
logo_path = Path.join(__DIR__, "assets/freshgoods_logo.png")
pdf_path = Path.join(__DIR__, "delivery_note.pdf")

html = File.read!(html_path)
logo = File.read!(logo_path)

{:ok, pdf} = Press.render(html, images: %{"./assets/freshgoods_logo.png" => logo})
File.write!(pdf_path, pdf)

IO.puts("Generated: #{pdf_path}")
