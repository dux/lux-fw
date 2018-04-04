# base class for production rendering
# MiniAssets.call('js/main/index.coffee').render
# MiniAssets::Base::JavasScript.new sorurce, files

class MiniAssets::Base
  attr_reader   :files

  def initialize source, files
    @source = source
    @files  = files
  end

  def join_string
    "\n"
  end

  def render_production
    nil
  end

  def gzip
    run! 'gzip -k %s' % @target
  end

  def run! what
    puts what.yellow
    system what
  end

  def opts
    MiniAssets::Opts
  end

  # this should only be called in builder for production "lux assets"
  def render
    data = []

    @files.each do |file|
      asset = asset_class.new file
      data.push asset.comment 'Source: %s' % file unless opts.production?
      data.push asset.render
    end

    data = data.join(join_string)
    type = asset_class.to_s.split('::').last.downcase

    @target = opts.public_root.join '%s-%s.%s' % [@source.to_s.gsub(/[^\w]+/,'-'), Digest::SHA1.hexdigest(data), type]

    # unless target exists, build it and minify it
    unless @target.exist?
      @target.write data

      render_production
      gzip

      # force old time stamp
      run! 'touch -t 201001010101 %s' % @target
      run! 'touch -t 201001010101 %s.gz' % @target
    end

    # update manifest (if needed)
    target   = @target.to_s.split('/public').last
    manifest = MiniAssets::Manifest.new
    manifest.add @source, target

    target
  end
end

