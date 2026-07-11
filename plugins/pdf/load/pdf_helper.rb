# View helper for PDF pages (app/views/pdf/, rendered by PdfController).
#
# Ships a self-contained `format_money` so the bundled demo renders in any app
# with no dependencies. Apps that have their own money formatter reopen this
# module in app/helpers/pdf_helper.rb and override `format_money`.
module PdfHelper
  # Format integer cents as a European money string:
  #   1_234_56 -> "1.234,56 EUR"   (dot thousands, comma decimals)
  def format_money(cents, currency = 'EUR')
    return "0,00 #{currency}" unless cents && cents != 0

    negative = cents < 0
    whole, decimal = ('%.2f' % (cents.abs / 100.0)).split('.')
    whole = whole.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1.')
    "#{negative ? '-' : ''}#{whole},#{decimal} #{currency}"
  end
end
