# Lux.plugin :auto_controller

Convention-based routing mixin: turn a URL path into a view lookup under
`app/views/<scope>/`, from a controller that drives its own `call`.

```ruby
Lux.plugin :auto_controller
```

## Usage

Include `Lux::Controller::Auto` (usually via an app `ControllerAutoLoader`) and
call the helpers from your `call`:

```ruby
module ControllerAutoLoader
  include Lux::Controller::Auto
end

class MainController < ApplicationController
  include ControllerAutoLoader
  layout :main

  def call
    auto_render
  end
end
```

`auto_render` mounts `nav.path` under `cattr.layout` (the controller's `layout`)
and renders the matching template, or `/error_404` when none matches.

Available helpers: `auto_render`, `auto_find_template`, `auto_export_var`,
`filter`.

## Path resolution

With `layout :main` and the default `template_root` of `./app/views`,
`auto_render` looks under `app/views/main/`:

| URL            | template (first match wins)                          |
| ---            | ---                                                  |
| `/`            | `main/root.{haml,erb,md}`                            |
| `/notes`       | `main/notes.*`                                       |
| `/notes/intro` | `main/notes/intro.*`, else `main/notes/intro/root.*` |

No match renders `/error_404` with status 404.

## Filters

Inside `call` (or any action) the `filter :seg do ... end` matcher runs its
block only when `nav.path` matches the given segments at the current depth.
Nesting descends one segment per level, so filters read like the URL; `:ref`
matches the extracted ref placeholder:

```ruby
filter :spaces do          # /spaces/*
  filter :ref do           # /spaces/:ref/*
    filter :admin do       # /spaces/:ref/admin
      @space.can.update!
    end
  end
end
```

Pass several segments to match in one step (`filter :admin, :users`). A block
that renders or redirects short-circuits the rest.

## auto_export_var

Find a model by ref, optionally policy-check it, and set `@object` plus a named
ivar:

```ruby
auto_export_var :task, params[:t], :read   # @object = @task = Task.find(...).can.read!
```

> The `/model/:ref` loader lives on `nav` as `nav.ref_object`; model loading is
> done by the router (`nav.load_models`) before dispatch.

## Layout

```
plugins/auto_controller/
  load/
    auto_controller.rb       # Lux::Controller::Auto mixin
```
