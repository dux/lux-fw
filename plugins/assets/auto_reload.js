// <script src="/autoreload-check"></script>
// @page_meta.auto_relad

(function() {
  // JUST INCLUDE @page.asset '/autoreload-check'
  var auto_reload;

  auto_reload = function() {
    var check, url;
    check = {}
    // get all header links
    $('head').find('script, link').each(function() {
      var parts, target
      target = $(this).attr('src') || $(this).attr('href')
      parts = target.split('?')
      if (!(target.indexOf('/assets/') > -1)) {
        return
      }
      return check[parts[0].split('/')[2]] = [parts[1], this]
    })

    // check for file changes
    url = '/autoreload-check?f=' + Object.keys(check).join(',')
    return $.get(url, function(data) {
      var hash, key, message, node, path, results
      for (key in data) {
        hash = data[key]
        if (hash !== check[key][0]) {
          message = `Autoreload: ${key} (${hash})`

          if (Info) { Info.ok(message) }
          console.log(message)

          location.href = location.href
        }
      }
    })
  }

  auto_reload();

  setInterval(auto_reload, 2000);

}).call(this);
