# Lux plugins

* loads plugins in selected namespace, default namespace :main
* gets plugins in selected namespace

```ruby
Lux.plugin name_or_folder
Lux.plugin name: :foo, folder: '/.../...', namespace: [:main, :admin]
Lux.plugin name: :bar

Luxp.lugin.folders :admin # => [:foo]
Luxp.lugin.folders # => [:foo, :bar]
```
