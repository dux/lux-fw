// Lux client core. Sets up window.Lux skeleton + fetch helper.
// Bundled into app packs via Lux::Browser.client_js (README); per-request csrf/config are
// assigned by #lux-state (Lux::Browser#window_script) before bundles run.
// Still available at /_lux_/core.js for direct include if needed.
;(function (global) {
  var Lux = global.Lux = global.Lux || {};

  // Filled by #lux-state when present; leave existing values alone if set.
  if (typeof Lux.csrf === 'undefined') Lux.csrf = null;
  Lux.config = Lux.config || {};

  // JSON-aware fetch wrapper. Defaults method to POST (the primary use case
  // is mutations / form submissions), adds X-CSRF-Token from Lux.csrf on
  // same-origin requests only, and serialises plain object/array bodies as
  // JSON. Override per call by passing your own method / headers / body.
  //
  //   Lux.fetch('/api/users', { body: { name: 'Joe' } })          // POST
  //   Lux.fetch('/api/users/42', { method: 'GET' })                // explicit GET
  function _sameOrigin(url) {
    if (!global.location) return true;
    try { return new URL(typeof url === 'string' ? url : url.url, global.location.href).origin === global.location.origin; }
    catch (_) { return false; }
  }

  Lux.fetch = function (url, opts) {
    opts = Object.assign({}, opts);
    opts.method = opts.method || 'POST';
    var headers = new Headers(opts.headers);
    if (Lux.csrf && !headers.has('X-CSRF-Token') && _sameOrigin(url)) headers.set('X-CSRF-Token', Lux.csrf);
    var body = opts.body;
    if (body && (Array.isArray(body) || Object.prototype.toString.call(body) === '[object Object]')) {
      if (!headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
      opts.body = JSON.stringify(body);
    }
    opts.headers = headers;
    return fetch(url, opts);
  };
})(typeof window !== 'undefined' ? window : globalThis);
