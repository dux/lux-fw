## Lux::Current - Main state object

Current application state as single object. Defined in Thread.current, available everywhere.

`Lux.current` - current response state

* `session`         - session, encoded in cookie
* `locale`          - locale, default nil
* `request`         - Rack request
* `response`        - Lux response object
* `nav`             - lux nav object
* `cookies`         - Rack cookies
* `can_clear_cache` - set to true if user can force refresh cache

