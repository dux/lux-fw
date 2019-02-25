# frozen_string_literal: true

class Lux::Response::File
  MIMME_TYPES = {
    txt:   'text/plain',
    html:  'text/html',
    gif:   'image/gif',
    jpg:   'image/jpeg',
    jpeg:  'image/jpeg',
    png:   'image/png',
    ico:   'image/png', # image/x-icon
    css:   'text/css',
    map:   'application/json',
    js:    'application/javascript',
    gz:    'application/x-gzip',
    zip:   'application/x-gzip',
    svg:   'image/svg+xml',
    mp3:   'application/mp3',
    woff:  'application/x-font-woff',
    woff2: 'application/x-font-woff',
    ttf:   'application/font-ttf',
    eot:   'application/vnd.ms-fontobject',
    otf:   'application/font-otf',
    doc:   'application/msword'
  }

  ###
  # all parametars are optional
  # :name          - file name
  # :cache         - client cache in seconds
  # :content_type  - string type
  # :inline        - sets disposition to inline if true
  # :disposition   - inline or attachment
  # :content       - raw file data
  def initialize file, in_opts={}
    opts = in_opts.to_opts :name, :cache, :content_type, :inline, :disposition, :content
    opts.disposition ||= opts.inline.class == TrueClass ? 'inline' : 'attachment'
    opts.cache         = true if opts.cache.nil?

    file = file.to_s if file.class == Pathname
    file = 'public/%s' % file unless file[0, 1] == '/'

    @ext  = file.include?('.') ? file.split('.').last.to_sym : nil
    @file = file
    @opts = opts
  end

  define_method(:request)  { Lux.current.request }
  define_method(:response) { Lux.current.response }

  def is_static_file?
    return false unless @ext
    File.exist?(@file)
  end

  def send
    file = File.exist?(@file) ? @file : Lux.root.join('public', @file).to_s

    raise Lux::Error.not_found('Static file not found') unless File.exists?(file)

    response.content_type(@opts.content_type || MIMME_TYPES[@ext || '_'] || 'application/octet-stream')

    file_mtime = File.mtime(file).utc.to_s
    key        = Crypt.sha1(file + (@opts.content || file_mtime.to_s))

    if @opts.disposition == 'attachment'
      @opts.name ||= @file.split('/').last
      response.headers['content-disposition'] = 'attachment; filename=%s' % @opts.name
    end

    response.headers['cache-control'] = 'max-age=%d, public' % (@opts.cache ? 31536000 : 0)
    response.headers['etag']          = '"%s"' % key
    response.headers['last-modified'] = file_mtime

    # IF etags match, returnfrom cache
    if request.env['HTTP_IF_NONE_MATCH'] == key
      response.body('not-modified', 304)
    else
      response.body @opts.content || File.read(file)
    end
  end
end