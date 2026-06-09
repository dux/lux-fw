// ApiForm - submits a .lux-form to a /api/ endpoint, then runs a named "done"
// handler. Ported from api_form.coffee; Info.* is now Toast.*, errors surface as
// toasts. Lives as plain JS (not inside sys-form.fez) so server-rendered forms can
// use it without the component; the bundle loads it after _dollar.js.

const $ = window.$
const onHandler = {}

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

  call(name) {
    const func = onHandler[name]
    if (func) func.apply(this, [this.response, this.opts, this.data, this.form])
    else Toast.error(`Form handler [${name}] not found.`)
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

    const xhr = new XMLHttpRequest()
    xhr.open('POST', this.action, true)
    if (window.Intl) xhr.setRequestHeader('x-tz-name', Intl.DateTimeFormat().resolvedOptions().timeZone)

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

// default - reload via Pjax
ApiForm.on('refresh', function (response, path) {
  path = path || ''
  if (path[0] == '/') {
    const ref = response.meta.ref || response.data.ref
    path = path.replaceAll('REF', ref)
  }
  Pjax.refresh(path)
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
