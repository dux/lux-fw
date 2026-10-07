require 'fileutils'
require 'tmpdir'

# public/favicon.svg is the one source, everything else is generated from it:
#   public/favicon.ico                  32px, committed, served at the root url
#   public/assets/apple-touch-icon.png  180px on white, shipped with the assets
module Favicon
  extend self

  SOURCE ||= 'public/favicon.svg'
  ICO    ||= 'public/favicon.ico'
  TOUCH  ||= 'apple-touch-icon.png'
  SEED   ||= File.expand_path('../favicon.svg', __dir__)

  # Dev only: seed a missing icon, rebuild outputs older than the svg. Rollup
  # empties public/assets on start, so this also restores the touch icon.
  def refresh!
    unless File.exist?(SOURCE)
      FileUtils.mkdir_p File.dirname(SOURCE)
      FileUtils.cp SEED, SOURCE
      Lux.shell.info "favicon: seeded #{SOURCE} with the Lux icon - replace it with your own"
    end

    build! if stale?
  end

  def build!
    raise "favicon: #{SOURCE} missing" unless File.exist?(SOURCE)

    Dir.mktmpdir do |dir|
      png = File.join(dir, 'favicon.png')
      rsvg '-w', 32, '-h', 32, SOURCE, '-o', png
      File.binwrite ICO, ico(File.binread(png))
    end

    FileUtils.mkdir_p File.dirname(touch_path)
    # iOS paints transparent pixels black
    rsvg '-w', 180, '-h', 180, '-b', 'white', SOURCE, '-o', touch_path
  end

  def stale?
    svg = File.mtime(SOURCE)
    [ICO, touch_path].any? { !File.exist?(_1) || File.mtime(_1) < svg }
  end

  # <head> links. Root files have no fingerprinted name, so ?v= (svg content
  # hash) busts browser favicon caches; the touch icon goes through CdnAsset.
  def tags
    return [] unless File.exist?(SOURCE)

    v = version
    touch = CdnAsset.path(TOUCH)

    [
      %[<link rel="icon" href="/favicon.ico?v=#{v}" sizes="32x32" />],
      %[<link rel="icon" href="/favicon.svg?v=#{v}" type="image/svg+xml" />],
      (%[<link rel="apple-touch-icon" href="#{touch}" />] if touch),
    ].compact
  end

  private

  def touch_path
    "public/assets/#{TOUCH}"
  end

  # re-hashed only when the svg changes
  def version
    mtime = File.mtime(SOURCE)
    @version = nil unless @mtime == mtime
    @mtime = mtime
    @version ||= File.read(SOURCE).sha1[0, 8]
  end

  # single-image ICO that embeds the PNG as is (read by every browser since IE Vista)
  def ico png
    [0, 1, 1].pack('v3') + [32, 32, 0, 0, 1, 32, png.bytesize, 22].pack('C4 v2 V2') + png
  end

  def rsvg *args
    Lux.shell.exec('rsvg-convert', *args) do |err, _out|
      raise "favicon: rsvg-convert failed (brew install librsvg): #{err}"
    end
  end
end
