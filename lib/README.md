<img alt="Lux logo" width="100" height="100" src="https://i.imgur.com/Zy7DLXU.png" align="right" />

# LUX - ruby web framework

* rack based
* how? # explicit, avoid magic when possible
* why? # fun, learn
* dream? # sinatra speed and memory usage with Rails interface

created by @dux in 2017

## How to start

First, make sure you have `ruby 2.x+` installed.

`gem install lux-fw`

Create a new Lux app

`lux new my-app`

Set it up and start it

```
cd my-app && bundle install
createdb my_app_development && lux db:am
lux s
```

Look at the generated code and play with it.


## Lux module

Main `Lux` module has a few usefull methods.

```ruby
Lux.root         # Pathname to application root
Lux.fw_root      # Pathname to lux gem root
Lux.speed { }    # execute block and return speed in ms
Lux.shell.info   # magenta status to STDERR
Lux.shell.error  # red status to STDERR
Lux.shell.die    # logger.fatal + exit 1
Lux.shell.exec   # safe argv-mode process execution (see lib/lux/shell)
```
