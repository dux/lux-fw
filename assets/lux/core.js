// Lux client core. Sets up window.Lux skeleton + fetch helper.
// Loaded via app asset packs (auto/common); per-request csrf/config are
// assigned by #lux-state (Lux::Browser#window_script) before bundles run.
// Still available at /_lux_/core.js for direct include if needed.
;(function (global) {
  var Lux = global.Lux = global.Lux || {};

  // Filled by #lux-state when present; leave existing values alone if set.
  if (typeof Lux.csrf === 'undefined') Lux.csrf = null;
  Lux.config = Lux.config || {};

  // JSON-aware fetch wrapper. Defaults method to POST (the primary use case
  // is mutations / form submissions), auto-adds X-CSRF-Token from Lux.csrf,
  // and serialises object/array bodies as JSON. Override per call by passing
  // your own method / headers / body.
  //
  //   Lux.fetch('/api/users', { body: { name: 'Joe' } })          // POST
  //   Lux.fetch('/api/users/42', { method: 'GET' })                // explicit GET
  Lux.fetch = function (url, opts) {
    opts = opts || {};
    opts.method = opts.method || 'POST';
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
