# Serves public/favicon.svg for legacy favicon polling:
#   /favicon.<ext>          - .ico, .png, ... (any extension)
#   /apple-touch-icon*      - including size suffixes and -precomposed
#
# /favicon.svg itself is served by the static-file handler, which runs
# before route resolution and never reaches here.

serve_favicon = proc {
  Lux::Response::File.send file: Lux.root.join('public/favicon.svg')
}

map 'favicon',             serve_favicon
map /\Aapple-touch-icon/,  serve_favicon
