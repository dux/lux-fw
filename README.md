# LUX - ruby web framework

![Lux logo](https://i.imgur.com/Zy7DLXU.png)

* rack based
* explicit, avoid magic when possible

created by @dux in 2017

## How to start

* define Lux.app do ...
* use Cells to render templates
* example to come ...

## Lux components

* [api](lib/lux/api)                 - api handler
* [application](lib/lux/application) - main application controller and router
* [cache](lib/lux/cache)             - Lux.cache mimics Rails.cache
* [cell](lib/lux/cell)               - Lux view controllers
* [config](lib/lux/config)           - config loader
* [current](lib/lux/current)         - main state object
* [delayed_job](lib/lux/delayed_job) - experimental delayed job interface
* [error](lib/lux/error)             - in case of error
* [helper](lib/lux/helper)           - templat helpers
* [mailer](lib/lux/mailer)           - mailers
* [response](lib/lux/response)       - response
* [template](lib/lux/template)       - server template rendering logic

## Example

Install gem with `gem install lux-fw`

#### config.ru

```ruby
require 'lux-fw'

class RootCell < Lux::Cell
  def index
    render text: 'Hello world'
  end

  def foo
    render text: 'Foo text'
  end

  def baz
    render text: 'Baz text'
  end
end

Lux.app.routes do
  root   RootCell

  action foo: RootCell

  map    bar: RootCell

  map RootCell do
    map :baz
  end
end

run Lux
```

`puma -p 3000`

* `curl http://localhost:3000/` -> `Hello world`
* `curl http://localhost:3000/foo` -> `Foo text`
* `curl http://localhost:3000/bar` -> `Hello world` (maps to RootCell that calls :index)
* `curl http://localhost:3000/baz` -> `Baz text`


