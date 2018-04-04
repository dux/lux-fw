### Page render flow

* config.ru calls Lux::Application.call(rack_enviroment)
* returns rack response [http status, heders hash, body]
