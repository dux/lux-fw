# Keeps an app's AGENTS.md pointing at the lux-fw docs it runs on. Plain Ruby:
# `lux new` calls it before any framework code is loaded.
module LuxAgentsMd
  START ||= '<!-- lux-fw:start -->'
  STOP  ||= '<!-- lux-fw:end -->'

  extend self

  # Creates AGENTS.md, or rewrites only the marked block in an existing one.
  # Returns :created, :updated or :unchanged.
  def write app_root, fw_root
    path  = File.join(app_root, 'AGENTS.md')
    old   = File.exist?(path) ? File.read(path) : nil
    block = block_for(app_root, fw_root)

    data =
      if old.nil?
        "# #{File.basename(app_root)}\n\n#{block}"
      elsif old.include?(START) && old.include?(STOP)
        old.sub(/#{Regexp.escape(START)}.*?#{Regexp.escape(STOP)}\n?/m) { block }
      else
        "#{old.chomp}\n\n#{block}"
      end

    return :unchanged if data == old

    File.write(path, data)
    old ? :updated : :created
  end

  def block_for app_root, fw_root
    fw = docs_path(app_root, fw_root)

    <<~MD
      #{START}
      ## Lux framework

      This app runs on Lux (lux-fw). Before writing code, read `#{fw}/AGENTS.md`.
      It lists the one canonical way to do each task and links a README per module:
      `#{fw}/lib/lux/<module>/README.md` and `#{fw}/plugins/<name>/README.md`.
      Specs follow `#{fw}/lib/lux/test/AGENTS.md`.

      Run `lux agents` after upgrading lux-fw to refresh these paths.
      #{STOP}
    MD
  end

  private

  # A linked checkout (.libs/lux-fw) keeps a stable relative path; an installed
  # gem gets its absolute, versioned path.
  def docs_path app_root, fw_root
    linked = File.join(app_root, '.libs/lux-fw')
    File.exist?(File.join(linked, 'AGENTS.md')) ? '.libs/lux-fw' : File.expand_path(fw_root)
  end
end
