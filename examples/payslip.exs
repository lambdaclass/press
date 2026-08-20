html_path = Path.join(__DIR__, "payslip.html")
logo_path = Path.join(__DIR__, "assets/paycorp_logo.png")
pdf_path = Path.join(__DIR__, "payslip.pdf")

html = File.read!(html_path)
logo = File.read!(logo_path)

{:ok, pdf} = Press.render(html, images: %{"./assets/paycorp_logo.png" => logo})
File.write!(pdf_path, pdf)

IO.puts("Generated: #{pdf_path}")
