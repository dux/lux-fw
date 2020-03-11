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

Create new template for lux app

`lux new my-app`

Start the app

`budle exec lux s`

Look at the generated code and play with it.


## Lux module

Main `Lux` module has a few usefull methods.

```ruby
Lux.root     # Pathname to application root
Lux.fw_root  # Pathname to lux gem root
Lux.speed {} # execute block and return speed in ms
Lux.info     # show console info in magenta
Lux.run      # run a command on a server and log it
Lux.die      # stop execution of a program and log
```
