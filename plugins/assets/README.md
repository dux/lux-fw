# Lux.plugin :assets

Asset generation and template helpers.

## Setup

```ruby
Lux.plugin :assets
```

Loads `CdnAsset` and extends `ApplicationHelper` with `svelte` and related
template helpers.

## CLI

```
lux assets:auto      # compile app/assets/auto into auto-<folder>.{js,scss}
```

## Layout

```
plugins/assets/
  Hammerfile           # `lux assets:*` tasks, also defines LuxAssets
  load/
    cdn_asset.rb       # CdnAsset module
    lux_helper.rb      # ApplicationHelper extensions
```
