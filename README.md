# LUX - ruby web framework

![Lux logo](https://i.imgur.com/Zy7DLXU.png)

* rack based
* explicit, avoid magic when possible

created by @dux in 2017

## How to start

* define Lux.app do ...
* use Cells to render templates
* example to come ...

## Lux components

* [api](lib/lux/api)                 - api handler
* [application](lib/lux/application) - main application controller and router
* [cache](lib/lux/cache)             - Lux.cache mimics Rails.cache
* [cell](lib/lux/cell)               - Lux view controllers
* [config](lib/lux/config)           - config loader
* [current](lib/lux/current)         - main state object
* [delayed_job](lib/lux/delayed_job) - experimental delayed job interface
* [error](lib/lux/error)             - in case of error
* [helper](lib/lux/helper)           - templat helpers
* [html](lib/lux/html)               - form builder helpers
* [mailer](lib/lux/mailer)           - mailers
* [response](lib/lux/response)       - response
* [template](lib/lux/template)       - server template rendering logic

