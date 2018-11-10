### Create Sequel plugin

```
module Sequel::Plugins::LuxHelp

  module ClassMethods
    def bla
      model # => refrence to model
    end
  end

  module InstanceMethods

  end

  module DatasetMethods

  end

end

Sequel::Model.plugin :lux_help
```

Default scope: http://stackoverflow.com/questions/11669880/default-scope-in-sequel

### init

If init.rb is defined it will be called, else all files will be loaded.