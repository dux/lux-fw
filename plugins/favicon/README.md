# favicon plugin

Serves a single SVG favicon and silences browser polling for the legacy
`.ico` and `apple-touch-icon` variants.

## Setup

1. Drop the SVG at `public/favicon.svg`. The Lux static-file handler
   serves it with the right MIME type automatically.
2. Load and mount the plugin:

   ```ruby
   # somewhere in your boot (e.g. config/application.rb)
   Lux.plugin :favicon

   # in your app's routes.rb
   Lux.app do
     routes do
       plugin_route :favicon
       # ... other routes
     end
   end
   ```

3. Emit the `<link>` tags in your layout `<head>`:

   ```haml
   %head
     != Lux::Favicon.head
   ```

   Or with a custom path:

   ```haml
   != Lux::Favicon.head '/static/brand.svg'
   ```

## What it does

* `Lux::Favicon.head` returns:

  ```html
  <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
  <link rel="apple-touch-icon" href="/favicon.svg" />
  ```

* Routes return `204 No Content` for:
  * `/favicon.ico` (and other extensions under `/favicon.*`)
  * `/apple-touch-icon*` (including size suffixes and `-precomposed`)

  This stops browsers and crawlers from re-requesting these paths.

## Browser support

* Chrome, Firefox, Edge, Safari 14+ - render the SVG directly.
* iOS Safari 16.4+ - uses the SVG for apple-touch-icon.
* Older iOS - silently no apple icon. Ship a separate PNG at
  `public/apple-touch-icon.png` if you need legacy support; the static
  handler will serve it and the plugin's 204 route only matches when
  no file exists.
