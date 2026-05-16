# Lux.plugin :auto_controller

Convention-based routing helper. Provides filter matching and template
auto-finding for controllers.

## Setup

```ruby
Lux.plugin :auto_controller
```

Then include in a controller:

```ruby
class MainController < ApplicationController
  include Lux::AutoController

  def filters
    filter :notes do
      filter :ref do
        # ...
      end
    end
  end
end
```

## Layout

```
plugins/auto_controller/
  load/
    auto_controller.rb       # Lux::AutoController module
```
