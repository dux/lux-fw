// Lux.sse - thin client for server-sent events streamed by response.sse.
// Single EventSource per page; events are dispatched by channel name.
//
//   Lux.sse.on('notifications', msg => banner.show(msg))
//   Lux.sse.on('user:42',       msg => inbox.update(msg))
//   Lux.sse.connect('/stream')
;(function (global) {
  var Lux = global.Lux = global.Lux || {};

  Lux.sse = {
    _es:       null,
    _handlers: {},   // channel -> [fn, ...]
    _bound:    {},   // channel -> true once addEventListener attached

    // Open the underlying EventSource. Idempotent.
    connect: function (url) {
      if (this._es) return this;
      this._url = url;
      this._es  = new EventSource(url);
      var self  = this;
      Object.keys(this._handlers).forEach(function (channel) {
        self._bind(channel);
      });
      return this;
    },

    on: function (channel, fn) {
      this._handlers[channel] = (this._handlers[channel] || []).concat(fn);
      if (this._es) this._bind(channel);
      return this;
    },

    off: function (channel, fn) {
      if (!fn) { delete this._handlers[channel]; return this; }
      var list = this._handlers[channel] || [];
      this._handlers[channel] = list.filter(function (f) { return f !== fn; });
      return this;
    },

    close: function () {
      if (this._es) {
        this._es.close();
        this._es    = null;
        this._bound = {};
      }
      return this;
    },

    _bind: function (channel) {
      if (this._bound[channel]) return;
      this._bound[channel] = true;
      var self = this;
      this._es.addEventListener(channel, function (e) {
        var data = e.data;
        try { data = JSON.parse(data); } catch (_) { /* leave as string */ }
        (self._handlers[channel] || []).forEach(function (fn) {
          try { fn(data, e); } catch (err) { console.error('Lux.sse handler error', channel, err); }
        });
      });
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
