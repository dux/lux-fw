// arrow-key list navigation driven by a [data-keynav] attribute.
//   <p data-keynav href="/foo">...</p>
// ArrowUp/ArrowDown move a `.selected` highlight between visible
// [data-keynav] nodes; Enter follows the node's href (via Pjax) or clicks it.
// the selection lives in the DOM (the `.selected` class), so it survives
// re-renders and ajax-injected results without any per-view wiring.
const $ = window.$

// live, visible candidates only (offsetParent is null for display:none nodes)
const items = () => [...document.querySelectorAll('[data-keynav]')].filter(n => n.offsetParent)

$(document).on('keydown', e => {
  if (!['ArrowDown', 'ArrowUp', 'Enter'].includes(e.key)) return

  const nodes = items()
  if (!nodes.length) return

  const current = nodes.find(n => n.classList.contains('selected'))

  if (e.key == 'Enter') {
    if (!current) return
    e.preventDefault()
    const href = current.getAttribute('href')
    href ? Pjax.load(href) : current.click()
    return
  }

  // arrows drive the list even while a search input is focused
  e.preventDefault()
  let i = nodes.indexOf(current)
  i = e.key == 'ArrowDown' ? (i + 1) % nodes.length : (i - 1 + nodes.length) % nodes.length

  $('.selected').removeClass('selected')
  $(nodes[i]).addClass('selected')
  nodes[i].scrollIntoView({ block: 'nearest' })
})
