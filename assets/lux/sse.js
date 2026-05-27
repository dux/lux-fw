// Lux.subscribe - thin pub/sub client for SSE streamed by /_lux_/stream.
//
//   Lux.subscribe('notifications', msg => banner.show(msg))
//   Lux.subscribe('user:42',       msg => inbox.update(msg))
//
// Auto-connects on first subscribe. Idempotent: same (channel, fn) pair
// won't register twice; same channel name across calls reuses the
// EventSource. Adding a new channel reconnects with the merged list
// (debounced into one reconnect per tick).
//
//   Lux.unsubscribe('notifications', fn)   // drop one handler
//   Lux.unsubscribe('notifications')       // drop all handlers + reconnect
//   Lux.disconnect()                       // close the stream entirely
;(function (global) {
  var Lux = global.Lux = global.Lux || {};

  var STREAM_URL = '/_lux_/stream';

  var _es             = null;
  var _handlers       = {};    // channel -> [fn, ...]
  var _bound          = {};    // channel -> true once addEventListener attached on _es
  var _reconnectTimer = null;
  var _openedFor      = '';    // sorted channel list the current _es was opened with

  function _channelList() {
    return Object.keys(_handlers).sort();
  }

  function _bind(channel) {
    if (_bound[channel] || !_es) return;
    _bound[channel] = true;
    _es.addEventListener(channel, function (e) {
      var data = e.data;
      try { data = JSON.parse(data); } catch (_) { /* leave as string */ }
      var list = _handlers[channel] || [];
      for (var i = 0; i < list.length; i++) {
        try { list[i](data, e); }
        catch (err) { console.error('Lux.subscribe handler error', channel, err); }
      }
    });
  }

  function _openIfNeeded() {
    var chs    = _channelList();
    var wanted = chs.join(',');

    // Nothing to listen to - close any open stream.
    if (!wanted) {
      if (_es) { _es.close(); _es = null; _bound = {}; _openedFor = ''; }
      return;
    }

    // Already open for the exact channel set - just (re)bind any
    // handlers we haven't attached yet.
    if (_es && wanted === _openedFor) {
      chs.forEach(_bind);
      return;
    }

    // Channel set changed - reopen with the new query string.
    if (_es) { _es.close(); _es = null; _bound = {}; }
    _openedFor = wanted;
    _es = new EventSource(STREAM_URL + '?channels=' + chs.map(encodeURIComponent).join(','));
    chs.forEach(_bind);
  }

  // Coalesce N subscribe() calls in a row into one EventSource open.
  function _scheduleOpen() {
    if (_reconnectTimer) return;
    _reconnectTimer = setTimeout(function () {
      _reconnectTimer = null;
      _openIfNeeded();
    }, 0);
  }

  Lux.subscribe = function (channel, fn) {
    if (typeof channel !== 'string' || !channel) throw new Error('Lux.subscribe: channel must be a non-empty string');
    if (typeof fn !== 'function')                throw new Error('Lux.subscribe: fn must be a function');

    var list = _handlers[channel] = _handlers[channel] || [];
    if (list.indexOf(fn) === -1) list.push(fn);
    _scheduleOpen();
    return Lux;
  };

  Lux.unsubscribe = function (channel, fn) {
    var list = _handlers[channel];
    if (!list) return Lux;

    if (fn) {
      _handlers[channel] = list.filter(function (f) { return f !== fn; });
      if (_handlers[channel].length) return Lux;
    }

    delete _handlers[channel];
    _scheduleOpen();
    return Lux;
  };

  Lux.disconnect = function () {
    if (_reconnectTimer) { clearTimeout(_reconnectTimer); _reconnectTimer = null; }
    if (_es)             { _es.close(); _es = null; }
    _bound      = {};
    _openedFor  = '';
    return Lux;
  };
})(typeof window !== 'undefined' ? window : globalThis);
