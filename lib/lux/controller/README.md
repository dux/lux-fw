## Lux::Controller - Simplified Rails like view controllers

Controllers are Lux view models

* all cells shoud inherit from Lux::Controller
* `before`, `before_action` and `after` class methods supportd
* instance_method `on_error` is supported
* calls templates as default action, behaves as Rails controller.

### Example code

```ruby
require 'lux-fw'

class Main::RootController < Lux::Controller
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

  ###

  mock :show # mock `show` action

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
```