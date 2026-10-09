// top-of-page save indicator: a 3px bar fills across the viewport, then removes
// itself. Use after an api write to confirm the save without a toast.
//   $.topBarInfo()                       standalone
//   Api('post/update', d).topInfo()      via the api chain (silent + topBarInfo)

const $ = window.$

const MARKUP = `<div id="loader-bar">
  <style>
    #loader-bar .bar {
      position: fixed;
      top: 0;
      left: 0;
      width: 0;
      height: 3px;
      background-color: #8198cd;
      animation: loader-bar-fill 0.5s cubic-bezier(0.23, 1, 0.32, 1) forwards;
    }
    @keyframes loader-bar-fill {
      0%   { width: 0; }
      60%  { width: 50%; }
      100% { width: 100%; }
    }
  </style>
  <div class="bar"></div>
</div>`

$.topBarInfo = () => {
  $('#loader-bar').remove() // drop any in-flight bar so a rapid save restarts it
  $(document.body).append(MARKUP)
  $.delay(500).then(() => $('#loader-bar').remove())
}
