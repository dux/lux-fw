# frozen_string_literal: true

class Lux::Current::StaticFile
  MIMME_TYPES = {
    txt:  'text/plain',
    html: 'text/html',
    gif:  'image/gif',
    jpg:  'image/jpeg',
    jpeg: 'image/jpeg',
    png:  'image/png',
    ico:  'image/png', # image/x-icon
    css:  'text/css',
    map:  'application/json',
    js:   'application/javascript',
    gz:   'application/x-gzip',
    zip:  'application/x-gzip',
    svg:  'image/svg+xml',
    mp3:  'application/mp3',
    woff:  'application/x-font-woff',
    woff2: 'application/x-font-woff',
    ttf:   'application/font-ttf',
    eot:   'application/vnd.ms-fontobject',
    otf:   'application/font-otf',
    doc:   'application/msword'
  }

  class << self
    def deliver file
      new(file).deliver
    end
  end

  ###

  def initialize file
    @file = file
  end

  def c
    Lux.current
  end

  def is_static_file?
    return false unless @file.index('.')

    path = @file.split('/')
    path.pop

    file = path.shift
    ext = @file.split('.').last

    return false if ext.to_s.length == 0
    return false unless MIMME_TYPES[ext.to_sym]

    true
  end

  def resolve_content_type
    mimme = MIMME_TYPES[@ext.to_sym]

    unless mimme
      c.response.body('Mimme type not supported')
      c.response.status(406)
      return
    end

    c.response.content_type = mimme
  end

  def deliver data=nil
    file = File.exist?(@file) ? @file : Lux.root.join("public#{@file}").to_s

    raise Lux::Error.not_found('Static file not found') unless File.exists?(file)

    @ext = file.to_s.split('.').last

    resolve_content_type

    file_mtime = File.mtime(file).utc.to_s
    key        = Crypt.sha1(file+file_mtime.to_s)

    c.response.headers['cache-control'] = 'max-age=31536000, public'
    c.response.headers['etag']          = '"%s"' % key
    c.response.headers['last-modified'] = file_mtime

    # IF etags match, returnfrom cache
    if c.request.env['HTTP_IF_NONE_MATCH'] == key
      c.response.status(304)
      c.response.body('not-modified')
      return
    end

    c.response.body data || File.read(file)

    true
  end
end