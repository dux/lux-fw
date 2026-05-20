// Boot script for the Lux::Api explorer.
//   1. window.lux_api: schema URLs + loaded schema (no bearer logic here -
//      that lives in <lux-api-header>; subscribe to 'lux_api:bearer-changed'
//      or read localStorage('lux_api_bearer') to consume it)
//   2. PostWind init (Tailwind utilities)
//   3. fetch /sys/schema and publish on 'lux_api:schema-loaded'
//
// UI structure is split across fez components:
//   <lux-api-header>  - top bar (search input, bearer toggle/editor)
//   <lux-api-sidebar> - left nav (namespace groups, scroll-spy marker)
//   <lux-api-apis>    - main content column; renders namespace sections
//                       after schema-loaded fires
//
// Lux::Api is JSON-RPC style: every action is reached via POST. The UI does
// NOT show REST verb pills - the snippets and try-it always POST.

(function () {
  const sysBase = location.pathname.split('/sys/')[0] + '/sys';

  window.lux_api = {
    api_schema:  null,
    sys_base:    sysBase,
    schema_url:  sysBase + '/schema',
    postman_url: sysBase + '/postman',
    openapi_url: sysBase + '/openapi'
  };

  // --- PostWind ------------------------------------------------------------

  // Typography + buttons + labels are defined as plain CSS (in index.html
  // <style> and component <style> blocks). PostWind is here only for the
  // Tailwind atomic utilities used for layout/spacing/colors.
  PostWind.init({ tailwind: true, body: true });

  // --- schema fetch --------------------------------------------------------

  document.addEventListener('DOMContentLoaded', function () {
    Fez.fetch(window.lux_api.schema_url, function (schema) {
      window.lux_api.api_schema = schema;
      Fez.publish('lux_api:schema-loaded', schema);
    });
  });
})();
