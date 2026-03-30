module CdnAsset
  extend self

  def get_time_stamp
    `date -r "$(ls -t $(find ./app/assets -type f) 2>/dev/null | head -1)" +%s`.chomp.to_i
  end

  TIME_STAMP ||= get_time_stamp

  # public asset from manifest
  #   = Cdn.url 'domain.css'
  # remote url
  #   = Cdn.url 'https://cdnjs.cloudflare.com/ajax/libs/marked/2.1.3/marked.min.js'
  # force css link type
  #   = Cdn.url 'https://cdn.com/fooliib', as: :css
  # dynamicly generated from controller
  #   = Cdn.url '/assets.js', dynamic: true
  def url name, opts = {}
    if name.include?('//') || name.start_with?('/') || opts.delete(:dynamic)
      nil
    else
      if root = Lux.secrets[:cdn_root]
        hash = manifest[name] || return
        file = hashed_name(name, hash)
        name = '%s/assets/%s' % [root, file]
      else
        return unless File.exist?("./public/assets/#{name}")
        tim_stamp = Lux.env.reload? ? get_time_stamp : TIME_STAMP
        name = '/assets/%s?%s' % [name, tim_stamp]
      end
    end

    asset_tag name, opts
  end

  def upload
    cdn_url = Lux.config.production.cdn_root
    data = manifest
    failed = []

    Thread::Simple.each(Dir.files('./public/assets')) do |file|
      data[file] = Digest::MD5.hexdigest(File.read("./public/assets/#{file}"))[0, 8]
      target = hashed_name(file, data[file])
      local_path = "./public/assets/#{file}"
      remote_key = "assets/#{target}"

      ok = ::Cdn.cdn_upload(local_path, remote_key, production: true)
      unless ok
        # retry once
        sleep 1
        ok = ::Cdn.cdn_upload(local_path, remote_key, production: true)
      end

      if ok
        puts "* #{file} -> #{cdn_url}/#{remote_key}"
      else
        failed.push file
        puts "* FAIL #{file} -> #{cdn_url}/#{remote_key}"
      end
    end

    if failed.any?
      abort "CDN upload failed for: #{failed.join(', ')}"
    end

    File.write('./public/manifest.json', data.to_jsonp)
    nil
  end

  # = CdnAsset.auto :shared, :fez, :app
  def auto *list
    list.inject([]) do |t, el|
      t.push url("auto-#{el}.js")
      t.push url("auto-#{el}.css")
      t
    end.compact.join("\n")
  end

  private

  # read manifest from disk, cache once per process
  def manifest
    @manifest ||= begin
      JSON.parse(File.read('./public/manifest.json'))
    rescue
      {}
    end
  end

  # domain.css + a1b2c3d4 -> domain.a1b2c3d4.css
  def hashed_name name, hash
    ext = File.extname(name)
    base = name.chomp(ext)
    '%s.%s%s' % [base, hash, ext]
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
