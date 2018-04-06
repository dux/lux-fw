### Page render flow

* in `config.ru` you have to define `run Lux`, that will call `Lux.call(rack_enviroment)`
* returns rack response [Integer http_status, Hash headers, [String body]]
