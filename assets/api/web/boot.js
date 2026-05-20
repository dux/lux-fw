// Boot script for the Joshua API explorer.
//   1. window.joshua: schema URLs + loaded schema (no bearer logic here -
//      that lives in <joshua-header>; subscribe to 'joshua:bearer-changed'
//      or read localStorage('joshua_bearer') to consume it)
//   2. PostWind init (Tailwind utilities)
//   3. fetch /sys/schema and publish on 'joshua:schema-loaded'
//
// UI structure is split across fez components:
//   <joshua-header>  - top bar (search input, bearer toggle/editor)
//   <joshua-sidebar> - left nav (namespace groups, scroll-spy marker)
//   <joshua-apis>    - main content column; renders namespace sections
//                      after schema-loaded fires
//
// Joshua is JSON-RPC style: every action is reached via POST. The UI does
// NOT show REST verb pills - the snippets and try-it always POST.

(function () {
  const sysBase = location.pathname.split('/sys/')[0] + '/sys';

  window.joshua = {
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
    Fez.fetch(window.joshua.schema_url, function (schema) {
      window.joshua.api_schema = schema;
      Fez.publish('joshua:schema-loaded', schema);
    });
  });
})();
