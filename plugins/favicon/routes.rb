# /favicon.svg is served from public/favicon.svg by the static-file handler,
# which runs before route resolution - so it never reaches here. The routes
# below short-circuit browser polling for legacy .ico and apple-touch-icon
# variants by returning 204 No Content.

map 'favicon',             proc { [204, {}, ['']] }
map /\Aapple-touch-icon/,  proc { [204, {}, ['']] }
