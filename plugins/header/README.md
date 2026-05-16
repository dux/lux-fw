# header plugin

Per-request HTML `<head>` builder, exposed as `lux.header`.

Replaces the old `PageMeta` class plus the `@header = PageMeta.new(App.name)`
boilerplate in controllers.

## Setup

```ruby
# config/application.rb (or wherever you load plugins)
Lux.plugin :header
```

No `before` filter, no controller wiring. The instance is created lazily
on first call to `lux.header.X` and memoized in `current.var[:header_class]`
for the rest of the request.

## Usage

In a controller or action:

```ruby
lux.header.title       'My page'
lux.header.description 'short summary'
lux.header.image       '/og.png'
lux.header.canonical   'https://example.com/page'
lux.header.noindex
```

In the layout `<head>`:

```haml
%head
  = lux.header.render do |page|
    = asset 'main.css'
    = asset 'main.js'
```

The block runs last and its returned HTML is appended after the framework's
meta tags but before `<title>`.

## Site name

`render` falls back to `Lux.config.app.name` for the site name in `<title>`
and `og:site_name`. Override per-request with:

```ruby
lux.header.site_name 'Custom name'
```

## API

| Method | Effect |
|---|---|
| `title(s)` | sets `<title>` and `og:title` |
| `description(s)` | sets `description`, `og:description`, `twitter:description` |
| `image(url)` | sets `og:image`, `twitter:image`, `twitter:card=summary_large_image` |
| `url(s)` | sets `og:url` |
| `canonical(href)` | adds `<link rel=canonical>` + `og:url` |
| `type(kind)` | sets `og:type` (default `website`) |
| `locale(s)` | sets `og:locale` |
| `site_name(s)` | overrides the title suffix |
| `noindex` / `nofollow` | sets robots meta + `x-robots-tag` header |
| `meta(name, value)` | arbitrary meta tag |
| `link(rel, href)` | arbitrary `<link>` |
| `preload(href)` | font preload `<link>` |
| `rss(url, title=nil)` | RSS alternate `<link>` |
| `sitemap(href)` | sitemap `<link>` |
| `revised(time)` | `revised` meta with ISO8601 |
| `render { \|page\| ... }` | emits the head HTML; block returns extra HTML to inject |

## Migration from `PageMeta`

```ruby
# before
class FrontendController < ApplicationController
  before { @header = PageMeta.new App.name }
end

# layout
= @header.render do |page|
  = asset 'main.css'
```

```ruby
# after
# remove the before filter entirely

# layout
= lux.header.render do |page|
  = asset 'main.css'
```

In controllers / actions, replace `@header.X` with `lux.header.X`.

## Favicon

This plugin no longer emits favicon `<link>` tags. Use the `favicon`
plugin and put `!= Lux::Favicon.head` inside your render block (or
elsewhere in `<head>`).

## Design notes

### Setter / getter conflation

Most attribute methods are dual-purpose: with an argument they set,
without one they read.

```ruby
lux.header.title 'My page'  # set
lux.header.title            # => 'My page'
lux.header.title = 'My page' # same set, aliased
```

Returning the slot only works for `title`, `description`, `url`,
`image`, `site_name`, `type`. The flag methods (`noindex`, `nofollow`)
and the link methods (`canonical`, `link`, `preload`, `rss`,
`sitemap`) have no reader.

### `url` vs `canonical`

These touch different slots:

* `url(href)` sets `og:url` and the `url` reader.
* `canonical(href)` adds `<link rel=canonical>` and sets `og:url`, but
  does NOT update the `url` reader.

If you want both the `<link>` and `header.url` to read back the value,
call both:

```ruby
lux.header.canonical href
lux.header.url       href
```

### `meta` property vs name detection

Keys starting with any of `og:`, `fb:`, `article:`, `book:`, `profile:`,
`video:`, `music:` are emitted as `<meta property="...">`. Everything
else (including `twitter:` per Twitter's docs) is emitted as
`<meta name="...">`. The list is `Lux::Header::META_PROPERTY_PREFIXES`.

### `render` side effects

`render` writes the `x-robots-tag` response header (driven by
`noindex` / `nofollow`). It is designed to be called exactly once per
request from the layout `<head>` block. Repeated calls are idempotent
(same header value) but waste work.

### Length caps

* `title` is trimmed to `MAX_TITLE_LENGTH` (100) chars with a `&hellip;`
  suffix.
* `description` is trimmed to `MAX_DESCRIPTION_LENGTH` (140) chars.

### HTML escaping

`<title>` text and `<meta content="...">` values are escaped via
`Rack::Utils.escape_html` (`&`, `<`, `>`, `"`, `'`). Raw `<link>`
strings passed to `link`, `rss`, `sitemap`, `preload`, `canonical`
are NOT escaped - the caller is responsible.
