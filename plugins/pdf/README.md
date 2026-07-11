# pdf plugin

Printable pages + PDF download, served under a reserved `/pdf/` root (mirrors
`/admin/`). Pages are laid out with Paged.js into real A4 pages - the same engine
renders the on-screen preview and the downloadable PDF, so they are identical.

## What it ships

* `load/pdf_generator.rb` - `PdfGenerator.generate_pdf(url)`: drives system Chrome
  via Puppeteer (`bun`) and returns the PDF binary.
* `load/pdf_helper.rb` - `PdfHelper` with a self-contained `format_money`
  (European cents formatting) so the bundled demo renders in any app.
* `routes.rb` - the `/pdf/` dispatch (loads models in router scope, gates access
  in the controller). Wire it in the host with `plugin_route :pdf`.
* `mount/` (symlinked into the app by `lux mount`):
  * `app/controllers/pdf_controller.rb` - `PdfController < FrontendController`
  * `app/views/layouts/pdf.haml` - the Paged.js A4 layout
  * `app/views/pdf/demo.haml` - the only bundled page (a paginated example)

## Using it

```yaml
# config.yaml
plugins:
  - pdf
```

```ruby
# routes.rb
plugin_route :pdf
```

Then `lux mount`. Drop your own printable pages in `app/views/pdf/<name>.haml`
(they stay local to the app); visit `/pdf/<name>` for the preview and
`/pdf/<name>.pdf` for the download. To format money through your app's own
formatter, reopen `PdfHelper` in `app/helpers/pdf_helper.rb`.
