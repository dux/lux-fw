## Lux::Controller

Similar to Rails Controllers

* `before`, `before_action`, `after` and `rescue_from` class methods supportd
* calls templates as default action, behaves as Rails controller.

```ruby
class RootController < ApplicationController
  # action to perform before
  before do
    @org = Org.find @org_id if @org_id
    # ...
  end
  # action to perform before

  before_action do |action_name|
    next if action_name == :index
    # ...
  end

  template_location './app/views' # default

  ###

  mock :show # mock `show` action

  def index
    render text: 'Hello world'
  end

  def foo
    # renders ./app/views/root/foo.(haml, erb)
  end

  def baz
    send_file local_file, file_name: 'local.txt'
  end

  def bar
    render json: { data: 'Bar text' }
  end

  def transfer
    # transfer to :baz
    action :baz

    # transfer to Another::Foo#bar
    action 'another/foo#bar'
  end
end
```

Render method can accept numerous parameters

```ruby
class MainController
  def foo
    render text: 'foo'
    render plain: 'foo'
    render html: '<html>...'
    render json: {}
    render javascript: '...'
    render template: false, content_type: :text
    render template: './some/template.haml', data: @template_data

    # helpers
    helper.link_to # MainHelper.link_to
    helper(:bar)   # BarHelper.link_to

    # respond to formats
    respond_to :js do ...
    respond_to do |format|
      case format
      when nil # /foo
        # ...
      when :js # /foo.js
        # ...
      end
  end
```

Definable callbacks

```ruby
before do ...        # before all
before_action do ... # before action
before_render do ... # before render
after_action do ...  # after action
after do ...         # after all
```

Definable class variables

```ruby
# define master layout
# string is template, symbol is method pointer and lambda is lambda
layout './some/layout.haml'

# define helper contest, by defult derived from class name
helper :global

# custom template root instead calcualted one
template_root './apps/admin/views'
```
