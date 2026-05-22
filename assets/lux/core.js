// Lux client core. Sets up window.Lux skeleton + per-request state.
// Composed by Lux::Browser and served at /lux/client.js (or /lux/*.js
// for an individual module - core is always prepended).
;(function (global) {
  var Lux = global.Lux = global.Lux || {};

  // Server-injected per-request state.
  Lux.csrf = <%= Lux.current.csrf.to_json %>;
  Lux.config = {
    host:   <%= Lux.config.host.to_s.to_json %>,
    locale: <%= Lux.current.locale.to_s.to_json %>
  };

  // JSON-aware fetch wrapper. Auto-adds X-CSRF-Token from Lux.csrf and
  // serialises object/array bodies as JSON. Override per call by passing
  // your own headers / body.
  //
  //   Lux.fetch('/api/users', { method: 'POST', body: { name: 'Joe' } })
  Lux.fetch = function (url, opts) {
    opts = opts || {};
    opts.headers = Object.assign({}, opts.headers);
    if (Lux.csrf && !opts.headers['X-CSRF-Token']) {
      opts.headers['X-CSRF-Token'] = Lux.csrf;
    }
    if (opts.body && typeof opts.body === 'object' && !(opts.body instanceof FormData) && !(opts.body instanceof Blob)) {
      opts.headers['Content-Type'] = opts.headers['Content-Type'] || 'application/json';
      opts.body = JSON.stringify(opts.body);
    }
    return fetch(url, opts);
  };
})(typeof window !== 'undefined' ? window : globalThis);
