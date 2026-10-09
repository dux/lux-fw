module CdnAsset
  extend self

  MANIFEST ||= './public/manifest.json'

  # public asset from manifest
  #   = Cdn.url 'domain.css'
  # remote url
  #   = Cdn.url 'https://cdnjs.cloudflare.com/ajax/libs/marked/2.1.3/marked.min.js'
  # force css link type
  #   = Cdn.url 'https://cdn.com/fooliib', as: :css
  # dynamicly generated from controller
  #   = Cdn.url '/assets.js', dynamic: true
  def url name, opts = {}
    # leave absolute / root-relative / dynamic names untouched; everything
    # else is rewritten to a fingerprinted CDN or local /assets path.
    unless name.include?('//') || name.start_with?('/') || opts.delete(:dynamic)
      name = path(name) || return
    end

    asset_tag name, opts
  end

  # url of a public/assets file: fingerprinted CDN path, or /assets/name?stamp.
  # nil when the asset is not built.
  def path name
    if root = Lux.secrets[:cdn_root]
      file = manifest[name] || return
      '%s/assets/%s' % [root, file]
    else
      return unless File.exist?("./public/assets/#{name}")
      stamp = Lux.reload? ? get_time_stamp : Lux::DEPLOY_ID
      '/assets/%s?%s' % [name, stamp]
    end
  end

  # force a <script> tag - use when the type can't be inferred from the
  # extension (extensionless / query-string urls)
  #   = Cdn.js 'https://cdn.com/foolib'
  def js name, opts = {}
    url name, opts.merge(as: :js)
  end
  alias_method :script, :js

  # force a <link rel="stylesheet">
  #   = Cdn.css 'https://cdn.com/foolib'
  def css name, opts = {}
    url name, opts.merge(as: :css)
  end

  # domain.css -> domain.a1b2c3d4.css, fingerprinted from the file's content.
  # Single source of truth for asset filenames, shared by url (reads it back
  # from the manifest) and write_manifest (bakes it into the manifest).
  def hashed_name name
    hash = File.read("./public/assets/#{name}").md5[0, 8]
    ext  = File.extname(name)
    '%s.%s%s' % [name.chomp(ext), hash, ext]
  end

  # public/assets -> public/manifest.json. It depends only on the built files,
  # so assets:build writes it and lux pack ships it.
  def write_manifest
    files = Dir.files('./public/assets').reject { _1.start_with?('.') } # .gitkeep
    data  = files.sort.to_h { [_1, hashed_name(_1)] }
    File.write(MANIFEST, data.to_jsonp)
  end

  # [local path, CDN path] per manifest entry - the assets:upload contract args.
  def uploads
    raise "#{MANIFEST} missing, run lux assets:build" unless File.exist?(MANIFEST)
    JSON.parse(File.read(MANIFEST)).map { |file, target| ["./public/assets/#{file}", "assets/#{target}"] }
  end

  private

  # newest asset mtime, for dev cache-busting in reload mode.
  # Include public/assets so a rebuild (e.g. after a gem dist update) invalidates
  # browser caches even when app/assets sources were not touched.
  def get_time_stamp
    (
      Lux.root.files('app/assets/**/*').map(&:to_s) + Dir['./public/assets/**/*']
    ).map { |f| File.mtime(f).to_i rescue 0 }.max || 0
  end

  # read manifest from disk, cache once per process. Maps source name to its
  # fingerprinted filename: { 'domain.css' => 'domain.a1b2c3d4.css' }
  def manifest
    @manifest ||= begin
      JSON.parse(File.read(MANIFEST))
    rescue
      {}
    end
  end

  def asset_tag name, opts={}
    # crossorigin not needed - CDN bucket has CORS configured
    as = opts.delete :as
    as ||= :js if name.include?('.js')
    as ||= :css if name.include?('css')

    case as
    when :js
      opts[:src] = name
      opts.tag(:script).sub('&lt;script', '<script')
    when :css
      opts[:href]    = name
      opts[:media] ||= 'all'
      opts[:rel]   ||= 'stylesheet'
      opts.tag :link
    else
      raise 'Not supported asset extension'
    end
  end
end
