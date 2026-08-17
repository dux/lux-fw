// ApiForm - submits a .lux-form to a /api/ endpoint, then runs a named "done"
// handler. Ported from api_form.coffee; Info.* is now Toast.*, errors surface as
// toasts. Lives as plain JS (not inside sys-form.fez) so server-rendered forms can
// use it without the component; the bundle loads it after _dollar.js.

const $ = window.$
const onHandler = {}

// Events a form only receives if it opts in. Unlike the named done-handlers, a
// missing handler here is the normal case and must not raise a toast.
const OPTIONAL_EVENTS = new Set(['progress', 'phase'])

class ApiForm {
  static bind(form, opts) { return new ApiForm($(form).closest('form')[0], opts) }
  static on(name, func) { onHandler[name] = func }
  static submit(el, opts) {
    const form = el.closest('form')
    form.setAttribute('onsubmit', 'return false')
    new ApiForm(form, opts)
    return false
  }

  // preview a picked image next to its input without submitting; pair with a real submit button
  static processFile(input) {
    const file = input.files && input.files[0]
    if (!file || !file.type.startsWith('image/')) return

    let img = input._preview
    if (!img) {
      img = document.createElement('img')
      img.style.cssText = 'display:block; margin-top:10px; width:100px; height:100px; border-radius:0.375rem; object-fit:cover;'
      // inside the row so it hugs the input; the row's own margin handles the gap below
      const row = input.closest('.form-row')
      if (row) row.appendChild(img)
      else input.after(img)
      input._preview = img
    }

    if (img.src) URL.revokeObjectURL(img.src)
    img.src = URL.createObjectURL(file)
  }

  // payload overrides the first argument for events that carry their own data
  // (progress); named done-handlers keep receiving the parsed response.
  call(name, payload) {
    const func = onHandler[name]
    if (func) func.apply(this, [payload === undefined ? this.response : payload, this.opts, this.data, this.form])
    else if (!OPTIONAL_EVENTS.has(name)) Toast.error(`Form handler [${name}] not found.`)
  }

  constructor(form, opts) {
    this.opts = opts
    this.form = $(form)
    this.response = null
    this.action = this.form.attr('action')

    this.call('before')

    if (this.action.indexOf('/api/') == -1) { alert('API target not found'); return }

    // convert files to blobs
    const formData = new FormData(form)
    form.querySelectorAll('input[type=file]').forEach(el => {
      const file = el.files[0]
      if (file) formData.append(el.name, new Blob([file], { type: file.type }), file.name)
    })

    // data-upload-url: send the file straight to object storage first and post
    // only its key, so a large upload never occupies a request.
    const uploadUrl = this.form.data('uploadUrl')

    if (uploadUrl) this.uploadThenPost(uploadUrl, form, formData)
    else this.post(formData)
  }

  // Reports byte progress; free on every XHR, so a form opts in just by
  // defining a 'progress' handler or a [data-progress] element.
  trackProgress(xhr) {
    xhr.upload.onprogress = e => {
      if (!e.lengthComputable) return
      this.call('progress', {
        loaded: e.loaded,
        total: e.total,
        percent: Math.round(e.loaded / e.total * 100),
      })
    }
  }

  // presign -> PUT the file to the returned URL -> post the key instead of the
  // file. The storage host is not our origin, so it needs a CORS rule for PUT.
  uploadThenPost(uploadUrl, form, formData) {
    const input = form.querySelector('input[type=file]')
    const file = input?.files[0]
    if (!file) return this.post(formData)

    const field = this.form.data('uploadField') || 'key'

    this.call('phase', 'presign')

    const presign = new FormData()
    for (const [k, v] of formData.entries()) if (!(v instanceof Blob)) presign.append(k, v)
    presign.append('filename', file.name)

    const ask = new XMLHttpRequest()
    ask.open('POST', uploadUrl, true)

    ask.onload = () => {
      let response
      try { response = JSON.parse(ask.responseText) }
      catch (_) { return this.uploadFailed('Upload could not be prepared') }

      if (ask.status != 200 || response.error) {
        // Surface the server's own message - it knows why it said no.
        this.response = response
        this.call('after')
        return this.call('error')
      }

      this.call('phase', 'upload')

      const put = new XMLHttpRequest()
      put.open('PUT', response.data.put_url, true)
      this.trackProgress(put)

      put.onload = () => {
        if (put.status < 200 || put.status > 299) {
          return this.uploadFailed(`Upload failed (${put.status})`)
        }

        this.call('phase', 'post')

        formData.delete(input.name)
        formData.append(field, response.data.key)
        this.post(formData)
      }

      put.onerror = () => this.uploadFailed('Upload blocked - check storage CORS')
      put.send(file)
    }

    ask.onerror = () => this.uploadFailed('Upload could not be prepared')
    ask.send(presign)
  }

  uploadFailed(text) {
    this.call('after')
    Toast.error(text)
  }

  post(formData) {
    const xhr = new XMLHttpRequest()
    xhr.open('POST', this.action, true)
    if (window.Intl) xhr.setRequestHeader('x-tz-name', Intl.DateTimeFormat().resolvedOptions().timeZone)

    this.trackProgress(xhr)

    xhr.onload = () => {
      if (this.rawResponse = xhr.responseText) {
        this.response = JSON.parse(xhr.responseText)
      } else {
        Toast.error('Empty response from server - network error?')
        return
      }

      this.call('after')

      if (!(this.form.attr('silent') || this.form.attr('data-silent'))) Toast.api(this.response)

      if (xhr.status == 200 && !this.response.error) {
        let func = this.form.data('done') || 'refresh'

        if (func[0] == '/') {
          // done is a path: swap REF for the created/updated ref, then navigate
          const ref = this.response.meta.ref || this.response.data.ref
          Pjax.load(func.replaceAll('REF', ref))
          return
        } else if (func[0] == '#') {
          this.opts = func
          func = 'refresh'
        } else if (func.includes('=>')) {
          func = new Function(`return ${func}`)
          func(this.response, this.opts)(this.response, this.opts)
          return
        }

        this.data = Object.fromEntries(formData.entries())
        this.call(func)
      } else {
        this.call('error')
      }
    }

    xhr.send(formData)
  }
}

window.ApiForm = ApiForm

// handlers - bound to the ApiForm instance via call(), so use function() not arrows

// before submit: disable the submit button and stash a restore fn
ApiForm.on('before', function () {
  const button = this.form.find('button[type=submit]')
  if (!button[0]) return
  const text = button.html()
  button.html(text + '&hellip;')
  button.prop('disabled', true)
  this.disable_button = () => { button.prop('disabled', false); button.html(text) }
})

// upload progress: fill a [data-progress] bar if the form has one, otherwise
// count up on the submit button, whose label the 'before' handler already owns.
ApiForm.on('progress', function (progress) {
  const bar = this.form.find('[data-progress]')[0]

  if (bar) {
    bar.style.width = `${progress.percent}%`
    bar.setAttribute('aria-valuenow', progress.percent)
    return
  }

  const button = this.form.find('button[type=submit]')[0]
  if (button && progress.percent < 100) button.innerHTML = `${progress.percent}%&hellip;`
})

ApiForm.on('after', function () {
  if (this.disable_button) this.disable_button()
  if (this.response?.error) return
  // swap in a success block if the form provided one
  const success = this.form.find('div.success')[0]
  if (success) this.form.html(success.innerHTML)
})

// show and hide validation errors on submit
ApiForm.on('error', function (response) {
  this.form.find('.error-message').remove()

  const errors = this.form.find('.errors')
  errors.html('')

  if (!response.error) return

  const details = response.error.messages.join(', ') || 'Unknown error, please <a href="/contact">contact</a> support and describe what are you triging to do.'
  const model = this.form.data('model')

  if (errors[0]) {
    errors.html(`<ui-info type="error"><h3>Form submit error</h3><p>${details}</p></ui-info>`)
  } else if (model) {
    if (response.error.details) {
      for (const k in response.error.details) {
        const v = response.error.details[k]
        let field = this.form.find(`*[name='${model}[${k}]']`)
        if (!field[0]) field = this.form.find(`*[name='${k}']`)

        if (field[0]) {
          field.parents('.form-row').addClass('error')
          field.after(`<div class='error-message' onclick='$(this).remove()'>${v}</div>`)
        } else {
          Toast.error(v)
        }
      }
    } else {
      Toast.error(details)
    }
  } else {
    Toast.error(details)
  }
})

// default - reload via Pjax; close the topmost dialog first so a form opened in a
// modal (e.g. the new-document dialog) dismisses itself on success
ApiForm.on('refresh', function (response, path) {
  path = path || ''
  if (path[0] == '/') {
    const ref = response.meta.ref || response.data.ref
    path = path.replaceAll('REF', ref)
  }
  if (window.Dialog?.isOpen()) Dialog.close()
  Pjax.refresh(path)
})

// done: :stream - the request only queued the work, so keep the dialog open and
// hand over to a <stream-box> that reports the rest. The response names the
// channel; the box refreshes the page itself when the run ends.
ApiForm.on('stream', function (response) {
  this.form.hide()

  // The panel is a sibling of the form, not a child - walk up to the nearest
  // ancestor that contains one, so the markup can nest it however it likes.
  let panel = null
  for (let node = this.form[0]; node && !panel; node = node.parentElement) {
    panel = node.querySelector('[data-stream-log]')
  }
  if (panel) panel.style.display = ''

  const channel = response.data?.channel
  if (!channel) return Toast.error('No stream channel in API response')
  if (!window.Lux?.subscribe) return Toast.error('Lux.subscribe missing - is shared/lux_core.js loaded?')

  // The box renders the log; this only watches for the terminal frame so the
  // page picks up whatever the job created.
  //
  // A terminal frame carrying ok: false means the run failed: leave the dialog
  // and its log on screen, because closing them would take the only report of
  // what went wrong with them.
  const stop = () => {
    Lux.unsubscribe(channel, onDone)
    Lux.offConnectionChange(onState)
  }

  const onDone = msg => {
    if (msg.type != 'done') return
    stop()
    if (msg.ok === false) return
    if (window.Dialog?.isOpen()) Dialog.close()
    Pjax.refresh()
  }

  // Nothing is replayed, so a frame sent while the connection was down is gone
  // for good - including the terminal one, which would otherwise leave this
  // dialog waiting forever on a run that already finished. We cannot tell a
  // finished run from a still-running one, so report the gap and stop watching
  // rather than hang silently.
  //
  // onConnectionChange fires immediately with the current state, which is
  // 'closed' until the socket opens - so only count a close as a drop once we
  // have actually been open.
  let wasOpen = false
  let dropped = false

  const onState = state => {
    if (state != 'open') return (dropped = wasOpen)

    if (!dropped) return (wasOpen = true)

    stop()
    Toast.warning('Connection dropped - the result may be incomplete. Refresh to check.')
  }

  Lux.subscribe(channel, onDone)
  Lux.onConnectionChange(onState)
})

ApiForm.on('edit', function (data) {
  const path = data.meta.path || Toast.error('No path in API response')
  Pjax.load(path + '/edit')
})

ApiForm.on('follow', function (data) {
  const path = data.path || this.response.meta.path || Toast.error('No path in API response')
  Pjax.load(path)
})

// bound once: any .lux-form posting to /api/ is handled here
document.addEventListener('submit', e => {
  const form = e.target.closest('.lux-form')
  if (!form) return
  if (!form.action?.includes('/api/')) return
  e.preventDefault()
  new ApiForm(form)
})
