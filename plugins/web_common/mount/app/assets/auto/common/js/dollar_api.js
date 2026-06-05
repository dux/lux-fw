// thin wrapper over $.ajax POST to /api/*, returning a chainable response handler.
// silent by default: nothing is shown unless you ask for it via .info().
//   Api(path, opts)                    execute silently (no success or error info)
//   Api(path, opts).info()             execute with info notification (success and errors)
//   Api(path, opts).silent()           explicit silent (the default)
//   Api(path, opts).topInfo()          silent save + flash the top progress bar
//   Api(path, opts).topInfo().done(fn) top bar + custom callback
//   Api(path, opts).info().done(fn)    info + custom callback
//   Api(path, opts).info().follow(p)   info and redirect on success
// path may also be a <form>; action becomes the path, fields the payload.

const $ = window.$

class ApiResponse {
  constructor(api_response) {
    // bind every prototype method (incl. app-defined ones) so a method detached
    // from its receiver, e.g. `execHash.error || this.error`, keeps its `this`.
    for (const m of Object.getOwnPropertyNames(ApiResponse.prototype))
      if (m != 'constructor' && typeof this[m] == 'function') this[m] = this[m].bind(this)

    // silent unless the caller opts into notifications
    this.is_silent = true

    if (api_response)
      window.requestAnimationFrame(() => this.onRequestDone(api_response))
  }

  onRequestDone(api_response, execHash = {}) {
    this.api_response ||= api_response
    this.response ||= JSON.parse(this.api_response.responseText)
    this.data = this.response.data
    this.meta = this.response.meta

    // .info() opts back into notifications, including on the error path
    if ('info' in execHash) this.is_silent = false

    if (this.response.error) {
      (execHash.error || this.error)()
    } else if (this.api_response.status == 200) {
      for (const m of Object.keys(execHash)) this[m](execHash[m])
    } else {
      alert('API strange error')
    }
  }
}

$.apiResponse = ApiResponse

// apps override or add chainable response methods to match their own stack
// (Dialog / Pjax / Info, etc.); methods should return `this` to stay chainable.
//   $.apiResponse.define({ close() { MyDialog.close(); return this } })
ApiResponse.define = methods => (Object.assign(ApiResponse.prototype, methods), ApiResponse)

// read fresh off the prototype each call so app overrides/additions are picked up
const apiMethods = () => Object.getOwnPropertyNames(ApiResponse.prototype)
  .filter(name => name != 'constructor' && name != 'onRequestDone' && typeof ApiResponse.prototype[name] == 'function')

// base chainable methods, declared through the same public API apps use
ApiResponse.define({
  // what to close
  close() {
    Dialog.close()
    return this
  },

  // refresh page in place
  refresh(what) {
    if (what != false) {
      if (what == true) what = undefined
      Pjax.refresh(what) // page, dialog, smart, all
    }
    return this
  },

  // reload page and scroll to top
  reload() {
    Pjax.reload()
    return this
  },

  // follow link from meta
  follow(arg) {
    let header_location
    if (arg) {
      // Api('posts/create', name: 'New post').follow('/admin/posts/show/ulid:{ulid}')
      const path = arg.replace(/\{(\w+)\}/g, (_, r1) => this.data[r1])
      Pjax.load(path)
    } else if ((header_location = this.api_response.getResponseHeader('location'))) {
      Pjax.load(header_location)
    } else if (location.pathname.includes('/admin/')) {
      const base = location.pathname.split('/')[2]
      Pjax.load(`/admin/${base}/${this.data.ref}`)
    } else if (this.response.meta.path) {
      Pjax.load(this.response.meta.path)
    } else {
      alert('Nothing to follow')
    }
  },

  // custom function when api request is done
  done(func) {
    if (typeof func == 'string') {
      if (func[0] == '#') Pjax.refresh(func)
      else Pjax.load(func)
    } else {
      func(this.response)
    }
    return this
  },

  // execute on error (suppressed while silent)
  error(err) {
    if (!this.is_silent) Info.api(this.response)
    return this
  },

  // force silence (default), suppressing error info too
  silent() {
    this.is_silent = true
    return this
  },

  // save silently and flash the top progress bar (see dollar_top_bar_info.js)
  topInfo() {
    this.silent()
    $.topBarInfo()
    return this
  },

  // show notification and un-silence the error path
  info() {
    this.is_silent = false
    if (!this.info_done) Info.api(this.response)
    this.info_done = true
  }
})

$.api = window.Api = (path, opts = {}) => {
  if (typeof path != 'string') {
    const form = $(path)
    path = form.attr('action')
    opts = form.serialize()
  }

  if (path.indexOf('/api/') != 0) path = `/api/${path}`
  const apiResponse = new ApiResponse()

  const execHash = {}
  const execOpts = {}
  apiMethods().forEach(m => {
    execHash[m] = args => {
      execOpts[m] = args
      return execHash
    }
  })

  $.ajax({
    type: 'POST',
    url: path,
    data: opts,
    complete: r => {
      apiResponse.onRequestDone(r, execOpts)
    },
    headers: window.Intl ? { 'x-tz-name': Intl.DateTimeFormat().resolvedOptions().timeZone } : {}
  })

  return execHash
}

// bind a record to its api path; returns the SAME object with non-enumerable
// helpers, so it stays clean in Object.keys/JSON but gains chainable api calls.
// path is prefixed with /api unless it already starts with '/'.
//   const o = $.api.prepare('tasks/' + task.ref, task)
//   o.update({ name: 'x' }).done(fn)
//   o.destroy().follow('/tasks')
//   o.send('archive', { reason: 'y' })
$.api.prepare = (path, data = {}) => {
  if (path[0] != '/') path = `/api/${path}`
  const send = (method, opts = {}) => Api(`${path}/${method}`, opts)
  Object.defineProperties(data, {
    update: { value: opts => send('update', opts) },
    destroy: { value: () => send('destroy') },
    send: { value: send }
  })
  return data
}
