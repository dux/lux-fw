# LUX - ruby web framework

![Lux logo](https://i.imgur.com/Zy7DLXU.png)

* rack based
* explicit, avoid magic when possible

created by @dux in 2017

## How to start

Add `lux-fw` to gemfile.

Define `config.ru` file (if you define `$lux_start_time` you will get speed load statistics)
```
$lux_start_time = Time.now
require './config/application'
Lux.serve self
```

* define Lux.app do ...
* use Controllers to render templates
* example to come

## Lux components

* [application](lib/lux/application) - main application controller and router
* [cell](lib/lux/controller)         - Lux view controllers
* [config](lib/lux/config)           - config loader
* [cache](lib/lux/cache)             - Lux.cache mimics Rails.cache
* [current](lib/lux/current)         - main state object
* [delayed_job](lib/lux/delayed_job) - experimental delayed job interface
* [error](lib/lux/error)             - in case of error
* [helper](lib/lux/helper)           - templat helpers
* [mailer](lib/lux/mailer)           - mailers
* [response](lib/lux/response)       - response
* [template](lib/lux/template)       - server template rendering logic
* [api](lib/plugins/api)             - simple api handler

## Example

Install gem with `gem install lux-fw`

#### config.ru

```ruby
require 'lux-fw'

class RootController < Lux::Controller
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
  root   RootController

  map  foo: 'root#index'

  map  bar: 'root' # /bar/baz => root#baz

  map 'root' do
    map :foo     # /foo => root#foo
    map :baz     # /baz => root#baz
  end
end
```

More examples https://github.com/dux/lux-fw/tree/master/lib/lux/application

`puma -p 3000`

* `curl http://localhost:3000/` -> `Hello world`
* `curl http://localhost:3000/foo` -> `Foo text`
* `curl http://localhost:3000/bar` -> `Hello world` (maps to RootController that calls :index)
* `curl http://localhost:3000/baz` -> `Baz text`


