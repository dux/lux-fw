# Generates PDFs by loading real web pages via Puppeteer.
#
# PdfGenerator.generate_pdf(url) -> PDF binary
#
module PdfGenerator
  extend self

  PUPPETEER_SCRIPT ||= File.join('tmp', 'pdf_render.mjs')
  SCRIPT_LOCK      ||= Mutex.new

  class RenderError < RuntimeError; end

  # Load a URL via Puppeteer and return PDF binary
  def generate_pdf(url)
    ensure_puppeteer_script

    pdf_path = File.join('tmp', "pdf_#{SecureRandom.hex(8)}.pdf")

    # exec returns stripped stdout on success; the block runs on failure
    # (non-zero exit / ENOENT) with (stderr, stdout) so we surface the real error.
    Lux.shell.exec('bun', PUPPETEER_SCRIPT, url, pdf_path) do |err, out|
      raise RenderError, "Puppeteer PDF failed for #{url}: #{out}#{err}"
    end

    unless File.exist?(pdf_path)
      raise RenderError, "Puppeteer PDF produced no file for #{url}"
    end

    File.binread(pdf_path)
  ensure
    File.delete(pdf_path) if pdf_path && File.exist?(pdf_path)
  end

  private

  # Written once per process, so an updated script replaces a stale tmp copy
  # on boot. The rename is atomic, so a render in another worker never runs a
  # half-written file.
  def ensure_puppeteer_script
    SCRIPT_LOCK.synchronize do
      return if @script_written

      FileUtils.mkdir_p(File.dirname(PUPPETEER_SCRIPT))
      tmp = "#{PUPPETEER_SCRIPT}.#{Process.pid}"
      File.write(tmp, puppeteer_script)
      File.rename(tmp, PUPPETEER_SCRIPT)
      @script_written = true
    end
  end

  def puppeteer_script
    <<~JS
      import puppeteer from 'puppeteer';

      const [url, pdfPath] = process.argv.slice(2);

      // Use the system Google Chrome (not Puppeteer's bundled Chromium): its text
      // layout matches the user's browser, so the PDF paginates identically to the
      // on-screen Paged.js preview. Requires Chrome installed (channel: 'chrome').
      const browser = await puppeteer.launch({ channel: 'chrome', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'] });
      const page = await browser.newPage();
      await page.goto(url, { waitUntil: 'networkidle0', timeout: 60000 });

      // Paged.js (loaded by layouts/pdf.haml) paginates into A4 boxes and sets
      // window.pagedReady when done. Wait for it + fonts, then print 1:1 - the
      // PDF is exactly the paginated page the user sees on screen.
      await page.waitForFunction('window.pagedReady === true', { timeout: 60000 });
      await page.evaluate(() => document.fonts.ready);
      // Drop the on-screen download toolbar so it never appears in the PDF.
      await page.evaluate(() => document.querySelector('#pdf-dl')?.remove());
      await page.pdf({
        path: pdfPath,
        printBackground: true,
        preferCSSPageSize: true,                                   // honour @page { size: A4 }
        margin: { top: '0', bottom: '0', left: '0', right: '0' },  // Paged.js already drew margins
      });
      await browser.close();
    JS
  end
end
