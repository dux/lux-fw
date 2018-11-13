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

class Main::RootController < Lux::Controller
  # action to perform before
  before do do |action_name|
    @org = Org.find @object_id if @object_id
    # ...
  end
  # action to perform before

  before_action do |action_name|
    next if action_name == :index
    # ...
  end

  ###

  def index
    render text: 'Hello world'
  end

  def foo
    # renders ./app/views/main/root/foo.(haml, erb)
  end

  def baz
    send_file local_file, file_name: 'local.txt'
  end

  def bar
    render json: { data: 'Bar text' }
  end

end

# app boot stack
Lux.app do
  # app config
  config do
    Lux.config.foo = :bar
  end

  # after config on app boot
  boot do
    # ...
  end
end

# on every request, while in routing
Lux.app do
  # before routes resolve
  before do
    # ...
  end

  # after routes resolve
  after do
    # ...
  end

  routes do
    root   RootController

    map  foo: 'root#index' # /foo  => 'root#index'

    # similar to resources in Rails, maps adaptively
    map  bar: 'root' # /bar        => root#index
                     # /bar/1/baz  => root#show (current.nav.id == 1)
                     # /bar/baz    => root#baz
                     # /bar/1/baz  => root#baz (current.nav.id == 1)

    map 'root' do
      map :foo     # /foo => root#foo
      map :baz     # /baz => root#baz
    end

    namespace 'foo' do
      map baz: 'root#baz' # /foo/baz => root#baz
    end

  end
end
```

More examples https://github.com/dux/lux-fw/tree/master/lib/lux/application

