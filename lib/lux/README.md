### Page render flow

* config.ru calls Lux::Current -> Lux::Current.call(ranck_enviroment)
* returns rack response [http status, heders hash, body]
