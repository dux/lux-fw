// Boot script for the Lux::Api explorer.
//   1. window.lux_api: schema URLs + loaded schema (no bearer logic here -
//      that lives in <lux-api-header>; subscribe to 'lux_api:bearer-changed'
//      or read localStorage('lux_api_bearer') to consume it)
//   2. window.luxMd: tiny markdown helper used by component templates via
//      {@html window.luxMd(text)}
//   3. PostWind init (Tailwind utilities)
//   4. fetch /sys/schema and publish on 'lux_api:schema-loaded'
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

  // ---- markdown ----------------------------------------------------------
  // Minimal markdown for desc / detail strings authored in Ruby. Escapes
  // first, then re-applies a small set of inline transforms. No block
  // constructs (lists, headings) - those are too rich for one-liner doc
  // strings and would invite ambiguity with backend output.
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
  }

  window.luxMd = function (text) {
    if (text == null || text === '') return '';
    let s = escapeHtml(text);

    // 1) code spans
    s = s.replace(/`([^`]+)`/g, '<code>$1</code>');

    // 2) [label](url) - stashed as placeholders so the bare-url pass below
    //    does NOT re-linkify the href we just generated. Sentinel is plain
    //    ASCII to keep the source file clean.
    const tokens = [];
    s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (_, label, url) {
      tokens.push('<a href="' + url + '" target="_blank" rel="noopener">' + label + '</a>');
      return '@@LMD_LINK_' + (tokens.length - 1) + '@@';
    });

    // 3) bare urls
    s = s.replace(/(^|[^\w])(https?:\/\/[^\s<]+)/g,
      '$1<a href="$2" target="_blank" rel="noopener">$2</a>');

    // 4) emphasis
    s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    s = s.replace(/(^|\W)\*([^*\s][^*]*[^*\s]|[^*\s])\*(?=\W|$)/g, '$1<em>$2</em>');

    // 5) restore stashed links
    s = s.replace(/@@LMD_LINK_(\d+)@@/g, function (_, i) { return tokens[+i]; });
    return s;
  };

  // ---- JSON tree toggle --------------------------------------------------
  // Inline onclick target on .jv-toggle inside response JSON trees rendered
  // by lux-api-runner. Lives on window so the markup stays self-contained
  // and survives fez template re-renders.
  window.luxJvToggle = function (el) {
    const summary = el.parentNode;
    const group   = summary && summary.parentNode;
    if (!group) return;
    const children = group.querySelector(':scope > .jv-children');
    const count    = group.querySelector(':scope > .jv-count');
    if (!children) return;
    const open = !children.classList.contains('is-open');
    children.classList.toggle('is-open', open);
    el.classList.toggle('is-open', open);
    el.textContent = open ? '▾' : '▸';
    if (count) count.style.display = open ? 'none' : 'inline';
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

  // --- keyboard nav --------------------------------------------------------
  // '/' focuses the filter input. 'Esc' clears focus / closes the cheatsheet.
  // 'j' / 'k' step to next / previous method anchor. '?' toggles a small
  // cheatsheet overlay. All handlers no-op while the user is typing in an
  // input or textarea.

  function isTyping() {
    const el = document.activeElement;
    if (!el) return false;
    const tag = (el.tagName || '').toLowerCase();
    return tag === 'input' || tag === 'textarea' || el.isContentEditable;
  }

  function focusFilter() {
    const f = document.querySelector('.jh-search');
    if (f) { f.focus(); f.select(); }
  }

  function methodAnchors() {
    return Array.from(document.querySelectorAll('article[id^="method-"]'));
  }

  function stepMethod(direction) {
    const items = methodAnchors();
    if (!items.length) return;
    const y = window.scrollY + 80;  // account for sticky header
    const idx = items.findIndex(a => a.getBoundingClientRect().top + window.scrollY > y);
    let target;
    if (direction > 0) {
      target = idx === -1 ? items[items.length - 1] : items[idx];
    } else {
      const prevIdx = idx === -1 ? items.length - 1 : Math.max(0, idx - 2);
      target = items[prevIdx];
    }
    if (target) {
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      history.replaceState(null, '', '#' + target.id);
    }
  }

  function toggleCheatsheet(force) {
    let sheet = document.getElementById('lux-cheatsheet');
    if (sheet && force !== true) { sheet.remove(); return; }
    if (sheet) return;
    sheet = document.createElement('div');
    sheet.id = 'lux-cheatsheet';
    sheet.innerHTML =
      '<div class="cs-card">' +
        '<div class="cs-title">Keyboard shortcuts</div>' +
        '<div class="cs-row"><kbd>/</kbd>     <span>focus filter</span></div>' +
        '<div class="cs-row"><kbd>j</kbd>     <span>next method</span></div>' +
        '<div class="cs-row"><kbd>k</kbd>     <span>previous method</span></div>' +
        '<div class="cs-row"><kbd>?</kbd>     <span>toggle this sheet</span></div>' +
        '<div class="cs-row"><kbd>Esc</kbd>   <span>close / blur input</span></div>' +
      '</div>';
    sheet.addEventListener('click', () => sheet.remove());
    document.body.appendChild(sheet);
  }

  document.addEventListener('keydown', function (e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;

    if (e.key === 'Escape') {
      const sheet = document.getElementById('lux-cheatsheet');
      if (sheet) { sheet.remove(); e.preventDefault(); return; }
      if (isTyping()) { document.activeElement.blur(); e.preventDefault(); }
      return;
    }

    if (isTyping()) return;

    switch (e.key) {
      case '/': focusFilter();         e.preventDefault(); break;
      case 'j': stepMethod(+1);        e.preventDefault(); break;
      case 'k': stepMethod(-1);        e.preventDefault(); break;
      case '?': toggleCheatsheet();    e.preventDefault(); break;
    }
  });

  // Cheatsheet styles
  const style = document.createElement('style');
  style.textContent = `
    #lux-cheatsheet {
      position: fixed; inset: 0; z-index: 1000;
      background: rgba(15, 23, 42, 0.45);
      display: flex; align-items: center; justify-content: center;
      cursor: pointer;
    }
    #lux-cheatsheet .cs-card {
      background: #0f172a; color: #e2e8f0;
      padding: 24px 28px; border-radius: 12px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.4);
      font-family: 'JetBrains Mono', ui-monospace, monospace;
      min-width: 280px; cursor: default;
    }
    #lux-cheatsheet .cs-title { color: #fff; font-size: 13px; font-weight: 700;
      text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 16px;
      font-family: 'Inter', system-ui, sans-serif; }
    #lux-cheatsheet .cs-row { display: flex; align-items: center; gap: 14px;
      padding: 4px 0; font-size: 14px; }
    #lux-cheatsheet kbd {
      display: inline-block; min-width: 38px; padding: 3px 8px;
      background: #1e293b; border: 1px solid #334155; border-radius: 4px;
      font-size: 12px; color: #cbd5e1; text-align: center;
      font-family: 'JetBrains Mono', ui-monospace, monospace; }
    #lux-cheatsheet span { color: #cbd5e1;
      font-family: 'Inter', system-ui, sans-serif; }
  `;
  document.head.appendChild(style);
})();
