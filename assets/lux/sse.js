// Lux.subscribe - thin pub/sub client for the SSE stream at /_lux_/stream.
//
//   Lux.subscribe('user:42',   msg => inbox.update(msg))
//   Lux.subscribe('wo-zip:abc', msg => log.append(msg))
//
// One socket per page, always. The stream is session-scoped: the server
// decides what it carries from the session cookie, the request has no
// parameters, and subscribing is purely local bookkeeping. So subscribing or
// unsubscribing NEVER opens, closes or reopens the connection - it is opened
// on the first subscribe and closed when the last handler goes away.
//
// Every frame is {channel, data}. A handler receives `data`, and is matched
// against the frame's channel and, if the payload is an object, its `topic` -
// which is how one session channel can carry many logical streams.
//
//   Lux.unsubscribe('user:42', fn)   // drop one handler
//   Lux.unsubscribe('user:42')       // drop all handlers for that channel
//   Lux.disconnect()                 // close the stream entirely
//
// EventSource reconnects on its own, and the server replays what was missed
// via Last-Event-ID. To surface the gap to the UI:
//
//   Lux.onConnectionChange(function (state) { ... })   // 'open' | 'closed'
;(function (global) {
  var Lux = global.Lux = global.Lux || {};

  var STREAM_URL = '/_lux_/stream';

  var _es            = null;
  var _handlers      = {};    // name -> [fn, ...]   name = channel or topic
  var _openTimer     = null;
  var _stateHandlers = [];    // fn(state)
  var _state         = 'closed';

  function _setState(state) {
    if (_state === state) return;
    _state = state;
    for (var i = 0; i < _stateHandlers.length; i++) {
      try { _stateHandlers[i](state); }
      catch (err) { console.error('Lux.onConnectionChange handler error', err); }
    }
  }

  function _hasHandlers() {
    for (var k in _handlers) if (_handlers[k] && _handlers[k].length) return true;
    return false;
  }

  function _emit(name, data, event) {
    var list = _handlers[name];
    if (!list) return;
    for (var i = 0; i < list.length; i++) {
      try { list[i](data, event); }
      catch (err) { console.error('Lux.subscribe handler error', name, err); }
    }
  }

  function _onMessage(e) {
    var frame;
    try { frame = JSON.parse(e.data); }
    catch (_) { return console.error('Lux.subscribe: unparsable frame', e.data); }
    if (!frame || typeof frame.channel !== 'string') return;

    var data = frame.data;

    _emit(frame.channel, data, e);

    // A topic routes within a channel, so a session stream can carry many
    // logical streams. Skip when it duplicates the channel name.
    var topic = data && typeof data === 'object' ? data.topic : null;
    if (typeof topic === 'string' && topic !== frame.channel) _emit(topic, data, e);
  }

  function _openIfNeeded() {
    if (!_hasHandlers()) {
      if (_es) { _es.close(); _es = null; _setState('closed'); }
      return;
    }

    if (_es) return;   // already connected - subscriptions are local only

    _es = new EventSource(STREAM_URL);
    _es.onmessage = _onMessage;

    // EventSource retries by itself; onerror fires on every drop, so this
    // reports the gap rather than driving reconnection.
    _es.onopen  = function () { _setState('open') };
    _es.onerror = function () { _setState('closed') };
  }

  // Coalesce N subscribe() calls in a row into one open.
  function _scheduleOpen() {
    if (_openTimer) return;
    _openTimer = setTimeout(function () {
      _openTimer = null;
      _openIfNeeded();
    }, 0);
  }

  // name is a channel ('user:42') or a topic carried inside one.
  Lux.subscribe = function (name, fn) {
    if (typeof name !== 'string' || !name) throw new Error('Lux.subscribe: name must be a non-empty string');
    if (typeof fn !== 'function')          throw new Error('Lux.subscribe: fn must be a function');

    var list = _handlers[name] = _handlers[name] || [];
    if (list.indexOf(fn) === -1) list.push(fn);
    _scheduleOpen();
    return Lux;
  };

  Lux.unsubscribe = function (name, fn) {
    var list = _handlers[name];
    if (!list) return Lux;

    if (fn) {
      _handlers[name] = list.filter(function (f) { return f !== fn; });
      if (_handlers[name].length) return Lux;
    }

    delete _handlers[name];
    _scheduleOpen();
    return Lux;
  };

  // fn('open' | 'closed'); called immediately with the current state.
  Lux.onConnectionChange = function (fn) {
    if (typeof fn !== 'function') throw new Error('Lux.onConnectionChange: fn must be a function');
    if (_stateHandlers.indexOf(fn) === -1) _stateHandlers.push(fn);
    fn(_state);
    return Lux;
  };

  Lux.offConnectionChange = function (fn) {
    _stateHandlers = _stateHandlers.filter(function (f) { return f !== fn });
    return Lux;
  };

  Lux.disconnect = function () {
    if (_openTimer) { clearTimeout(_openTimer); _openTimer = null; }
    if (_es)        { _es.close(); _es = null; }
    _setState('closed');
    return Lux;
  };

  // Test seam: what the page is listening for, and whether a socket is open.
  Lux.streamState = function () {
    return { connected: !!_es, state: _state, names: Object.keys(_handlers).sort() };
  };
})(typeof window !== 'undefined' ? window : globalThis);
