## Lux.plugin (Lux::Plugin)

Plugin management

* loads plugins in selected namespace, default namespace :main
* gets plugins in selected namespace

```ruby
# load a plugin
Lux.plugin name_or_folder
Lux.plugin name: :foo, folder: '/.../...', namespace: [:main, :admin]
Lux.plugin name: :bar

# plugin folder path
Lux.plugin.folder(:foo) # /home/app/...

# Load lux plugin
Lux.plugin :db
```
