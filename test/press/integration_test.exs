defmodule Press.IntegrationTest do
  use ExUnit.Case, async: true

  test "renders a full business invoice HTML+CSS document into a valid PDF binary" do
    html = """
    <!DOCTYPE html>
    <html>
      <head>
        <style>
          @page {
            size: A4;
            margin: 15mm 20mm;
          }
          body {
            font-family: helvetica;
            font-size: 10pt;
            color: #333333;
          }
          header {
            margin-bottom: 20pt;
            border-bottom: 2pt solid #4f46e5;
            padding-bottom: 10pt;
          }
          h1 {
            color: #4f46e5;
            font-size: 22pt;
            margin: 0;
          }
          .company-info {
            text-align: right;
            font-size: 9pt;
            color: #666666;
          }
          .bill-to {
            margin-top: 15pt;
            margin-bottom: 20pt;
          }
          .bill-to h2 {
            font-size: 12pt;
            color: #111827;
            margin-bottom: 5pt;
          }
          table {
            width: 100%;
            margin-top: 10pt;
            margin-bottom: 20pt;
          }
          th {
            background-color: #f3f4f6;
            color: #374151;
            font-weight: bold;
            padding: 8pt;
            text-align: left;
            border-bottom: 1pt solid #e5e7eb;
          }
          td {
            padding: 8pt;
            border-bottom: 1pt solid #f3f4f6;
          }
          .amount {
            text-align: right;
          }
          .total-row td {
            font-weight: bold;
            font-size: 12pt;
            color: #4f46e5;
            border-top: 2pt solid #4f46e5;
          }
          footer {
            margin-top: 30pt;
            text-align: center;
            font-size: 8pt;
            color: #9ca3af;
            border-top: 1pt solid #e5e7eb;
            padding-top: 10pt;
          }
        </style>
      </head>
      <body>
        <header>
          <h1>INVOICE</h1>
          <p class="company-info">Altenwald Solutions S.L. &bull; CIF: B12345678</p>
        </header>

        <main>
          <div class="bill-to">
            <h2>Billed To:</h2>
            <p><strong>Acme Corporation</strong><br>123 Innovation Way<br>Tech City, TC 90210</p>
          </div>

          <table>
            <thead>
              <tr>
                <th style="width: 50%">Description</th>
                <th style="width: 15%" class="amount">Qty</th>
                <th style="width: 15%" class="amount">Rate</th>
                <th style="width: 20%" class="amount">Total</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>Software Architecture Consulting</td>
                <td class="amount">40</td>
                <td class="amount">&euro;120.00</td>
                <td class="amount">&euro;4,800.00</td>
              </tr>
              <tr>
                <td>Elixir OTP Backend Implementation</td>
                <td class="amount">60</td>
                <td class="amount">&euro;100.00</td>
                <td class="amount">&euro;6,000.00</td>
              </tr>
              <tr>
                <td>Automated Testing & CI Pipeline</td>
                <td class="amount">20</td>
                <td class="amount">&euro;90.00</td>
                <td class="amount">&euro;1,800.00</td>
              </tr>
              <tr class="total-row">
                <td colspan="3">Grand Total</td>
                <td class="amount">&euro;12,600.00</td>
              </tr>
            </tbody>
          </table>
        </main>

        <footer>
          <p>Payment is due within 30 days. Thank you for your business!</p>
        </footer>
      </body>
    </html>
    """

    assert {:ok, pdf_bytes} = Press.render(html)

    # Valid PDF syntax
    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
    assert String.ends_with?(pdf_bytes, "%%EOF")
    assert pdf_bytes =~ "/Type /Catalog"
    assert pdf_bytes =~ "/Type /Pages"
    assert pdf_bytes =~ "/Type /Page"
    assert pdf_bytes =~ "/Type /Font"
    assert pdf_bytes =~ "xref"
    assert pdf_bytes =~ "trailer"

    # Dimensions: A4 page MediaBox
    assert pdf_bytes =~ "/MediaBox [0 0 595.28 841.89]"

    # Key text rendered in stream
    assert pdf_bytes =~ "(INVOICE) Tj"
    assert pdf_bytes =~ "(Acme) Tj"
    assert pdf_bytes =~ "(Corporation) Tj"
    assert pdf_bytes =~ "(Software) Tj"
    assert pdf_bytes =~ "(Grand) Tj"
    assert pdf_bytes =~ "(Total) Tj"
  end
end
