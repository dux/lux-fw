// thin wrapper over $.ajax POST to /api/*, returning a chainable response handler.
// silent by default for success; a server error response always surfaces as a toast.
//   Api(path, opts)                    silent on success, but shows server errors
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
      document.dispatchEvent(new CustomEvent('api:response', {
        detail: { path: this.path, response: this.response }
      }))
      for (const m of Object.keys(execHash)) this[m](execHash[m])
    } else {
      alert('API strange error')
    }
  }
}

$.apiResponse = ApiResponse

// apps override or add chainable response methods to match their own stack
// (Dialog / Fez.load / Info, etc.); methods should return `this` to stay chainable.
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
      Fez.refresh(what) // page, dialog, smart, all
    }
    return this
  },

  // reload page and scroll to top
  reload() {
    Fez.refresh(null, { scroll: true })
    return this
  },

  // follow link from meta
  follow(arg) {
    let header_location
    if (arg) {
      // Api('posts/create', name: 'New post').follow('/admin/posts/show/ulid:{ulid}')
      const path = arg.replace(/\{(\w+)\}/g, (_, r1) => this.data[r1])
      Fez.load(path)
    } else if ((header_location = this.api_response.getResponseHeader('location'))) {
      Fez.load(header_location)
    } else if (location.pathname.includes('/admin/')) {
      const base = location.pathname.split('/')[2]
      Fez.load(`/admin/${base}/${this.data.ref}`)
    } else if (this.response.meta.path) {
      Fez.load(this.response.meta.path)
    } else {
      alert('Nothing to follow')
    }
  },

  // custom function when api request is done
  done(func) {
    if (typeof func == 'string') {
      if (func[0] == '#') Fez.refresh(func)
      else Fez.load(func)
    } else {
      func(this.response)
    }
    return this
  },

  // execute on error; a server error response always surfaces, even when silent.
  // callers that want to handle errors themselves pass a custom .error(fn).
  error(err) {
    Info.api(this.response)
    return this
  },

  // force silence (default): suppresses success info, but not server errors
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
  apiResponse.path = path

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

// Model handles, one per model API, from Lux.models (app/assets/lux_models.tmp.js,
// generated from ModelApi.client_index). Every call returns the Api() chain.
//   app.m.user(ref).update({ name: 'x' }).done(fn)   member actions on the handle
//   app.m.user(record).destroy().follow('/users')    anything with .ref works
//   app.m.user.create({ email: 'a@b.c' }).info()     collection actions on the factory
// Built on first access, so the index may load before or after this file.
// app.m has no setter: an app exporting window.app.m fails loudly instead of
// replacing the handles.
const apiAction = (path, name) => opts => Api(`${path}/${name}`, opts)

const buildModels = () => {
  const out = {}
  for (const [key, m] of Object.entries(window.Lux?.models || {})) {
    const factory = ref => {
      ref = ref?.ref ?? ref
      if (!ref) throw new Error(`app.m.${key}(ref): ref is required`)
      const handle = { ref }
      m.member.forEach(name => handle[name] = apiAction(`${m.path}/${ref}`, name))
      return handle
    }
    // defineProperty, a collection action may be called `name` or `length`
    m.collection.forEach(name => Object.defineProperty(factory, name, { value: apiAction(m.path, name) }))
    out[key] = factory
  }
  return Object.freeze(out)
}

let models
Object.defineProperty(window.app ||= {}, 'm', { get: () => models ||= buildModels(), enumerable: true, configurable: true })
