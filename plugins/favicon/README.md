# Lux.plugin :favicon

App icon from a single SVG.
`public/favicon.svg` is the source, everything else is generated from it, and the `<head>` builder (`lux.render_html`, or `lux.header.render`) writes the links on its own.

```yaml
# config/config.yaml
default:
  plugins:
    - web_common
    - favicon
```

```haml
= lux.render_html do |el|
  = el.icon false          # only to leave the icon links out (popups, embeds)
```

With `lux.header.render` the switch is `lux.header.icon false`.

## Files

| File | Git | Made by |
|------|-----|---------|
| `public/favicon.svg` | committed | you; dev seeds the Lux icon when it is missing |
| `public/favicon.ico` | committed | generated, 32px PNG inside an ICO, served at the root url old clients ask for |
| `public/assets/apple-touch-icon.png` | ignored | generated, 180px on white (iOS paints transparency black), shipped with the assets |

```html
<link rel="icon" href="/favicon.ico?v=ab12cd34" sizes="32x32" />
<link rel="icon" href="/favicon.svg?v=ab12cd34" type="image/svg+xml" />
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png?..." />
```

* `?v=` is the SVG content hash.
  Browsers cache favicons hard, and the root files have no fingerprinted name.
* The touch icon url comes from `CdnAsset.path`, so it is fingerprinted and on the CDN when `cdn_root` is set.
* The files are plain static files.
  `serve_static_files` (or nginx `root public`) serves them, there is no route.

## Building

* Dev: every rendered `<head>` rebuilds both outputs when they are missing or older than the SVG.
  Rollup empties `public/assets` on start, the next page load puts the touch icon back.
* `lux assets:build` builds them after rollup and before the manifest, so `assets:deploy` uploads the touch icon.
* `lux favicon` rebuilds on demand.

Rendering needs `rsvg-convert` (`brew install librsvg`) on the machine that builds the assets.
Production only serves the files.
