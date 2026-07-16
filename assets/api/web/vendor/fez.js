(()=>{var Ge=Object.defineProperty;var Ue=(e,t)=>()=>(e&&(t=e(e=0)),t);var Ve=(e,t)=>{for(var n in t)Ge(e,n,{get:t[n],enumerable:!0})};var Be={};Ve(Be,{loadDefaults:()=>He});var He,We=Ue(()=>{He=()=>{Fez("fez-component",class{init(e){let t=document.createElement(e.name);for(t.props=e.props||e["data-props"]||e;this.root.firstChild;)this.root.parentNode.insertBefore(this.root.lastChild,t.nextSibling);this.root.innerHTML="",this.root.appendChild(t)}}),Fez("fez-include",class{init(e){Fez.fetch(e.src,t=>{let n=Fez.domRoot(t);Fez.head(n),this.root.innerHTML=n.innerHTML})}}),Fez("fez-if",class{init(e){new Function(`return (${e.if||e.test})`)()||this.root.remove()}}),Fez("fez-demo-nav",class{init(){this.state.items=[],this.state.activeIndex=-1,this.state.markerTop=0,this.state.markerHeight=0,this.state.open=!1,this.state.loaded=!1,this.state.selectedName=""}onMount(){this.setTimeout(()=>this.loadComponents(),1e3),typeof window<"u"&&window.addEventListener&&(this.on("scroll",this.updateActive,{throttle:50}),this.on("resize",this.sync,{throttle:100}),this.on("hashchange",this.syncToHash)),this.on(this.root,"click",this.handleClick)}onRefresh(){this.setTimeout(()=>this.updateMarker(),0)}loadComponents(){let e=this.loadedComponents();if(!e.length){this.setTimeout(()=>this.loadComponents(),250);return}this.state.items=e,this.state.loaded=!0,this.setTimeout(()=>this.syncToHash()||this.sync(),0)}loadedComponents(){let e=Fez.index.withDemo().sort(),t=e.filter(n=>document.getElementById(this.sectionId(n)));return t.length?t:e}sectionId(e){return`fez-demo-${String(e).replace(/[^a-z0-9_-]/gi,"-")}`}sync(){this.updateActive(),this.updateMarker()}toggle(){this.state.open=!this.state.open,this.state.open&&this.setTimeout(()=>this.sync(),0)}syncToHash(){if(!window.location.hash)return this.state.selectedName="",this.state.activeIndex=-1,!1;let e=window.location.hash.slice(1),t=this.state.items.findIndex(n=>this.sectionId(n)===e);return t<0?!1:(this.state.activeIndex=t,this.state.selectedName=this.state.items[t],this.scrollToComponent(this.state.items[t]),!0)}handleClick(e){let t=e.target?.closest?.(".fez-demo-nav-link");if(!t)return;let n=Number(t.dataset.index);Number.isFinite(n)&&(this.state.activeIndex=n,this.state.selectedName=this.state.items[n]||"",this.setTimeout(()=>this.scrollToComponent(this.state.items[n]),0)),this.state.open=!1,this.setTimeout(()=>this.sync(),0)}clearSelection(e){e?.preventDefault?.(),e?.stopPropagation?.(),this.state.selectedName="",this.state.open=!1,this.setTimeout(()=>{let t=this.find(".fez-demo-nav-current");t&&(t.textContent="quick select")},0),this.setTimeout(()=>this.sync(),0),window.history?.replaceState&&window.history.replaceState(null,"",window.location.pathname+window.location.search)}scrollToComponent(e){let t=document.getElementById(this.sectionId(e));if(!t)return;t.scrollIntoView({behavior:"auto",block:"start"}),window.scrollBy(0,-12),this.state.open=!1,this.state.selectedName=e;let n=this.state.items.indexOf(e);n>=0&&(this.state.activeIndex=n),this.updateMarker(),window.history?.replaceState&&window.history.replaceState(null,"",`#${this.sectionId(e)}`)}updateActive(){let e=this.state.items;if(!e.length)return;if(!this.state.selectedName&&!window.location.hash&&window.scrollY<20){this.state.activeIndex=-1,this.updateMarker(-1);return}let t=window.innerHeight||document.documentElement?.clientHeight||800,n=Math.min(t*.35,260),i=this.state.activeIndex;e.forEach((s,r)=>{let o=document.getElementById(this.sectionId(s));o?.getBoundingClientRect&&o.getBoundingClientRect().top<=n&&(i=r)}),this.state.activeIndex!==i&&(this.state.activeIndex=i),this.updateMarker(i)}updateMarker(e=this.state.activeIndex){if(e<0){this.state.markerTop!==0&&(this.state.markerTop=0),this.state.markerHeight!==0&&(this.state.markerHeight=0);return}let t=this.find(".fez-demo-nav-list"),n=this.find(`[data-index="${e}"]`);if(!t?.getBoundingClientRect||!n?.getBoundingClientRect)return;let i=t.getBoundingClientRect(),s=n.getBoundingClientRect(),r=Math.round(s.top-i.top),o=Math.round(s.height);this.state.markerTop!==r&&(this.state.markerTop=r),this.state.markerHeight!==o&&(this.state.markerHeight=o)}CSS(){return`.fez-demo-side-nav {
        position: fixed;
        top: 10px;
        left: 12px;
        z-index: 1000;
        width: min(340px, calc(100vw - 32px));
        text-align: left;
        transform: none;
      }
      .fez-demo-nav-control {
        display: flex;
        align-items: center;
        width: 100%;
        min-height: 46px;
        margin: 0 auto;
        border: 1px solid #dedede;
        border-radius: 999px;
        background: #fff;
        color: #20242c;
        box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
      }
      .fez-demo-nav-toggle {
        display: flex;
        align-items: center;
        justify-content: flex-start;
        flex: 1 1 auto;
        gap: 10px;
        min-width: 0;
        min-height: 44px;
        padding: 6px 10px 6px 7px;
        border: 0;
        border-radius: 999px;
        background: transparent;
        color: #20242c;
        font: inherit;
        line-height: 1;
        cursor: pointer;
      }
      .fez-demo-nav-icon {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 auto;
        width: 32px;
        height: 32px;
        border-radius: 999px;
        background: #20242c;
        color: #fff;
        font-size: 15px;
        font-weight: 800;
      }
      .fez-demo-nav-current {
        flex: 1 1 auto;
        min-width: 0;
        overflow: hidden;
        color: #242424;
        font-size: 15px;
        font-weight: 650;
        line-height: 1.2;
        text-align: left;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .fez-demo-nav-current.placeholder {
        color: #9a9a9a;
        font-weight: 500;
      }
      .fez-demo-nav-clear {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 auto;
        width: 32px;
        height: 32px;
        margin-right: 7px;
        border: 0;
        border-radius: 999px;
        background: transparent;
        color: #8a8a8a;
        font: inherit;
        font-size: 20px;
        line-height: 1;
        cursor: pointer;
      }
      .fez-demo-nav-clear:hover {
        background: #f0f0f0;
        color: #222;
      }
      .fez-demo-nav-panel {
        box-sizing: border-box;
        height: calc(100vh - 76px);
        max-height: calc(100vh - 76px);
        overflow: auto;
        margin-top: 10px;
        padding: 14px 16px 14px 14px;
        border: 1px solid #e3e3e3;
        border-radius: 10px;
        background: #fff;
        box-shadow: 0 16px 42px rgba(0, 0, 0, 0.16);
        animation: fezDemoNavPop 160ms ease-out;
      }
      @keyframes fezDemoNavPop {
        from {
          opacity: 0;
          transform: translateY(-8px);
        }
        to {
          opacity: 1;
          transform: translateY(0);
        }
      }
      .fez-demo-nav-list {
        position: relative;
        display: flex;
        flex-direction: column;
        gap: 0;
        margin: 0;
        padding: 0 0 0 3px;
        border-left: 4px solid #e7e7e7;
      }
      .fez-demo-nav-marker {
        position: absolute;
        left: -4px;
        top: 0;
        width: 4px;
        height: var(--marker-height, 40px);
        background: #222;
        transform: translateY(var(--marker-top, 0px));
        transition: transform 180ms ease, height 180ms ease;
      }
      .fez-demo-nav-link {
        display: block;
        padding: 9px 0 9px 28px;
        color: #8f8f8f;
        font-size: 15px;
        line-height: 1.35;
        text-decoration: none;
        overflow-wrap: anywhere;
        transition: color 160ms ease, font-weight 160ms ease;
      }
      .fez-demo-nav-link:hover,
      .fez-demo-nav-link.active {
        color: #242424;
      }
      .fez-demo-nav-link.active {
        font-weight: 650;
      }`}HTML(){return`<nav class="fez-demo-side-nav" aria-label="Demo components">
        <div class="fez-demo-nav-control">
          <button
            class="fez-demo-nav-toggle"
            aria-label="Components"
            aria-expanded={state.open ? 'true' : 'false'}
            onclick="fez.toggle()"
          >
            <span class="fez-demo-nav-icon" aria-hidden="true">F</span>
            <span class="fez-demo-nav-current {state.selectedName ? '' : 'placeholder'}">{state.selectedName ? state.selectedName : 'quick select'}</span>
          </button>
          {#if state.selectedName}
            <button class="fez-demo-nav-clear" aria-label="Clear selection" onclick="fez.clearSelection(event)">X</button>
          {/if}
        </div>
        {#if state.open}
          <div class="fez-demo-nav-panel">
            <div
              class="fez-demo-nav-list"
              style="--marker-top: {state.markerTop}px; --marker-height: {state.markerHeight}px;"
            >
              <span class="fez-demo-nav-marker" aria-hidden="true"></span>
              {#each state.items as name, index}
                <a
                  class="fez-demo-nav-link {state.activeIndex === index ? 'active' : ''}"
                  href="#{fez.sectionId(name)}"
                  data-index={index}
                  aria-current={state.activeIndex === index && state.activeIndex >= 0 ? 'page' : 'false'}
                >{name}</a>
              {/each}
            </div>
          </div>
        {/if}
      </nav>`}}),Fez("fez-demo",class{init(e){this.state.ready=!1,this.state.components=[],this.state.undocumented=[],this.state.filtered=!1,this.state.showAllUrl="",this.state.allComponentsUrl="";let t=new URLSearchParams(window.location.search),n=e.name||t.get("fez"),i=new URL(window.location.href);i.searchParams.delete("fez"),this.state.allComponentsUrl=i.pathname+i.search+i.hash,t.get("fez")&&(this.state.showAllUrl=this.state.allComponentsUrl,this.state.filtered=!0);let s=l=>!l.startsWith("fez-"),r=0,o=0,a=()=>{if(n)Fez.index[n]?.class?(this.state.components=Fez.index[n]?.demo?[n]:[],this.state.ready=!0):setTimeout(a,100);else{let l=Fez.index.names().filter(s);l.length>0&&l.length===r?o++:o=0,r=l.length,o>=2?(this.state.components=Fez.index.withDemo().filter(s).sort(),this.state.undocumented=l.filter(d=>!Fez.index[d]?.demo).sort(),this.state.ready=!0):setTimeout(a,100)}};a()}showHtml(e){let t=Fez.index[e]?.demo||"No demo HTML";Fez.log("Demo HTML: "+e+`

`+t)}showFez(e){Fez.log("Fez source: "+e+`

`+(Fez.index[e]?.source||"Made via raw Fez API, source not available"))}openSingle(e){let t=new URL(window.location.href);t.searchParams.set("fez",e),window.location.href=t.toString()}openCodePen(e){let t=Fez.index[e]?.demo||"",n=Fez.index[e]?.source||"",i=[`<link rel="stylesheet" href="//cdn.simplecss.org/simple.css" />
<script src="//dux.github.io/fez/dist/fez.js"><\/script>`,`<!-- FEZ code start -->
<xmp fez="${e}">
${n}
</xmp>
<!-- FEZ code end -->`,`<!-- HTML code start -->
${t}
<!-- HTML code end -->`],s={title:"Fez component - "+e,html:i.join(`

`),css:"body { padding-top: 50px; }",js:"",editors:"100"},r=document.createElement("form");r.method="POST",r.action="https://codepen.io/pen/define",r.target="_blank";let o=document.createElement("input");o.type="hidden",o.name="data",o.value=JSON.stringify(s),r.appendChild(o),document.body.appendChild(r),r.submit(),document.body.removeChild(r)}renderDemo(e){let t=e.dataset.name;Fez.index.apply(t,e)}renderInfo(e){let t=e.dataset.name,n=Fez.index.get(t);n.info?e.innerHTML=n.info.innerHTML:e.innerHTML="<em>No info available</em>"}CSS(){return`:fez {
        display: block;
        font-family: system-ui, -apple-system, sans-serif;
        color: #1f2937;
        padding: 0 22px 40px;
        box-sizing: border-box;
      }
      .fez-demo-header {
        display: flex;
        align-items: center;
        justify-content: flex-start;
        padding: 24px 0 18px;
        margin: 0 auto;
        max-width: 1180px;
      }
      .fez-demo-brand {
        display: flex;
        align-items: baseline;
        gap: 12px;
        min-width: 0;
        text-decoration: none;
        color: inherit;
      }
      .fez-demo-logo {
        font-size: 22px;
        font-weight: 750;
        line-height: 1;
      }
      .fez-demo-subtitle {
        color: #6b7280;
        font-size: 14px;
        line-height: 1.3;
        white-space: nowrap;
      }
      .fez-demo-shell {
        display: block;
        max-width: 980px;
        margin: 0 auto;
      }
      .fez-demo-main {
        min-width: 0;
      }
      @media (max-width: 640px) {
        .fez-demo-header {
          padding-top: 16px;
        }
        .fez-demo-brand {
          flex-direction: column;
          gap: 4px;
        }
      }
      @media (max-width: 980px) {
        .fez-demo-shell {
          display: block;
        }
      }
      .fez-demo-item {
        margin-bottom: 40px;
        scroll-margin-top: 28px;
      }
      .fez-demo-anchor {
        display: block;
        height: 0;
        scroll-margin-top: 12px;
      }
      .fez-demo-title {
        display: flex;
        align-items: center;
        gap: 15px;
        font-size: 18px;
        font-weight: 600;
        margin: 0 0 25px 0;
        &::before {
          content: '';
          flex: 1;
          height: 1px;
          background: #ddd;
        }
        &::after {
          content: '';
          flex: 1;
          height: 1px;
          background: #ddd;
        }
        .fez-demo-show-all, .fez-demo-open-single {
          font-size: 14px;
          font-weight: normal;
          color: #666;
          text-decoration: none;
          cursor: pointer;
          &:hover { text-decoration: underline; }
        }
      }
      .fez-demo-cols {
        display: flex;
        gap: 40px;
        @media (max-width: 768px) {
          flex-direction: column;
          gap: 20px;
        }
      }
      .fez-demo-left, .fez-demo-right {
        flex: 1;
        min-width: 0;
        overflow: visible;
      }
      .fez-demo-content {
        min-height: 50px;
        text-align: left;
        h3, h4, h5 { margin: 16px 0 8px; }
        h3:first-child, h4:first-child, h5:first-child { margin-top: 0; }
      }
      .fez-demo-info {
        text-align: left;
        background: #fff;
        border: 1px solid #ddd;
        border-radius: 6px;
        padding: 20px;
        line-height: 1.6;
        ul { margin: 0; padding-left: 20px; }
        code { background: #e8e8e8; padding: 2px 5px; border-radius: 3px; font-size: 13px; }
      }
      .fez-demo-buttons {
        margin-top: 30px;
        display: flex;
        gap: 10px;
      }
      .fez-demo-undocumented {
        margin-top: 40px;
        padding-top: 20px;
        border-top: 1px solid #ddd;
        h3 { font-size: 16px; font-weight: 600; color: #6b7280; margin: 0 0 12px; }
        .fez-demo-undocumented-list { display: flex; flex-wrap: wrap; gap: 8px; }
      }
      .fez-demo-btn {
        padding: 8px 16px;
        border: 1px solid #ccc;
        background: #fff;
        color: #333;
        font: inherit;
        line-height: 1.2;
        border-radius: 4px;
        cursor: pointer;
        box-shadow: none;
        &:hover { background: #f0f0f0; color: #333; }
      }`}HTML(){return`{#if state.ready}
        <header class="fez-demo-header">
          <a class="fez-demo-brand" href="{state.allComponentsUrl}">
            <span class="fez-demo-logo">Fez</span>
            <span class="fez-demo-subtitle">Component demos</span>
          </a>
        </header>
        <div class="fez-demo-shell">
          <main class="fez-demo-main">
            {#each state.components as name}
              <div class="fez-demo-item" data-demo-name={name}>
                <a class="fez-demo-anchor" id="fez-demo-{name}" name="fez-demo-{name}" aria-hidden="true"></a>
                <h2 class="fez-demo-title">{name}{#if state.filtered} <a href="{state.showAllUrl}" class="fez-demo-show-all">show all</a>{:else} <a onclick="fez.openSingle('{name}')" class="fez-demo-open-single">open</a>{/if}</h2>
                <div class="fez-demo-cols">
                  <div class="fez-demo-left">
                    <div class="fez-demo-content" data-name={name} fez-use="renderDemo"></div>
                  </div>
                  <div class="fez-demo-right">
                    <div class="fez-demo-info" data-name={name} fez-use="renderInfo"></div>
                    <div class="fez-demo-buttons">
                      <button class="fez-demo-btn" onclick="fez.showHtml('{name}')">Demo HTML</button>
                      <button class="fez-demo-btn" onclick="fez.showFez('{name}')">Fez Component</button>
                      <button class="fez-demo-btn" onclick="fez.openCodePen('{name}')">CodePen</button>
                    </div>
                  </div>
                </div>
              </div>
            {/each}
            {#if state.undocumented.length}
              <div class="fez-demo-undocumented">
                <h3>Undocumented</h3>
                <div class="fez-demo-undocumented-list">
                  {#each state.undocumented as name}
                    <button class="fez-demo-btn" onclick="fez.showFez('{name}')">{name}</button>
                  {/each}
                </div>
              </div>
            {/if}
          </main>
        </div>
      {:else}
        <div style="text-align: center; color: #888;">Loading components...</div>
      {/if}`}})};typeof Fez<"u"&&Fez&&typeof document<"u"&&document.head&&He()});function H(e,t={},n){if(typeof t=="string"&&([t,n]=[n,t],t||={}),t instanceof Node&&(n=t,t={}),Array.isArray(e)&&(n=e,e="div"),(typeof t!="object"||Array.isArray(t))&&(n=t,t={}),e.includes(".")){let r=e.split(".");e=r.shift()||"div";let o=r.join(" ");t.class?t.class+=` ${o}`:t.class=o}let i=document.createElement(e),s=["checked","disabled","selected","readonly","required","hidden","multiple","autofocus"];for(let[r,o]of Object.entries(t))if(typeof o=="function")i[r]=o.bind(this);else if(s.includes(r))o&&i.setAttribute(r,r);else{let a=String(o).replaceAll("fez.",this.fezHtmlRoot);i.setAttribute(r,a)}if(n)if(Array.isArray(n))for(let r of n)i.appendChild(r);else n instanceof Node?i.appendChild(n):i.innerHTML=String(n);return i}var Ze=new Set(["console","window","document","Math","JSON","Date","Array","Object","String","Number","Boolean","parseInt","parseFloat","setTimeout","setInterval","clearTimeout","clearInterval","alert","confirm","prompt","fetch","event"]);function ie(e){return e.replace(/(?<![.\w])([a-zA-Z_$][a-zA-Z0-9_$]*)\s*\(/g,(t,n)=>Ze.has(n)?t:`fez.${n}(`)}function D(e){if(e.startsWith("[")){let i=e.match(/^\[([^\]]+)\](?:\s*,\s*(\w+))?$/);if(i)return{params:i[1].split(",").map(s=>s.trim()),indexParam:i[2]||null,isDestructured:!0}}let n=e.split(",").map(i=>i.trim());return n.length===2?{params:n,indexParam:null,isDestructured:!0}:{params:n,indexParam:null,isDestructured:!1}}function re(e){let t=D(e),n=[...t.params];return t.indexParam&&n.push(t.indexParam),t.params.length===1&&!n.includes("i")&&n.push("i"),n}function oe(e){let t=D(e);return t.isDestructured&&t.params.length===2?[t.params[0]]:t.isDestructured?t.params:t.params.length>=3?t.params.slice(0,-1):t.params.length===2?[t.params[0]]:t.params}function ae(e,t){let n=D(t);return n.isDestructured&&n.params.length===2?`Fez.toPairs(${e})`:n.isDestructured||n.params.length>=3?`((_c)=>Array.isArray(_c)?_c:(_c&&typeof _c==="object")?Object.entries(_c):[])(${e})`:`(${e}||[])`}function le(e){let t=D(e);if(t.isDestructured){let i="["+t.params.join(", ")+"]",s=t.indexParam||(t.params.includes("i")?"_i":"i");return i+", "+s}if(t.params.length>=3){let i=[...t.params],s=i.pop();return"["+i.join(", ")+"], "+s}if(t.params.length===2)return t.params.join(", ");let n=t.params[0]==="i"?"_i":"i";return t.params[0]+", "+n}function ce(e){return/^\s*(\([^)]*\)|[a-zA-Z_$][a-zA-Z0-9_$]*)\s*=>/.test(e)}function fe(e,t=[],n=[]){let i=e.match(/^\s*(?:\([^)]*\)|[a-zA-Z_$][a-zA-Z0-9_$]*)\s*=>\s*(.+)$/s);if(!i)return e;let s=i[1].trim(),o=e.match(/^\s*\(?\s*([a-zA-Z_$][a-zA-Z0-9_$]*)?\s*(?:,\s*[^)]+)?\)?\s*=>/)?.[1],a=o&&["e","event","ev"].includes(o);if(n.filter(d=>new RegExp(`\\b${d}\\b`).test(s)).length>0){if(a&&o!=="event"){let d=new RegExp(`\\b${o}\\b`,"g");s=s.replace(d,"event")}return s=ie(s),`\${'Fez(' + UID + ').fezGlobals.get(' + fez.fezGlobals.setHandler((event) => ${s}) + ')(event)'}`}if(a&&o!=="event"){let d=new RegExp(`\\b${o}\\b`,"g");s=s.replace(d,"event")}for(let d of t){let c=new RegExp(`(?<!\\$\\{)\\b${d}\\b(?![^{]*\\})`,"g");s=s.replace(c,`\${${d}}`)}return s=ie(s),s}function de(e,t){let n=0,i=t;for(;i<e.length;){let s=e[i];if(s==="{")n++;else if(s==="}"){if(n--,n===0)return{expression:e.slice(t+1,i),endIndex:i}}else if(s==='"'||s==="'"||s==="`"){let r=s;for(i++;i<e.length&&e[i]!==r;)e[i]==="\\"&&i++,i++}i++}throw new Error(`Unmatched brace at ${t}`)}function B(e,t){let n=t-1;for(;n>=0&&(e[n]==="{"||e[n]===" "||e[n]==="	");)n--;if(n>=0&&e[n]==="="){for(n--;n>=0&&(e[n]===" "||e[n]==="	");)n--;let i=n+1;for(;n>=0&&/[a-zA-Z0-9_:-]/.test(e[n]);)n--;let s=e.slice(n+1,i);if(s&&/^[a-zA-Z]/.test(s)&&(n<0||/\s/.test(e[n])))return s.toLowerCase()}return null}function ue(e,t){let n=B(e,t);return n&&/^on[a-z]+$/.test(n)?n:null}function W(e,t={}){let n=t.name||"unknown";try{e=e.replaceAll("&#x60;","`").replaceAll("&lt;","<").replaceAll("&gt;",">").replaceAll("&amp;","&"),e=e.replace(/\bfez:([a-z]+)=/gi,"fez-$1="),e=e.replace(/\bon([a-z]+)!=(["'])([\s\S]*?)\2/gi,(f,m,u,p)=>`on${m}=${u}fez.fezBang(event) && (${p})${u}`),e=e.replace(/<[a-z][a-z0-9-]*\b[^>]*>/gi,f=>{if(!/\bclass:[\w-]+=/.test(f))return f;let m=[];if(f=f.replace(/\s*\bclass:([\w-]+)=\{([^}]*)\}/g,(p,z,x)=>(m.push({name:z,expr:x}),"")),f=f.replace(/\s*\bclass:([\w-]+)="([^"]*)"/g,(p,z,x)=>(m.push({name:z,expr:x}),"")),!m.length)return f;let u=m.map(p=>` {(${p.expr}) ? '${p.name}' : ''}`).join("");return/\bclass="/.test(f)?f=f.replace(/class="([^"]*)"/,(p,z)=>`class="${z}${u}"`):f=f.replace(/(\s*\/?>)$/,` class="${u.trim()}"$1`),f});let i=e.match(/<([a-z]+-[a-z][a-z0-9-]*)\b[^>]*\bfez-keep=/);i&&console.error(`FEZ: fez:keep must be on plain HTML elements, not on fez components. Found on <${i[1]}> in <${n}>`);let s={};e=e.replace(/\{@block\s+(\w+)\}([\s\S]*?)\{\/block\}/g,(f,m,u)=>(s[m]=u,"")),e=e.replace(/\{@block:(\w+)\}/g,(f,m)=>s[m]||""),e=e.replace(/:(\w+)="([^"{}]+)"/g,(f,m,u)=>/^\d+$/.test(u.trim())?f:`:${m}={\`Fez(\${UID}).fezGlobals.delete(\${fez.fezGlobals.set(${u})})\`}`),e=e.replace(/<!--[\s\S]*?-->/g,""),e=e.replace(/>\s+</g,"><").trim(),e=e.replace(/<([a-z][a-z0-9]*-[a-z0-9-]*)((?:=>|[^>])*)>/gi,(f,m,u)=>u.trimEnd().endsWith("/")?`<${m}${u.replace(/\s*\/$/,"")}></${m}>`:f),e=e.replace(/<slot\s*\/>/gi,"<slot></slot>"),e=Ye(e);let r="",o=0,a=[],l=[],d=[],c=[],h=[],y=[],v=0;for(;o<e.length;){if(e[o]==="`"){for(r+="\\`",o++;o<e.length&&e[o]!=="`";)if(e[o]==="\\")r+="\\\\",o++,o<e.length&&(e[o]==="`"?r+="\\`":e[o]==="$"?r+="\\$":r+=e[o],o++);else if(e[o]==="$"&&e[o+1]==="{"){r+="\\${",o+=2;let f=1;for(;o<e.length&&f>0;)e[o]==="{"?f++:e[o]==="}"&&f--,f>0||e[o]!=="}"?e[o]==="`"?r+="\\`":e[o]==="\\"?r+="\\\\":r+=e[o]:r+="}",o++}else e[o]==="$"?r+="\\$":r+=e[o],o++;o<e.length&&(r+="\\`",o++);continue}if(e[o]==="\\"&&e[o+1]==="{"){r+="{",o+=2;continue}if(e[o]==="{"){let{expression:f,endIndex:m}=de(e,o),u=f.trim();if(/^(\w+|"\w+"|'\w+')\s*:/.test(u)){r+="{"+f+"}",o=m+1;continue}if(u.startsWith("#if ")){let p=u.slice(4);r+="${Fez.isTruthy("+p+") ? `",a.push(!1),h.push("if")}else if(u.startsWith("#unless ")){let p=u.slice(8);r+="${!Fez.isTruthy("+p+") ? `",a.push(!1),h.push("if")}else if(u===":else"||u==="else"){let p=h[h.length-1];if(p==="loop"){let z=c[c.length-1];z.hasElse=!0,r+='`).join("") : `'}else if(p==="if")r+="` : `",a[a.length-1]=!0;else throw new Error("{:else} without matching {#if}, {#unless}, {#each}, or {#for}")}else if(u.startsWith(":else if ")||u.startsWith("else if ")||u.startsWith("elsif ")||u.startsWith("elseif ")){let p=u.startsWith(":else if ")?u.slice(9):u.startsWith("else if ")?u.slice(8):u.startsWith("elseif ")?u.slice(7):u.slice(6);r+="` : Fez.isTruthy("+p+") ? `"}else if(u==="/if"||u==="/unless"){let p=a.pop();h.pop(),r+=p?"`}":"` : ``}"}else if(u.startsWith("#each ")||u.startsWith("#for ")){let p=u.startsWith("#each "),z,x;if(p){let _=u.slice(6),R=_.indexOf(" as ");z=_.slice(0,R).trim(),x=_.slice(R+4).trim()}else{let _=u.slice(5),R=_.indexOf(" in ");x=_.slice(0,R).trim(),z=_.slice(R+4).trim()}let A=ae(z,x),qe=le(x);l.push(re(x)),d.push(oe(x)),c.push({collectionExpr:A,hasElse:!1}),h.push("loop"),r+="${((_arr) => _arr.length ? _arr.map(("+qe+") => `"}else if(u==="/each"||u==="/for"){l.pop(),d.pop();let p=c.pop();h.pop(),p.hasElse?r+="`)("+p.collectionExpr+")}":r+='`).join("") : "")('+p.collectionExpr+")}"}else if(u.startsWith("#await ")){let p=u.slice(7).trim(),z=v++;y.push({awaitId:z,promiseExpr:p,hasThen:!1,hasCatch:!1,thenVar:"_value",catchVar:"_error"}),r+='${((_aw) => _aw.status === "pending" ? `'}else if(u.startsWith(":then")){let p=y[y.length-1];p&&(p.hasThen=!0,p.thenVar=u.slice(5).trim()||"_value",r+='` : _aw.status === "resolved" ? (('+p.thenVar+") => `")}else if(u.startsWith(":catch")){let p=y[y.length-1];p&&(p.hasCatch=!0,p.catchVar=u.slice(6).trim()||"_error",p.hasThen?r+='`)(_aw.value) : _aw.status === "rejected" ? (('+p.catchVar+") => `":r+='` : _aw.status === "rejected" ? (('+p.catchVar+") => `")}else if(u==="/await"){let p=y.pop();p&&(p.hasThen&&p.hasCatch?r+="`)(_aw.error) : ``)(Fez.fezAwait(fez, "+p.awaitId+", "+p.promiseExpr+"))}":p.hasThen?r+="`)(_aw.value) : ``)(Fez.fezAwait(fez, "+p.awaitId+", "+p.promiseExpr+"))}":p.hasCatch?r+="`)(_aw.error) : ``)(Fez.fezAwait(fez, "+p.awaitId+", "+p.promiseExpr+"))}":r+="` : ``)(Fez.fezAwait(fez, "+p.awaitId+", "+p.promiseExpr+"))}")}else if(u.startsWith("@html ")){let p=u.slice(6);r+="${"+p+"}"}else if(u.startsWith("@json ")){let p=u.slice(6);r+='${`<pre class="json">${Fez.htmlEscape(JSON.stringify('+p+", null, 2))}</pre>`}"}else if(ce(u))if(ue(e,o)){let z=l.flat(),x=d.flat(),A=fe(u,z,x);A=A.replace(/"/g,"&quot;"),r+='"'+A+'"'}else r+="${"+u+"}";else B(e,o)?r+='"${Fez.htmlEscape('+u+')}"':r+="${Fez.htmlEscape("+u+")}";o=m+1;continue}e[o]==="$"&&e[o+1]==="{"?r+="\\$":e[o]==="\\"?r+="\\\\":r+=e[o],o++}if(r=r.replace(/(<[a-z][a-z0-9-]*\s+)([^>]*?)(fez-this="([^"{}]+)")([^>]*?)>/gi,(f,m,u,p,z,x)=>{if(/\bid=/.test(u)||/\bid=/.test(x))return f;let A=z.replace(/[^a-zA-Z0-9]/g,"-");return`${m}${u}${p}${x} id="fez-\${UID}-${A}">`}),typeof Fez<"u"&&Fez.LOG){let f=r.match(/fez-this="[^"]*\{[^}]+\}[^"]*"/g);f&&console.warn(`Fez <${n}>: Dynamic fez-this values won't get auto-ID for DOM differ matching:`,f)}let w=`
      const fez = this;
      with (this) {
        return \`${r}\`
      }
    `,g=new Function(w);return f=>{try{return g.bind(f)()}catch(m){return console.error(`FEZ template runtime error in <${f.fezName||n}>:`,m.message),console.error("Template source:",r.substring(0,500)),""}}}catch(i){return console.error(`FEZ template compile error in <${n}>:`,i.message),console.error("Template:",e.substring(0,200)),()=>""}}function Xe(e){if(e.startsWith("#each ")){let t=e.slice(6),n=t.indexOf(" as ");if(n<0)return"i";let s=t.slice(n+4).trim().split(",").map(r=>r.trim());return s.length>=2?s[s.length-1]:"i"}if(e.startsWith("#for ")){let t=e.slice(5),n=t.indexOf(" in ");if(n<0)return"i";let s=t.slice(0,n).trim().split(",").map(r=>r.trim());return s.length>=3?s[s.length-1]:"i"}return"i"}function Je(e){let t="";if(e.startsWith("#each ")){let i=e.slice(6),s=i.indexOf(" as ");if(s<0)return"";t=i.slice(s+4).trim()}else if(e.startsWith("#for ")){let i=e.slice(5),s=i.indexOf(" in ");if(s<0)return"";t=i.slice(0,s).trim()}let n=t.replace(/^\[/,"").replace(/\]$/,"").split(",")[0].trim();return/^[A-Za-z_$][\w$]*$/.test(n)?n:""}function Ye(e){let t="",n=0,i=0,s=[];for(;n<e.length;){if(e[n]==="{"&&n+1<e.length&&/[#/:]/.test(e[n+1])){let r=n+1,o=1;for(;r<e.length;){if(e[r]==="{")o++;else if(e[r]==="}"&&(o--,o===0))break;r++}let a=e.slice(n+1,r).trim();if(a.startsWith("#if ")||a.startsWith("#unless "))s.push({type:"if"});else if(a.startsWith("#each ")||a.startsWith("#for "))s.push({type:"loop",indexVar:Xe(a),itemKeyVar:Je(a),inElse:!1});else if(a==="/if"||a==="/unless")s.length&&s.pop();else if(a==="/each"||a==="/for")s.length&&s.pop();else if(a===":else"||a==="else"||a.startsWith(":else if ")||a.startsWith("else if ")){let l=s[s.length-1];l&&l.type==="loop"&&(l.inElse=!0)}t+=e.slice(n,r+1),n=r+1;continue}if(e[n]==="<"&&n+1<e.length&&/[a-zA-Z]/.test(e[n+1])){let r=n+1;for(;r<e.length;){if(e[r]==='"'||e[r]==="'"){let c=e[r++];for(;r<e.length&&e[r]!==c;)r++}else if(e[r]==="{"){let c=1;for(r++;r<e.length&&c>0;)e[r]==="{"?c++:e[r]==="}"&&c--,r++;continue}else if(e[r]===">")break;r++}let o=e.slice(n,r+1);if(e[n+1]==="/"){t+=o,n=r+1;continue}if(/\bkey\s*=/.test(o)){t+=o,n=r+1;continue}let a=i++,l=s.filter(c=>c.type==="loop"&&!c.inElse),d;if(l.length>0){let c=l.reduce((y,v)=>(y[v.indexVar]=(y[v.indexVar]||0)+1,y),{}),h=l.map(y=>`-{${c[y.indexVar]>1&&y.itemKeyVar?y.itemKeyVar:y.indexVar}}`).join("");d=`${a}${h}`}else d=`${a}`;if(o.trimEnd().endsWith("/>")){let c=o.lastIndexOf("/");t+=o.slice(0,c)+` fez-key="${d}"/>`}else t+=o.slice(0,-1)+` fez-key="${d}">`;n=r+1;continue}t+=e[n],n++}return t}var I=new Map;function k(e,t={}){if(I.has(e))return I.get(e);let n=Qe(e,t);if(I.has(n)){let s=I.get(n);return I.set(e,s),s}let i=W(n,t);return I.set(n,i),n!==e&&I.set(e,i),i}function Qe(e,t={}){return et(e)?tt(e,t.name):e}function et(e){return e.includes("{{")&&e.includes("}}")||e.includes("[[")&&e.includes("]]")}function tt(e,t){return e=e.replaceAll("[[","{{").replaceAll("]]","}}"),e=e.replace(/\{\{block\s+(\w+)\s*\}\}/g,"{@block $1}"),e=e.replace(/\{\{\/block\}\}/g,"{/block}"),e=e.replace(/\{\{block:([\w\-]+)\s*\}\}/g,"{@block:$1}"),e=e.replace(/\{\{#?if\s+(.*?)\}\}/g,"{#if $1}"),e=e.replace(/\{\{\/if\}\}/g,"{/if}"),e=e.replace(/\{\{#?unless\s+(.*?)\}\}/g,"{#unless $1}"),e=e.replace(/\{\{\/unless\}\}/g,"{/unless}"),e=e.replace(/\{\{:?else\s+if\s+(.*?)\}\}/g,"{:else if $1}"),e=e.replace(/\{\{:?elsif\s+(.*?)\}\}/g,"{:else if $1}"),e=e.replace(/\{\{:?elseif\s+(.*?)\}\}/g,"{:else if $1}"),e=e.replace(/\{\{:?else\}\}/g,"{:else}"),e=e.replace(/\{\{#?for\s+(.*?)\}\}/g,"{#for $1}"),e=e.replace(/\{\{\/for\}\}/g,"{/for}"),e=e.replace(/\{\{#?each\s+(.*?)\}\}/g,"{#each $1}"),e=e.replace(/\{\{\/each\}\}/g,"{/each}"),e=e.replace(/\{\{#?(?:raw|html)\s+(.*?)\}\}/g,"{@html $1}"),e=e.replace(/\{\{json\s+(.*?)\}\}/g,"{@json $1}"),e=e.replace(/\{\{\s*(.*?)\s*\}\}/g,"{$1}"),t&&console.warn(`Fez component "${t}" uses old {{ ... }} notation, converting.`),e}var N=new Map,E={};function he(e,t,n){let i=null,s=null,r;typeof t=="function"?(r=e,n=t):(r=t,typeof e=="string"?i=e:s=e),N.has(r)||N.set(r,new Set);let o=N.get(r);for(let l of o)l.callback===n&&l.selector===i&&l.node===s&&o.delete(l);let a={selector:i,node:s,callback:n};return o.add(a),()=>o.delete(a)}function pe(e,...t){let n=N.get(e);if(n)for(let i of n){let s=null;if(i.selector){if(s=document.querySelector(i.selector),!s)continue}else if(i.node){if(!i.node.isConnected){n.delete(i);continue}s=i.node}try{i.callback.call(s,...t)}catch(r){console.error(`Fez pubsub error on "${e}":`,r)}}E[e]&&E[e].forEach(([i,s])=>{i.isConnected&&s.bind(i)(...t)})}function me(e,t,n){return E[t]||=[],E[t]=E[t].filter(([i])=>i.isConnected),E[t].push([e,n]),()=>{E[t]=E[t].filter(([i,s])=>!(i===e&&s===n))}}function ge(e,t,...n){let i=r=>{if(E[t]){let o=E[t].find(([a])=>a===r);if(o)return o[1].bind(r)(...n),!0}return!1};if(i(e))return!0;let s=e.root?.parentElement;for(;s;){if(s.fez&&i(s.fez))return!0;s=s.parentElement}return!1}var K=new Set(["resize","scroll","load","beforeunload","unload","pagehide","pageshow","hashchange","popstate","online","offline","message","storage","orientationchange","error"]),T=class{static nodeName="div";static getProps(t,n){let i={};if(t.props)return t.props;for(let s of t.attributes)i[s.name]=s.value;for(let[s,r]of Object.entries(i))if([":"].includes(s[0])){delete i[s];try{let o=new Function(`return (${r})`).bind(n)();i[s.replace(/^:/,"")]=o}catch(o){Fez.onError("attr",`<${t.tagName.toLowerCase()}> Error evaluating ${s}="${r}": ${o.message}`)}}if(i["data-props"]){let s=i["data-props"];if(typeof s=="object")return s;s[0]!="{"&&(s=decodeURIComponent(s));try{i=JSON.parse(s)}catch(r){Fez.onError("props",`<${t.tagName.toLowerCase()}> Invalid JSON in data-props: ${r.message}`)}}else if(i["data-json-template"]){let s=n.previousSibling?.textContent;if(s)try{i=JSON.parse(s),n.previousSibling.remove()}catch(r){Fez.onError("props",`<${t.tagName.toLowerCase()}> Invalid JSON in template: ${r.message}`)}}return i}static formData(t){let n=t.closest("form")||t.querySelector("form");if(!n)return Fez.consoleLog("No form found for formData()"),{};let i=new FormData(n),s={};return i.forEach((r,o)=>{s[o]=r}),s}constructor(){}n=H;fezBlocks={};local={};fezGlobals={_data:new Map,_counter:0,_handlerCounter:0,_handlerKeys:new Set,_nextHandlerKeys:null,set(t){let n=this._counter++;return this._data.set(n,t),n},setHandler(t){let n=`h${this._handlerCounter++}`;return this._data.set(n,t),this._nextHandlerKeys?.add(n),`'${n}'`},get(t){return this._data.get(t)},delete(t){let n=this._data.get(t);return this._data.delete(t),n},beginRender(){this._handlerCounter=0,this._nextHandlerKeys=new Set},commitRender(){if(this._nextHandlerKeys){for(let t of this._handlerKeys)this._nextHandlerKeys.has(t)||this._data.delete(t);this._handlerKeys=this._nextHandlerKeys,this._nextHandlerKeys=null}},clear(){this._data.clear(),this._handlerKeys.clear(),this._nextHandlerKeys=null}};fezError(t,n,i){let s=this.fezName||this.root?.tagName?.toLowerCase()||"unknown",r=i?{...i,componentName:s}:{componentName:s};return Fez.onError(t,`<${s}> ${n}`,r)}get fezHtmlRoot(){return`Fez(${this.UID}).`}get isConnected(){return!!this.root?.isConnected}prop(t){let n=this.oldRoot[t]||this.props[t];return typeof n=="function"&&(n=n.bind(this.root)),n}connect(){}onMount(){}beforeRender(){}afterRender(){}onDestroy(){}onStateChange(){}onGlobalStateChange(){}onPropsChange(){}onRefresh(){}fezOnDestroy(){this._destroyed||(this._destroyed=!0,this._onDestroyCallbacks&&(this._onDestroyCallbacks.forEach(t=>{try{t()}catch(n){this.fezError("destroy","Error in cleanup callback",n)}}),this._onDestroyCallbacks=[]),this.onDestroy(),this.onDestroy=()=>{},this.local={},this.fezGlobals.clear(),this.root&&(this.root.fez=void 0),this.root=void 0)}addOnDestroy(t){this._onDestroyCallbacks=this._onDestroyCallbacks||[],this._onDestroyCallbacks.push(t)}fezParseHtml(t){let n=this.fezHtmlRoot.replaceAll('"',"&quot;");return t=t.replace(/([!'"\s;(])fez\.(\w)/g,`$1${n}$2`).replace(/>\s+</g,"><"),t.trim()}fezNextTick(t,n){n?(this._nextTicks||={},this._nextTicks[n]||=window.requestAnimationFrame(()=>{t.bind(this)(),this._nextTicks[n]=null},n)):window.requestAnimationFrame(t.bind(this))}fezRefresh(){this.fezNextTick(()=>this.fezRender(),"refresh")}refresh(){this.fezRefresh()}fezRender(t){if(t||=this.fezHtmlFunc||this?.class?.fezHtmlFunc,!t||!this.root)return;this._isRendering=!0,this.beforeRender();let n=typeof this.class.nodeName=="function"?this.class.nodeName(this.root):this.class.nodeName,i=document.createElement(n||"div");this.fezGlobals.beginRender();let s;if(Array.isArray(t))t[0]instanceof Node?t.forEach(o=>i.appendChild(o)):s=t.join("");else if(typeof t=="string"){let o=this.root?.tagName?.toLowerCase();s=k(t,{name:o})(this)}else typeof t=="function"&&(s=t(this));if(s)if(s instanceof DocumentFragment||s instanceof Node)i.appendChild(s);else{s=s.replace(/\s\w+="undefined"/g,"");let o=this.fezParseHtml(s),a=Fez.fnv1(o);if(a===this._fezHash){this.fezGlobals.commitRender(),this._isRendering=!1;return}this._fezHash=a,i.innerHTML=o,this.fezPromoteInternalKeys(i)}this.fezKeepNode(i);let r=new Map;this.root.querySelectorAll("input, textarea, select").forEach(o=>{o._fezThisName&&r.set(o._fezThisName,{value:o.value,checked:o.checked})}),Fez.morphdom(this.root,i),r.size&&this.root.querySelectorAll("input, textarea, select").forEach(o=>{let a=o._fezThisName&&r.get(o._fezThisName);a&&(o.value=a.value,a.checked!==void 0&&(o.checked=a.checked))}),this.fezRenderPostProcess(),this.fezGlobals.commitRender(),this.afterRender(),this._isRendering=!1}fezRenderPostProcess(){let t=(n,i)=>{this.root.querySelectorAll(`*[${n}]`).forEach(s=>{let r=s.getAttribute(n);s.removeAttribute(n),r&&i.bind(this)(r,s)})};t("fez-this",(n,i)=>{new Function("n",`this.${n} = n`).bind(this)(i),i._fezThisName=n}),t("fez-use",(n,i)=>{if(n.includes("=>"))return Fez.getFunction(n)(i);if(n.includes("."))return Fez.getFunction(n).bind(i)();let s=this[n];if(typeof s=="function")return s(i);this.fezError("fez-use",`"${n}" is not a function`)}),t("fez-class",(n,i)=>{let s=n.split(/\s+/),r=s.pop();s.forEach(o=>i.classList.add(o)),r&&setTimeout(()=>{i.classList.add(r)},1)}),t("fez-bind",(n,i)=>{if(["INPUT","SELECT","TEXTAREA"].includes(i.nodeName)){let s=new Function(`return this.${n}`).bind(this)(),r=i.type.toLowerCase()=="checkbox",o=["SELECT"].includes(i.nodeName)||r?"onchange":"onkeyup";i.setAttribute(o,`${this.fezHtmlRoot}${n} = this.${r?"checked":"value"}`),this.val(i,s),i._fezThisName=n}else this.fezError("fez-bind",`Can't bind "${n}" to ${i.nodeName} (needs INPUT, SELECT or TEXTAREA)`)}),this.root.querySelectorAll("*[checked], *[disabled], *[selected]").forEach(n=>{for(let i of["checked","disabled","selected"]){if(!n.hasAttribute(i))continue;let s=n.getAttribute(i);["false","null","undefined"].includes(s)?(n.removeAttribute(i),n[i]=!1):n.setAttribute(i,i)}})}fezPromoteInternalKeys(t){t.querySelectorAll?.("[fez-key]").forEach(n=>{n._fezKey=n.getAttribute("fez-key"),n.removeAttribute("fez-key")})}fezKeepNode(t){if(this._fezSlotInitialized||!this._fezSlotNodes)return;let n=t.querySelector(".fez-slot");if(n&&(this._fezSlotInitialized=!0,this._fezSlotNodes.forEach(i=>{n.appendChild(i)}),n.hasAttribute("unwrap"))){let i=n.parentNode;for(;n.firstChild;)i.insertBefore(n.firstChild,n);n.remove()}}fezRegister(){this.css&&(this.css=Fez.globalCss(this.css,{name:this.fezName,wrap:!0})),this.class.css&&(this.class.css=Fez.globalCss(this.class.css,{name:this.fezName})),this.class.fezSlotUnwrap?(this._fezStateDisabled=!0,this.state=new Proxy({},{set:(t,n,i)=>(console.error(`Fez: <${this.fezName}> uses <slot unwrap />, this.state is disabled`),!0),get:(t,n)=>{}})):this.state||=this.fezReactiveStore(),this.globalState=Fez.state.createProxy(this),this.fezRegisterBindMethods()}fezRegisterBindMethods(){let t=new Set,n=Object.getPrototypeOf(this);for(;n&&n!==Object.prototype;){for(let i of Object.getOwnPropertyNames(n))i==="constructor"||t.has(i)||typeof this[i]=="function"&&t.add(i);n=Object.getPrototypeOf(n)}t.forEach(i=>this[i]=this[i].bind(this))}fezReactiveStore(t,n){t||={},n||=(r,o,a,l)=>{a!=l&&(this.onStateChange(o,a,l),!this._isRendering&&!this._isInitializing&&this.fezNextTick(this.fezRender,"fezRender"))},n.bind(this);function i(r){return typeof r=="object"&&r!==null&&!(r instanceof Promise)&&!r.nodeType}function s(r,o){return i(r)?new Proxy(r,{set(a,l,d,c){let h=Reflect.get(a,l,c);if(h!==d){i(d)&&(d=s(d,o));let y=Reflect.set(a,l,d,c);return o(a,l,d,h),y}return!0},get(a,l,d){let c=Reflect.get(a,l,d);return i(c)?s(c,o):c}}):r}return s(t,n)}find(t){return typeof t=="string"?this.root.querySelector(t):t}addClass(t,n){(n||this.root).classList.add(...t.split(/\s+/).filter(Boolean))}toggleClass(t,n,i){(i||this.root).classList.toggle(t,n)}val(t,n){let i=this.find(t);if(i)if(["INPUT","TEXTAREA","SELECT"].includes(i.nodeName))if(typeof n<"u")i.type=="checkbox"?i.checked=!!n:i.value=n;else return i.value;else if(typeof n<"u")i.innerHTML=n;else return i.innerHTML}formData(t){return this.class.formData(t||this.root)}attr(t,n){return typeof n>"u"?this.root.getAttribute(t):(this.root.setAttribute(t,n),n)}childNodes(t){let n=this._fezChildNodes||Array.from(this.root.children);return t&&(n=n.map(t)),n}childObjects(){return this.childNodes().map(t=>{let n={html:t.innerHTML,ROOT:t,NODE_NAME:t.nodeName.toLowerCase()};for(let i of t.attributes)n[i.name]=i.value;return n})}setStyle(t,n){t&&typeof t=="object"?Object.entries(t).forEach(([i,s])=>{this.root.style.setProperty(i,s)}):this.root.style.setProperty(t,n)}copy(){for(let t of Array.from(arguments)){let n=this.props[t];if(n!==void 0){if(t=="class"){let i=this.root.getAttribute(t,n);i&&(n=[i,n].join(" "))}typeof n=="string"?this.root.setAttribute(t,n):this.root[t]=n}}}rootId(){return this.root.id||=`fez_${this.UID}`,this.root.id}dissolve(t){t&&(t.classList.add("fez"),t.classList.add(`fez-${this.fezName}`),t.fez=this,this.attr("id")&&t.setAttribute("id",this.attr("id")),this.root.innerHTML="",this.root.appendChild(t));let n=this.root,i=this.childNodes(),s=this.root.parentNode;return i.reverse().forEach(r=>s.insertBefore(r,n.nextSibling)),this.root.remove(),this.root=void 0,t&&(this.root=t),i}fezBang(t){return t.target!==t.currentTarget?!1:(t.stopPropagation(),t.preventDefault(),!0)}on(t,n,i,s){typeof t=="string"&&([t,n,i,s]=[K.has(t)?window:document,t,n,i]);let r=i.bind(this),o=d=>{this.isConnected&&r(d)},a=s?.throttle?Fez.throttle(o,s.throttle):o;t.addEventListener(n,a,s);let l=()=>t.removeEventListener(n,a,s);return this.addOnDestroy(l),l}onWindowResize(t,n=200){this.on("resize",t,{throttle:n}),t.call(this)}onWindowScroll(t,n=200){this.on("scroll",t,{throttle:n}),t.call(this)}onElementResize(t,n,i=200){let s=Fez.throttle(()=>{this.isConnected&&n.call(this,t.getBoundingClientRect(),t)},i),r=new ResizeObserver(s);r.observe(t),n.call(this,t.getBoundingClientRect(),t),this.addOnDestroy(()=>{r.disconnect()})}setTimeout(t,n){let i=setTimeout(()=>{this.isConnected&&t()},n);return this.addOnDestroy(()=>clearTimeout(i)),i}setInterval(t,n,i){typeof t=="number"&&([n,t]=[t,n]),i||=Fez.fnv1(String(t)),this._setIntervalCache||={},clearInterval(this._setIntervalCache[i]);let s=setInterval(()=>{this.isConnected&&t()},n);return this._setIntervalCache[i]=s,this.addOnDestroy(()=>{clearInterval(s),delete this._setIntervalCache[i]}),s}publish(t,...n){return ge(this,t,...n)}subscribe(t,n){let i=me(this,t,n);return this.addOnDestroy(i),i}fezSlot(t,n){n||=document.createElement("template");let i=n.nodeName=="SLOT";for(;t.firstChild;)i?n.parentNode.insertBefore(t.lastChild,n.nextSibling):n.appendChild(t.firstChild);return i?n.parentNode.removeChild(n):t.innerHTML="",n}};var nt={data:""},be=e=>typeof window=="object"?((e?e.querySelector("#_goober"):window._goober)||Object.assign((e||document.head).appendChild(document.createElement("style")),{innerHTML:" ",id:"_goober"})).firstChild:e||nt,st=e=>{let t=be(e),n=t.data;return t.data="",n},it=/(?:([\u0080-\uFFFF\w-%@]+) *:? *([^{;]+?);|([^;}{]*?) *{)|(}\s*)/g,rt=/\/\*[^]*?\*\/|  +/g,ye=/\n+/g,S=(e,t)=>{let n="",i="",s="";for(let r in e){let o=e[r];r[0]=="@"?r[1]=="i"?n=r+" "+o+";":i+=r[1]=="f"?S(o,r):r+"{"+S(o,r[1]=="k"?"":t)+"}":typeof o=="object"?i+=S(o,t?t.replace(/([^,])+/g,a=>r.replace(/(^:.*)|([^,])+/g,l=>/&/.test(l)?l.replace(/&/g,a):a?a+" "+l:l)):r):o!=null&&(r=/^--/.test(r)?r:r.replace(/[A-Z]/g,"-$&").toLowerCase(),s+=S.p?S.p(r,o):r+":"+o+";")}return n+(t&&s?t+"{"+s+"}":s)+i},C={},ze=e=>{if(typeof e=="object"){let t="";for(let n in e)t+=n+ze(e[n]);return t}return e},ot=(e,t,n,i,s)=>{let r=ze(e),o=C[r]||(C[r]=(l=>{let d=0,c=11;for(;d<l.length;)c=101*c+l.charCodeAt(d++)>>>0;return"go"+c})(r));if(!C[o]){let l=r!==e?e:(d=>{let c,h,y=[{}];for(;c=it.exec(d.replace(rt,""));)c[4]?y.shift():c[3]?(h=c[3].replace(ye," ").trim(),y.unshift(y[0][h]=y[0][h]||{})):y[0][c[1]]=c[2].replace(ye," ").trim();return y[0]})(e);C[o]=S(s?{["@keyframes "+o]:l}:l,n?"":"."+o)}let a=n&&C.g?C.g:null;return n&&(C.g=C[o]),((l,d,c,h)=>{h?d.data=d.data.replace(h,l):d.data.indexOf(l)===-1&&(d.data=c?l+d.data:d.data+l)})(C[o],t,i,a),o},at=(e,t,n)=>e.reduce((i,s,r)=>{let o=t[r];if(o&&o.call){let a=o(n),l=a&&a.props&&a.props.className||/^go/.test(a)&&a;o=l?"."+l:a&&typeof a=="object"?a.props?"":S(a,""):a===!1?"":a}return i+s+(o??"")},"");function F(e){let t=this||{},n=e.call?e(t.p):e;return ot(n.unshift?n.raw?at(n,[].slice.call(arguments,1),t.p):n.reduce((i,s)=>Object.assign(i,s&&s.call?s(t.p):s),{}):n,be(t.target),t.g,t.o,t.k)}var we,q,G,lt=F.bind({g:1}),ct=F.bind({k:1});function ft(e,t,n,i){S.p=t,we=e,q=n,G=i}function dt(e,t){let n=this||{};return function(){let i=arguments;function s(r,o){let a=Object.assign({},r),l=a.className||s.className;n.p=Object.assign({theme:q&&q()},a),n.o=/ *go\d+/.test(l),a.className=F.apply(n,i)+(l?" "+l:""),t&&(a.ref=o);let d=e;return e[0]&&(d=a.as||e,delete a.as),G&&d[0]&&G(a),we(d,a)}return t?t(s):s}}var xe={css:F,extractCss:st,glob:lt,keyframes:ct,setup:ft,styled:dt};function V(e,t,n={}){$e(e,t,n);let i=e.nextSibling;i?.nodeType===3&&!i.textContent.trim()&&i.remove()}function ut(e,t){let n=e.attributes,i=t.attributes,s=e===document.activeElement&&Ce(e),r=t.hasAttribute("style"),o=e.getAttribute("class")||"",a=t.getAttribute("class")||"",l=o!==""&&o===a;for(let d=n.length-1;d>=0;d--){let c=n[d].name;if(!t.hasAttribute(c)){if(c==="style"&&!r&&l)continue;e.removeAttribute(c)}}for(let d=0;d<i.length;d++){let c=i[d];if(!(s&&(c.name==="value"||c.name==="checked"))&&e.getAttribute(c.name)!==c.value)if(c.name==="class")ht(e,t);else try{e.setAttribute(c.name,c.value)}catch(h){console.error("Error setting attribute:",{node:e,attribute:c.name,error:h.message})}}}function ve(e,t){e.nodeType!==1||t.nodeType!==1||(t._fezKey!==void 0?e._fezKey=t._fezKey:delete e._fezKey)}function ht(e,t){let n=new Set((e.getAttribute("class")||"").split(/\s+/).filter(Boolean)),i=new Set((t.getAttribute("class")||"").split(/\s+/).filter(Boolean));for(let s of n)i.has(s)||e.classList.remove(s);for(let s of i)n.has(s)||e.classList.add(s)}function Ce(e){let t=e.nodeName;return t==="INPUT"||t==="TEXTAREA"||t==="SELECT"}function Z(e){if(e.nodeType!==1)return null;let t=e.getAttribute?.("fez-keep");if(t)return{key:"keep-"+t,preserve:!0};if(e._fezKey!==void 0)return{key:"key-"+e._fezKey,preserve:!1};let n=e.getAttribute?.("fez-key");if(n)return{key:"key-"+n,preserve:!1};let i=e.getAttribute?.("key");if(i)return{key:"key-"+i,preserve:!1};let s=e.id;return s?{key:"id-"+s,preserve:!1}:null}function pt(e,t){if(t.describeOld){let n=t.describeOld(e);if(n)return n}return Z(e)}function mt(e,t){if(t.describeNew){let i=t.describeNew(e);if(i)return i}let n=Z(e);return n?n.key:null}function $e(e,t,n){let i=Array.from(e.childNodes),s=Array.from(t.childNodes);if(i.length===0&&s.length===0)return;if(i.length===0){for(let g of s)e.appendChild(g);return}if(s.length===0){for(let g of i)n.beforeRemove&&g.nodeType===1&&P(g,n),e.removeChild(g);return}let r=new Map,o=new Map,a=(g,f)=>{r.has(g)||r.set(g,[]),r.get(g).push(f)};for(let g of i){let f=pt(g,n);if(f&&(o.set(g,f),a(f.key,g),f.aliases))for(let m of f.aliases)a(m,g)}let l=[],d=new Set;for(let g=0;g<s.length;g++){let f=s[g],m=mt(f,n);if(m&&r.has(m)){let u=r.get(m);for(;u.length&&d.has(u[0]);)u.shift();let p=u.shift();if(!p){l.push({old:null,new:f,preserve:!1});continue}let x=!!o.get(p)?.preserve;l.push({old:p,new:f,preserve:x}),d.add(p)}else l.push({old:null,new:f,preserve:!1})}let c=i.filter(g=>!d.has(g)),h=[];for(let g=0;g<l.length;g++){if(l[g].old)continue;let f=l[g].new;if(!(f.nodeType===1&&Z(f)?.preserve))for(let m=0;m<c.length;m++){let u=c[m];if(u.nodeType===1){let z=o.get(u);if(z?.preserve||z&&z.softMatch===!1)continue}let p=bt(u,f);p>0&&h.push({matchIdx:g,oldIdx:m,score:p})}}h.sort((g,f)=>f.score-g.score);let y=new Set,v=new Set;for(let g of h)v.has(g.matchIdx)||y.has(g.oldIdx)||(l[g.matchIdx].old=c[g.oldIdx],d.add(c[g.oldIdx]),y.add(g.oldIdx),v.add(g.matchIdx));for(let g of i)d.has(g)||(g.nodeType===1&&P(g,n),e.removeChild(g));let w=e.firstChild;for(let g of l)if(g.old){let f=g.old,m=g.new;if(g.preserve){n.onPreserve&&n.onPreserve(f,m),ve(f,m),f!==w?e.insertBefore(f,w):w=w.nextSibling;continue}if(f.nodeType===3&&m.nodeType===3)f.textContent!==m.textContent&&(f.textContent=m.textContent);else if(f.nodeType===8&&m.nodeType===8)f.textContent!==m.textContent&&(f.textContent=m.textContent);else if(f.nodeType===1&&m.nodeType===1){if(!(n.skipNode&&n.skipNode(f)))if(f.nodeName===m.nodeName)ut(f,m),ve(f,m),$e(f,m,n),gt(f,m);else{P(f,n);let u=m;e.insertBefore(u,f),e.removeChild(f),w=u.nextSibling;continue}}else{f.nodeType===1&&P(f,n),e.insertBefore(m,f),e.removeChild(f),w=m.nextSibling;continue}f!==w?e.insertBefore(f,w):w=w.nextSibling}else e.insertBefore(g.new,w)}function gt(e,t){if(e.nodeType!==1||t.nodeType!==1)return;let n=e===document.activeElement&&Ce(e),i=e.nodeName;if("disabled"in e&&U(e,t,"disabled"),i==="INPUT"){let s=(e.getAttribute("type")||"").toLowerCase();!n&&t.hasAttribute("value")&&(e.value=t.getAttribute("value")),!n&&(s==="checkbox"||s==="radio")&&U(e,t,"checked")}else i==="TEXTAREA"||i==="SELECT"?n||(e.value=t.value):i==="OPTION"&&U(e,t,"selected")}function yt(e,t){return e.hasAttribute(t)?!["false","null","undefined"].includes(e.getAttribute(t)):!1}function U(e,t,n){let i=yt(t,n);e[n]=i,i||e.removeAttribute(n)}function Ee(e){if(e._morphClassSet)return e._morphClassSet;let t=e.getAttribute?.("class"),n=t?new Set(t.split(/\s+/).filter(Boolean)):null;return e._morphClassSet=n,n}function bt(e,t){if(e.nodeType!==t.nodeType)return 0;if(e.nodeType!==1)return 1;if(e.nodeName!==t.nodeName)return 0;let n=1,i=Ee(e),s=Ee(t);if(i&&s)for(let r of s)i.has(r)&&(n+=3);else!i&&!s&&(n+=1);return e.attributes&&t.attributes&&e.attributes.length===t.attributes.length&&(n+=2),n}function P(e,t){t.beforeRemove&&(t.beforeRemove(e),e.querySelectorAll&&e.querySelectorAll(".fez").forEach(n=>{t.beforeRemove(n)}))}function Te(e){if(e._fezSigHash)return e._fezSigHash;let t=String(e?._fezSignature??e?.outerHTML??"").trim(),n=2166136261;for(let s=0;s<t.length;s++)n^=t.charCodeAt(s),n=Math.imul(n,16777619);let i=(n>>>0).toString(36);return e._fezSigHash=i,i}function Se(e){return e._fezKey??e.getAttribute?.("fez-key")??void 0}function X(e,t,n,i){return e!==void 0?"key-"+e:t?"key-"+t:`${n}:sig-${Te(i)}`}function zt(e){if(e.nodeType!==1||!e.classList?.contains("fez")||!e.fez)return null;let t=[];e.id&&t.push("id-"+e.id);let n=Se(e);n!==void 0&&t.push("key-"+n);let i=e.getAttribute?.("key");if(i&&t.push("key-"+i),e.classList){for(let s of e.classList)if(s.startsWith("fez-")&&s!=="fez"){t.push(`fez-class-${s}:sig-${Te(e)}`);break}}return{key:"fez-uid-"+e.fez.UID,aliases:t,preserve:!0,softMatch:!1}}function wt(e,t){let n=e.fez;if(!n||n._destroyed)return;let i=n.props||{};t&&n.class?.getProps&&(i=n.class.getProps(t,e));let s=n.props||{},r=new Set([...Object.keys(s),...Object.keys(i)]),o=[];for(let a of r)s[a]!==i[a]&&o.push(a);if(n.props=i,o.length){for(let a of o)n.onPropsChange(a,i[a]??null);n.refresh()}n.onRefresh(n.props)}function J(e){function t(i){if(i.nodeType!==1)return null;let s=Se(i),r=i.getAttribute?.("key");if(i.classList?.contains("fez")){for(let l of i.classList)if(l.startsWith("fez-")&&l!=="fez")return X(s,r,"fez-class-"+l,i)}let o=i.tagName?.toLowerCase();if(o&&e.index?.[o])return X(s,r,"fez-class-fez-"+o,i);let a=i.getAttribute?.("fez");if(a&&e.index?.[a]){let l=i.getAttribute?.("fez-key")??void 0;return X(l,r,"fez-class-fez-"+a,i)}return null}let n={describeOld:zt,describeNew:t,skipNode:i=>i.classList?.contains("fez")&&i.fez&&!i.fez._destroyed?(e.LOG&&console.log(`Fez: preserved child component ${i.fez.fezName} (UID ${i.fez.UID})`),!0):!1,beforeRemove:i=>{i.classList?.contains("fez")&&i.fez&&i.fez.fezOnDestroy()},onPreserve:(i,s)=>{i.classList?.contains("fez")&&i.fez&&!i.fez._destroyed&&wt(i,s)}};e.morphdom=(i,s)=>{V(i,s,n)},e.nodeMorph=(i,s,r={})=>{if(!i||i.nodeType!==1){e.onError("nodeMorph","target must be an Element");return}let o=i.tagName,a=o.toLowerCase(),l;if(typeof s=="string"){s=s.trim();let d=document.createElement(a);d.innerHTML=s,d.children.length===1&&d.firstElementChild.tagName===o&&Array.from(d.childNodes).every(c=>c.nodeType!==3||!c.textContent.trim())?l=d.firstElementChild:l=d}else if(s&&s.nodeType===11)l=document.createElement(a),l.appendChild(s);else if(s&&s.nodeType===1)s.tagName===o?l=s:(l=document.createElement(a),l.appendChild(s));else{e.onError("nodeMorph","src must be a string, Element, or DocumentFragment");return}V(i,l,{...n,...r})}}var xt=e=>{let t=e.split(/(<\/?[^>]+>)/g).map(s=>s.trim()).filter(s=>s),n=0,i=[];for(let s=0;s<t.length;s++){let r=t[s],o=t[s+1],a=t[s+2];if(r.startsWith("<"))if(!r.startsWith("</")&&!r.endsWith("/>")&&o&&!o.startsWith("<")&&a&&a.startsWith("</")){let l=Math.max(0,n);i.push("  ".repeat(l)+r+o+a),s+=2}else if(r.startsWith("</")){n--;let l=Math.max(0,n);i.push("  ".repeat(l)+r)}else if(r.endsWith("/>")||r.includes(" />")){let l=Math.max(0,n);i.push("  ".repeat(l)+r)}else{let l=Math.max(0,n);i.push("  ".repeat(l)+r),n++}else if(r){let l=Math.max(0,n);i.push("  ".repeat(l)+r)}}return i.join(`
`)},Y=(()=>{let e=[],t=[],n=0,i=null;document.addEventListener("keydown",o=>{if(o.key==="Escape"){o.preventDefault();let a=document.getElementById("dump-dialog"),l=document.getElementById("log-reopen-button");a?(a.remove(),s()):l&&(l.remove(),r())}else(o.key==="ArrowLeft"||o.key==="ArrowRight"||o.key==="ArrowUp"||o.key==="ArrowDown")&&document.getElementById("dump-dialog")&&e.length>0&&(o.preventDefault(),o.key==="ArrowLeft"&&n>0?(n--,localStorage.setItem("_LOG_INDEX",n),i()):o.key==="ArrowRight"&&n<e.length-1?(n++,localStorage.setItem("_LOG_INDEX",n),i()):o.key==="ArrowUp"&&n>0?(n=Math.max(0,n-5),localStorage.setItem("_LOG_INDEX",n),i()):o.key==="ArrowDown"&&n<e.length-1&&(n=Math.min(e.length-1,n+5),localStorage.setItem("_LOG_INDEX",n),i()))});let s=()=>{let o=document.getElementById("log-reopen-button");o||(o=document.body.appendChild(document.createElement("button")),o.id="log-reopen-button",o.innerHTML='<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:middle;margin-right:4px"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>LOG',o.style.cssText="position:fixed; top: 10px; right: 10px;padding:10px 20px;background:#ff3333;color:#fff;border:none;cursor:pointer;font:14px/1.4 monospace;z-index:2147483647;border-radius:8px;display:flex;align-items:center;opacity:1;visibility:visible;box-shadow:0 4px 12px rgba(255,51,51,0.3)",o.onclick=()=>{o.remove(),r()})},r=()=>{let o=document.getElementById("log-reopen-button");o&&o.remove();let a=document.getElementById("dump-dialog");a||(a=document.body.appendChild(document.createElement("div")),a.id="dump-dialog",a.style.cssText="position:fixed; top:20px; left:20px; right:20px; max-height:calc(100vh - 40px);background:#fff; border:1px solid #333; box-shadow:0 0 10px rgba(0,0,0,0.5);padding:20px; overflow:auto; z-index:2147483646; font:13px/1.4 monospace;white-space:pre; display:block; opacity:1; visibility:visible");let l=parseInt(localStorage.getItem("_LOG_INDEX"));!isNaN(l)&&l>=0&&l<e.length?n=l:n=e.length-1,i=()=>{let d=e.map((c,h)=>{let y="#f0f0f0";return h!==n&&(t[h]==="object"?y="#d6e3ef":t[h]==="array"&&(y="#d8d5ef")),`<button style="font-size: 14px; font-weight: 400; padding:2px 6px; margin: 0 2px 2px 0;cursor:pointer;background:${h===n?"#333":y};color:${h===n?"#fff":"#000"}" data-index="${h}">${h+1}</button>`}).join("");a.innerHTML='<div style="display:flex;flex-direction:column;height:100%"><div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:10px"><div style="display:flex;flex-wrap:wrap;gap:4px;flex:1;margin-right:10px">'+d+'</div><button style="padding:4px 8px;cursor:pointer;flex-shrink:0">&times;</button></div><xmp style="font-family:monospace;flex:1;overflow:auto;margin:0;padding:0;color:#000;background:#fff;font-size:14px;line-height:22px">'+e[n]+"</xmp></div>",a.querySelector('button[style*="flex-shrink:0"]').onclick=()=>{a.remove(),s()},a.querySelectorAll("button[data-index]").forEach(c=>{c.onclick=()=>{n=parseInt(c.dataset.index),localStorage.setItem("_LOG_INDEX",n),i()}})},i()};return o=>{if(!document.body){window.requestAnimationFrame(()=>Y(o));return}let a=typeof o;o instanceof Node&&(o.nodeType===Node.TEXT_NODE?o=o.textContent||String(o):o=xt(o.outerHTML)),o===void 0&&(o="undefined"),o===null&&(o="null"),Array.isArray(o)?a="array":typeof o=="object"&&o!==null&&(a="object"),typeof o!="string"&&(o=JSON.stringify(o,(d,c)=>typeof c=="function"?String(c):c,2).replaceAll("<","&lt;")),o=o.trim(),e.push(o+`

type: ${a}`),t.push(a),!!document.getElementById("dump-dialog")?(n=e.length-1,localStorage.setItem("_LOG_INDEX",n),i&&i()):r()}})();typeof window<"u"&&!window.LOG&&(window.LOG=Y);var Ae=Y;var _e=()=>{let e=parseInt(window.location.port)||80;if(!(Fez.DEV===!0||e>2999&&Fez.DEV!==!1))return;let t=document.querySelectorAll(".fez-highlight-overlay");if(t.length>0){t.forEach(i=>i.remove());return}document.querySelectorAll(".fez, .svelte").forEach(i=>{let s=null,r=null;if(i.classList.contains("fez")&&i.fez&&i.fez.fezName?(s=i.fez.fezName,r="fez"):i.classList.contains("svelte")&&i.svelte&&i.svelte.svelteName&&(s=i.svelte.svelteName,r="svelte"),s){let o=document.createElement("div");o.className="fez-highlight-overlay";let a=i.getBoundingClientRect(),l=window.pageYOffset||document.documentElement.scrollTop,d=window.pageXOffset||document.documentElement.scrollLeft;o.style.cssText=`
        position: absolute;
        top: ${a.top+l}px;
        left: ${a.left+d}px;
        width: ${a.width}px;
        height: ${a.height}px;
        border: 1px solid ${r==="svelte"?"blue":"red"};
        pointer-events: none;
        z-index: 9999;
      `;let c=document.createElement("div");c.textContent=s,c.style.cssText=`
        position: absolute;
        top: -20px;
        left: 0;
        background: ${r==="svelte"?"blue":"red"};
        color: white;
        padding: 4px 6px 2px 6px;
        font-size: 14px;
        font-family: monospace;
        line-height: 1;
        white-space: nowrap;
        cursor: pointer;
        pointer-events: auto;
        text-transform: uppercase;
      `,c.addEventListener("click",h=>{h.stopPropagation(),Fez.log(i)}),o.appendChild(c),document.body.appendChild(o)}})};document.addEventListener("keydown",e=>{(e.ctrlKey||e.metaKey)&&e.key==="e"&&(e.target.closest("form")||(e.preventDefault(),_e()))});var Ie=_e;var vt=new Set(["area","base","br","col","embed","hr","img","input","link","meta","source","track","wbr"]);function L(e){return e.replace(/<([a-z][a-z-]*)\b((?:=>|[^>])*)>/g,(t,n,i)=>!i.trimEnd().endsWith("/")||vt.has(n)?t:`<${n}${i.replace(/\s*\/$/,"")}></${n}>`)}var Et=new MutationObserver(e=>{for(let t of e)if(t.type==="attributes"){let n=t.target.fez;if(n){let i=t.attributeName,s=t.target.getAttribute(i);n.props[i]=s,n.onPropsChange(i,s)}}});function Q(e,t){let n=globalThis.window?.Fez||globalThis.Fez;if(!e.includes("-")){console.error(`Fez: Invalid name "${e}". Must contain a dash.`);return}t=Ct(n,e,t),t.html&&(/<slot\s[^>]*unwrap[\s>\/]/.test(t.html)&&(t.fezSlotUnwrap=!0),t.html=t.html.replace(/<slot(\s[^>]*)?>/,'<div class="fez-slot" fez-keep="default-slot"$1>').replace("</slot>","</div>"),t.fezHtmlFunc=k(t.html,{name:e})),t.css&&(t.css=n.globalCss(t.css,{name:e})),n.index.ensure(e).class=t,customElements.get(e)||customElements.define(e,class extends HTMLElement{connectedCallback(){document.readyState==="loading"?requestAnimationFrame(()=>ke(e,this)):ke(e,this)}})}function Ct(e,t,n){if(n.prototype instanceof T)return n.html&&(n.html=L(n.html)),n;let i=new n,s=class extends T{},r=[...Object.getOwnPropertyNames(i),...Object.getOwnPropertyNames(n.prototype)].filter(a=>a!=="constructor"&&a!=="prototype");for(let a of r)s.prototype[a]=i[a];let o={GLOBAL:"GLOBAL",NAME:"nodeName"};for(let[a,l]of Object.entries(o))i[a]&&(s[l]=i[a]);if(i.CSS&&(s.css=typeof i.CSS=="function"?i.CSS():i.CSS),i.HTML){let a=typeof i.HTML=="function"?i.HTML():i.HTML;s.html=L(a)}return i.META&&(s.META=i.META,e.index.ensure(t).meta=i.META),i.GLOBAL&&e.onReady(()=>document.body.appendChild(document.createElement(t))),e.consoleLog(`${t} compiled`),s}function ke(e,t){if(!t.isConnected||t.classList?.contains("fez"))return;let n=Fez.index[e]?.class,i=typeof n.nodeName=="function"?n.nodeName(t):n.nodeName,s=document.createElement(i||"div");if(s.classList.add("fez",`fez-${e}`),!t.parentNode){console.warn(`Fez: ${e} has no parent, skipping`);return}t.parentNode.replaceChild(s,t);let r=new n;r.UID=++Fez.instanceCount,Fez.instances.set(r.UID,r),r.oldRoot=t,r.fezName=e,r.root=s,r.props=n.getProps(t,s),r.class=n,s._fezSignature=t.outerHTML,r.fezSlot(t,s),s.fez=r,n.GLOBAL&&n.GLOBAL!==!0&&(window[n.GLOBAL]||=r),window.$&&(r.$root=$(s)),r.props.id&&s.setAttribute("id",r.props.id);let o=t.getAttribute("key");o&&s.setAttribute("key",o),t._fezKey!==void 0&&(s._fezKey=t._fezKey);let a=t.getAttribute("fez-key");a&&s.setAttribute("fez-key",a);let l=t.getAttribute("fez-keep");if(l&&s.setAttribute("fez-keep",l),r.fezRegister(),r.root.childNodes.length&&(r._fezSlotNodes=Array.from(r.root.childNodes),r._fezChildNodes=r._fezSlotNodes.filter(c=>c.nodeType===1)),r._isInitializing=!0,(r.onInit||r.init||r.created||r.connect).call(r,r.props),r.fezRender(),r._isInitializing=!1,r.onMount(r.props),r.onRefresh(r.props),r.onSubmit){let c=r.root.nodeName==="FORM"?r.root:r.find("form");c&&(c.onsubmit=h=>{h.preventDefault(),r.onSubmit(r.formData())})}if(r.onPropsChange){Et.observe(s,{attributes:!0});for(let[c,h]of Object.entries(r.props))r.onPropsChange(c,h)}}var Le=new Map;function Me(e){let t=e.split(`
`),n=t.filter(s=>s.trim());if(!n.length)return e;let i=Math.min(...n.map(s=>s.match(/^(\s*)/)[1].length));return i===0?e:t.map(s=>s.slice(i)).join(`
`)}function $t(e,t){return new RegExp(`^<${t}(?:\\s|>|$)`,"i").test(e)}function Tt(e){if(!e)return!1;let t=e.replace(/<demo>[\s\S]*?<\/demo>/gi,"");return/<(xmp|template)\s+fez\s*=/i.test(t)}function M(e,t){if(arguments.length===1)return te(e);if(Tt(t)){if(e){Fez.index.ensure(e).source=t;let s=ne(t);s.info?.trim()&&(Fez.index.ensure(e).info=s.info),s.demo?.trim()&&(Fez.index.ensure(e).demo=s.demo)}return te(t)}if(e&&!e.includes("-")&&!e.includes(".")&&!e.includes("/")){console.error(`Fez: Invalid name "${e}". Must contain a dash (e.g., 'my-element').`);return}if(Fez.index.ensure(e).source=t,Le.get(e)?.html===t&&Fez.index[e]?.class)return Fez.index[e].class;let i=_t(e,ne(t));return Lt(e),It(e,i),Le.set(e,{html:t}),Fez.index[e]?.class}function te(e){if(e instanceof Node){let n=e;n.remove();let i=n.getAttribute("fez");if(i?.includes(".")||i?.includes("/"))return St(i);if(i&&!i.includes("-")){console.error(`Fez: Invalid name "${i}". Must contain a dash.`);return}return M(i,n.innerHTML)}(e?Fez.domRoot(e):document.body).querySelectorAll("template[fez], xmp[fez]").forEach(n=>te(n))}function St(e){if(Fez.consoleLog(`Loading from ${e}`),e.endsWith(".txt")){Fez.head({fez:e});return}Fez.fetch(e).then(t=>{let i=new DOMParser().parseFromString(t,"text/html").querySelectorAll("template[fez], xmp[fez]");if(i.length>0){let s=e.split("/").pop().split(".")[0],r=ne(t);r.info?.trim()&&(Fez.index.ensure(s).info=r.info),r.demo?.trim()&&(Fez.index.ensure(s).demo=r.demo),i.forEach(o=>{let a=o.getAttribute("fez");if(a&&!a.includes("-")&&!a.includes(".")&&!a.includes("/")){console.error(`Fez: Invalid name "${a}". Must contain a dash.`);return}M(a,o.innerHTML)})}else{let s=e.split("/").pop().split(".")[0];M(s,t)}}).catch(t=>{Fez.onError("compile",`Load error for "${e}": ${t.message}`)})}function ne(e){let t={script:"",style:"",html:"",head:"",demo:"",info:""},n=e.split(`
`),i=[],s="";for(let r of n){let o=r.trim();o.startsWith("<demo")&&!t.demo&&!s?s="demo":o.startsWith("<info")&&!t.info&&!s?s="info":o.startsWith("<script")&&!t.script&&s!=="head"&&s!=="demo"&&s!=="info"?s="script":$t(o,"head")&&!t.head&&s!=="demo"&&s!=="info"?s="head":o.startsWith("<style")&&s!=="demo"&&s!=="info"?s="style":o.endsWith("</demo>")&&s==="demo"?(t.demo=Me(i.join(`
`)),i=[],s=""):o.endsWith("</info>")&&s==="info"?(t.info=Me(i.join(`
`)),i=[],s=""):o.endsWith("<\/script>")&&s==="script"&&!t.script?(t.script=i.join(`
`),i=[],s=""):o.endsWith("</style>")&&s==="style"?(t.style=i.join(`
`),i=[],s=""):o.endsWith("</head>")&&s==="head"?(t.head=i.join(`
`),i=[],s=""):s?i.push(s==="demo"||s==="info"?r:o):t.html+=o+`
`}return t.head&&At(t.head),t}function At(e){let t=Fez.domRoot(e);Array.from(t.children).forEach(n=>{if(n.tagName==="SCRIPT"){let i=document.createElement("script");Array.from(n.attributes).forEach(s=>{i.setAttribute(s.name,s.value)}),i.type||="text/javascript",n.src?document.head.appendChild(i):(i.type.includes("javascript")||i.type==="module")&&(i.textContent=n.textContent,document.head.appendChild(i))}else document.head.appendChild(n.cloneNode(!0))})}function _t(e,t){let n=t.script;if(/class\s+\{/.test(n)||(n=`class {
${n}
}`),String(t.style).includes(":")){let r=Fez.cssMixin(t.style).replace(/:host\b/g,":fez");r=r.includes(":fez")||/(?:^|\s)body\s*\{/.test(r)?r:`:fez {
${r}
}`,n=n.replace(/\}\s*$/,`
  CSS = \`${r}\`
}`)}if(/\w/.test(String(t.html))){let r=t.html.replaceAll("`","&#x60;").replaceAll("$","\\$");n=n.replace(/\}\s*$/,`
  HTML = \`${r}\`
}`)}t.demo?.trim()&&(Fez.index.ensure(e).demo=L(t.demo)),t.info?.trim()&&(Fez.index.ensure(e).info=L(t.info));let[i,s]=n.split(/class\s+\{/,2);return`${i};

window.Fez('${e}', class {
${s})`}function It(e,t){if(t.includes("import ")){let n=/Fez\.head\(\s*\{\s*importmap\s*:\s*(\{[\s\S]*?\})\s*\}\s*\)\s*;?/g,i={},s;for(;(s=n.exec(t))!==null;)try{let r=new Function(`return ${s[1]}`)();Object.assign(i,r);let o=Object.entries(r).sort((a,l)=>l[0].length-a[0].length);for(let[a,l]of o){let d=a.replace(/[.*+?^${}()|[\]\\\/]/g,"\\$&");t=t.replace(new RegExp(`(from\\s+['"])${d}`,"g"),`$1${l}`)}}catch(r){Fez.consoleError(`importmap parse error: ${r.message}`)}t=t.replace(n,""),Object.keys(i).length>0&&kt(i),Fez.head({script:t},r=>{if(r){Fez.consoleError(`Template "${e}" module load failed: ${r.message||r}`);return}queueMicrotask(()=>{Fez.index[e]?.class||Fez.consoleError(`Template "${e}" possible compile error.`)})})}else try{new Function(t)()}catch(n){Fez.consoleError(`Template "${e}" compile error: ${n.message}`),console.log(t)}}function kt(e){if(!(typeof document>"u")&&document.head?.appendChild&&!document.querySelector('script[type="importmap"]'))try{let t=document.createElement("script");t.type="importmap",t.textContent=JSON.stringify({imports:e}),document.head.insertBefore(t,document.head.firstChild)}catch{}}var ee=new Set;function Lt(e){if(!e||ee.has(e))return;ee.add(e);let t=document.getElementById("fez-hidden-styles");t||(t=document.createElement("style"),t.id="fez-hidden-styles",document.head.appendChild(t)),t.textContent=`${[...ee].sort().join(", ")} { display: none; }
`}var Mt={data:{},listeners:new Map,subscribers:new Map,globalSubscribers:new Set,notify(e,t,n){Fez.consoleLog(`Global state change for ${e}: ${t} (from ${n})`);let i=this.listeners.get(e);i&&i.forEach(r=>{if(r.isConnected)try{r.onGlobalStateChange(e,t,n),r.fezRender()}catch(o){console.error(`Error in component listener for key ${e}:`,o)}else i.delete(r)});let s=this.subscribers.get(e);s&&s.forEach(r=>{try{r(t,n,e)}catch(o){console.error(`Error in subscriber for key ${e}:`,o)}}),this.globalSubscribers.forEach(r=>{try{r(e,t,n)}catch(o){console.error("Error in global subscriber:",o)}})},createProxy(e){return e.addOnDestroy(()=>{for(let[t,n]of this.listeners)n.delete(e);e._globalStateKeys?.clear()}),new Proxy({},{get:(t,n)=>{if(typeof n!="symbol")return e._globalStateKeys||=new Set,e._globalStateKeys.has(n)||(e._globalStateKeys.add(n),this.listeners.has(n)||this.listeners.set(n,new Set),this.listeners.get(n).add(e)),this.data[n]},set:(t,n,i)=>{if(typeof n=="symbol")return!0;let s=this.data[n];return s!==i&&(this.data[n]=i,this.notify(n,i,s)),!0}})},set(e,t){let n=this.data[e];n!==t&&(this.data[e]=t,this.notify(e,t,n))},get(e){return this.data[e]},forEach(e,t){let n=this.listeners.get(e);n&&n.forEach(i=>{i.isConnected?t(i):n.delete(i)})},subscribe(e,t){if(typeof e=="function")return this.globalSubscribers.add(e),()=>this.globalSubscribers.delete(e);{let n=e;return this.subscribers.has(n)||this.subscribers.set(n,new Set),this.subscribers.get(n).add(t),()=>{let i=this.subscribers.get(n);i&&(i.delete(t),i.size===0&&this.subscribers.delete(n))}}}},Oe=Mt;var j=()=>globalThis.localStorage||window.localStorage;function Ot(e,t){try{j().setItem(e,JSON.stringify(t))}catch(n){console.error(`Fez localStorage: Failed to set "${e}"`,n)}}function Rt(e,t=null){try{let n=j().getItem(e);return n===null?t:JSON.parse(n)}catch(n){return console.error(`Fez localStorage: Failed to get "${e}"`,n),t}}function Dt(e){j().removeItem(e)}function Nt(){j().clear()}var Re={set:Ot,get:Rt,remove:Dt,clear:Nt};function se(e,t,n){e._awaitStates||=new Map;let i=e._awaitStates.get(t);if(!n||typeof n.then!="function")return{status:"resolved",value:n,error:null};if(i&&i.promise===n)return i;let s={status:"pending",value:null,error:null,promise:n};return e._awaitStates.set(t,s),n.then(r=>{let o=e._awaitStates.get(t);o&&o.promise===n&&(o.status="resolved",o.value=r,e.isConnected&&e.fezNextTick(e.fezRender,"fezRender"))}).catch(r=>{let o=e._awaitStates.get(t);o&&o.promise===n&&(o.status="rejected",o.error=r,e.isConnected&&e.fezNextTick(e.fezRender,"fezRender"))}),s}function De(e){let t=document.createElement("div");return t.innerHTML=e,t}var Ft={ensure(e){return(!this[e]||typeof this[e]!="object"||!("class"in this[e]))&&(this[e]={class:null,meta:null,demo:null,info:null,source:null}),this[e]},get(e){let t=this[e];return!t||typeof t!="object"||!("class"in t)?{class:null,meta:null,demo:null,info:null,source:null}:{class:t.class,meta:t.meta,source:t.source,demo:t.demo?De(t.demo):null,info:t.info?De(t.info):null}},apply(e,t){let n=this[e];if(!n?.demo||!t)return!1;let i=document.createElement("div");return i.innerHTML=n.demo,i.querySelectorAll(":scope > script").forEach(s=>{let r=s.textContent;if(r.trim())try{new Function(r)()}catch(o){console.error(`Fez.index.apply("${e}") script error:`,o.message)}s.remove()}),t.innerHTML=i.innerHTML,!0},names(){return Object.keys(this).filter(e=>typeof this[e]=="object"&&this[e]!==null&&"class"in this[e])},withDemo(){return this.names().filter(e=>this[e].demo)},all(){let e={};for(let t of this.names())e[t]=this.get(t);return e},info(){console.log("Fez components:",this.names())}},Ne=Ft;var Fe=e=>{e.head=(s,r)=>{if(s.nodeName){s.nodeName=="SCRIPT"?(e.head({script:s.innerText}),s.remove()):(s.querySelectorAll("script").forEach(h=>e.head(h)),s.querySelectorAll("template[fez], xmp[fez], script[fez]").forEach(h=>e.compile(h)));return}if(typeof s!="object"||s===null)throw new Error("head requires an object parameter");let o,a={},l;if(s.fez){let h=s.fez;if(h.endsWith(".txt")){e.fetch(h).then(y=>{let v=h.substring(0,h.lastIndexOf("/")+1),w=y.split(`
`).map(m=>m.trim()).filter(m=>m&&!m.startsWith("#")),g=0,f=w.length;w.forEach(m=>{let u;if(m.startsWith("/"))u=m;else{let z=m.endsWith(".fez")?m:m+".fez";u=v+z}let p=u.split("/").pop().split(".")[0];e.fetch(u).then(z=>{e.compile(p,z),g++,g===f&&r&&r()})})});return}e.fetch(h).then(y=>{let v=h.split("/").pop().split(".")[0];e.compile(v,y),r&&r()});return}if(s.script){if(s.script.includes("import ")){let h=document.createElement("script");h.type="module",h.textContent=s.script,r&&(h.addEventListener("load",()=>r(null)),h.addEventListener("error",y=>r(y?.error||new Error("module script error")))),document.head.appendChild(h),requestAnimationFrame(()=>h.remove())}else try{new Function(s.script)(),r&&r()}catch(h){e.consoleError("Error executing script:",h),console.log(s.script)}return}else if(s.js){o=s.js,l="script";for(let[h,y]of Object.entries(s))h!=="js"&&h!=="module"&&(a[h]=y);s.module&&(a.type="module")}else if(s.css){o=s.css,l="link",a.rel="stylesheet";for(let[h,y]of Object.entries(s))h!=="css"&&(a[h]=y)}else throw new Error('head requires either "script", "js" or "css" property');let d=document.querySelector(`${l}[src="${o}"], ${l}[href="${o}"]`);if(d)return r&&r(),d;let c=document.createElement(l);l==="link"?c.href=o:c.src=o;for(let[h,y]of Object.entries(a))c.setAttribute(h,y);return(r||s.module)&&(c.onload=()=>{s.module&&l==="script"&&import(o).then(h=>{window[s.module]=h.default||h[s.module]||h}).catch(h=>{console.error(`Error importing module ${s.module}:`,h)}),r&&r()}),document.head.appendChild(c),c};let t=5*60*1e3,n=100;e.fetch=function(...s){e._fetchCache||=new Map;let r="GET",o,a;typeof s[0]=="string"&&/^[A-Z]+$/.test(s[0])&&(r=s.shift()),o=s.shift();let l={},d=null;if(typeof s[0]=="object"&&(d=s.shift()),typeof s[0]=="function"&&(a=s.shift()),d){if(r==="GET"){let f=new URLSearchParams(d);o+=(o.includes("?")?"&":"?")+f.toString()}else if(r==="POST"){let f=new FormData;for(let[m,u]of Object.entries(d))f.append(m,u);l.body=f}}l.method=r,l.headers={"x-requested-with":"XMLHttpRequest",...l.headers};let c=`${r}:${o}:${JSON.stringify(l)}`,h=r==="GET",y=h?e._fetchCache.get(c):null;if(y&&Date.now()-y.timestamp<t){if(e.consoleLog(`fetch cache hit: ${r} ${o}`),a){a(y.data);return}return Promise.resolve(y.data)}let v=f=>f.headers.get("content-type")?.includes("application/json")?f.json():f.text(),w=(f,m)=>{if(e._fetchCache.size>=n){let u=e._fetchCache.keys().next().value;e._fetchCache.delete(u)}e._fetchCache.set(f,{data:m,timestamp:Date.now()})};e._fetchInflight||=new Map;let g=h?e._fetchInflight.get(c):null;if(g?e.consoleLog(`fetch inflight: ${r} ${o}`):(e.consoleLog(`fetch live: ${r} ${o}`),g=fetch(o,l).then(v).then(f=>(h&&w(c,f),f)),h&&(g=g.finally(()=>e._fetchInflight.delete(c)),e._fetchInflight.set(c,g))),a){g.then(f=>a(f)).catch(f=>e.onError("fetch",f));return}return g},e.clearFetchCache=()=>{e._fetchCache?.clear(),e._fetchInflight?.clear()},e.darkenColor=(s,r=20)=>{let o=parseInt(s.replace("#",""),16),a=Math.round(2.55*r),l=(o>>16)-a,d=(o>>8&255)-a,c=(o&255)-a;return"#"+(16777216+(l<255?l<1?0:l:255)*65536+(d<255?d<1?0:d:255)*256+(c<255?c<1?0:c:255)).toString(16).slice(1)},e.lightenColor=(s,r=20)=>{let o=parseInt(s.replace("#",""),16),a=Math.round(2.55*r),l=(o>>16)+a,d=(o>>8&255)+a,c=(o&255)+a;return"#"+(16777216+(l<255?l<1?0:l:255)*65536+(d<255?d<1?0:d:255)*256+(c<255?c<1?0:c:255)).toString(16).slice(1)},e.htmlEscape=s=>typeof s=="string"?s.replace(/font-family\s*:\s*(?:&[^;]+;|[^;])*?;/gi,"").replaceAll("&","&amp;").replaceAll("'","&apos;").replaceAll('"',"&quot;").replaceAll("<","&lt;").replaceAll(">","&gt;"):s===void 0?"":s,e.domRoot=(s,r="div")=>{if(s instanceof Node)return s;{let o=document.createElement(r);return o.innerHTML=s,o}},e.activateNode=(s,r="active")=>{!s||!s.parentElement||(Array.from(s.parentElement.children).forEach(o=>{o.classList.remove(r)}),s.classList.add(r))},e.isTrue=s=>["1","true","on"].includes(String(s).toLowerCase()),e.uid=(()=>{let s=111;return()=>"fez_uid_"+(++s).toString(32)})(),e.POINTER_SEQ=0,e.POINTER={},e.POINTER_CREATED={},e.pointer=(s,r={})=>{if(typeof s=="function"){let o=++e.POINTER_SEQ;return r.persist?e.POINTER[o]=s:(e.POINTER_CREATED[o]=Date.now(),e.POINTER[o]=(...a)=>{let l=s(...a);return delete e.POINTER[o],delete e.POINTER_CREATED[o],l}),`Fez.POINTER[${o}]`}},e.sweepPointers=()=>{let s=Date.now()-3e5;for(let r of Object.keys(e.POINTER_CREATED))e.POINTER_CREATED[r]<s&&(delete e.POINTER[r],delete e.POINTER_CREATED[r])},setInterval(e.sweepPointers,60*1e3),e.getFunction=s=>{if(s){if(typeof s=="function")return s;if(typeof s=="string"){let r=/^\s*\(?\s*\w+(\s*,\s*\w+)*\s*\)?\s*=>/,o=/^\s*function\s*\(/;return r.test(s)||o.test(s)?new Function("return "+s)():s.includes(".")&&!s.includes("(")?new Function(`return function() { return ${s}(); }`):new Function(s)}}else return()=>{}},e.onReady=s=>{document.readyState==="loading"?document.addEventListener("DOMContentLoaded",()=>{s()},{once:!0}):s()},e.fnv1=s=>{let r=2166136261,o=16777619,a=r;for(let l=0;l<s.length;l++)a^=s.charCodeAt(l),a*=o;return a.toString(36).replaceAll("-","")},e.untilTrue=(s,r)=>{r||=200,s()||setTimeout(()=>{e.untilTrue(s,r)},r)};let i=200;e.throttle=(s,r=i)=>{let o=0,a;return function(...l){let d=Date.now();d-o>=r?(s.apply(this,l),o=d):(clearTimeout(a),a=setTimeout(()=>{s.apply(this,l),o=Date.now()},r-(d-o)))}},e.isTruthy=s=>Array.isArray(s)?s.length>0:s&&typeof s=="object"?Object.keys(s).length>0:!!s,e.toPairs=s=>Array.isArray(s)?s.map((r,o)=>[r,o]):s&&typeof s=="object"?Object.entries(s):[],e.tag=(s,r={},o="")=>{let a=encodeURIComponent(JSON.stringify(r));return`<${s} data-props="${a}">${o}</${s}>`},e.typeof=s=>{if(s==null)return"u";if(Array.isArray(s))return"a";let r=typeof s;return r==="function"?"f":r==="string"?"s":r==="number"?Number.isInteger(s)?"i":"n":r==="object"?"o":r[0]}};var Pe={},je=e=>{e.cssMixin=(t,n)=>{if(n)Pe[t]=n;else return Object.entries(Pe).forEach(([i,s])=>{t=t.replaceAll(`:${i} `,`${s} `),t=t.replaceAll(`@include ${i} `,`${s} `)}),t},e.cssMixin("mobile","@media (max-width: 767px)"),e.cssMixin("tablet","@media (min-width: 768px) and (max-width: 1023px)"),e.cssMixin("desktop","@media (min-width:  1200px)")};var b=(e,t)=>{if(typeof e=="number"){let i=b.instances.get(e);if(i)return i;b.onError("lookup",`Instance with UID "${e}" not found. Component may have been destroyed or never created.`,{uid:e});return}if(!e){b.onError("lookup","Fez() called without arguments. Expected component name, UID, or DOM node.");return}if(t){if(typeof t=="function"&&!/^\s*class/.test(t.toString())&&!/\b(this|new)\b/.test(t.toString())){let s=Array.from(document.querySelectorAll(`.fez.fez-${e}`)).filter(r=>r.fez);return s.forEach(r=>t(r.fez)),s}return typeof t!="function"?b.find(e,t):Q(e,t)}let n=e.nodeName?e.closest(".fez"):document.querySelector(e.includes("#")?e:`.fez.fez-${e}`);if(!n){b.onError("lookup",`Component "${e}" not found in DOM. Ensure the component is defined and rendered.`,{componentName:e});return}if(!n.fez){b.onError("lookup",`DOM node "${e}" exists but has no Fez instance attached. Component may not be initialized yet.`,{node:n,tagName:e});return}return n.fez};b.WINDOW_EVENTS=K;b.index=Ne;b.instanceCount=0;b.instances=new Map;b.find=(e,t)=>{let n=typeof e=="string"?document.body.querySelector(e):e;typeof n.val=="function"&&(n=n[0]);let i=t?`.fez.fez-${t}`:".fez",s=n.closest(i);if(s?.fez)return s.fez;b.onError("find",`Node connector not found. Selector: "${i}", node: ${e}`,{original:e,resolved:n,selector:i})};b.cssClass=e=>{try{return xe.css(e)}catch{let t=0;for(let n=0;n<e.length;n++)t=(t<<5)-t+e.charCodeAt(n)|0;return"fez-"+Math.abs(t).toString(36)}};b.globalCss=(e,t={})=>{if(typeof e=="function"&&(e=e()),e.includes(":")){let n=e.split(`
`).filter(i=>!/^\s*\/\//.test(i)).join(`
`);t.wrap&&(n=`:fez { ${n} }`),n=n.replace(/\:fez|\:host/,`.fez.fez-${t.name}`),e=b.cssClass(n)}return b.onReady(()=>document.body.parentElement.classList.add(e)),e};J(b);b.subscribe=he;b.publish=pe;b.localStorage=Re;b.fezAwait=se;b.consoleError=(e,t)=>{if(e=`Fez: ${e}`,console.error(e),t)return`<span style="border: 1px solid red; font-size: 14px; padding: 3px 7px; background: #fee; border-radius: 4px;">${e}</span>`};b.consoleLog=e=>{b.LOG&&console.log(`Fez: ${String(e).substring(0,180)}`)};b.onError=(e,t,n)=>{let i=n?.componentName||n?.name;if(!i&&typeof t=="string"){let a=t.match(/<([^>]+)>/);a&&(i=a[1])}let s=i?` [${i}]`:"",r=typeof t=="string"?t:t?.message||String(t),o=`Fez ${e}:${s} ${r}`;return n&&b.LOG?console.error(o,n):console.error(o),t instanceof Error&&t.stack&&b.LOG&&console.error(t.stack),o};Fe(b);je(b);b.compile=M;b.createTemplate=k;b.state=Oe;b.log=Ae;b.highlightAll=Ie;b.onReady(()=>b.consoleLog("Fez.LOG === true, logging enabled."));var O=b;var Ke=typeof window<"u"&&!window.Fez;Ke&&(window.FezBase=T,window.Fez=O,Promise.resolve().then(()=>(We(),Be)));var Pt=new MutationObserver(e=>{for(let{addedNodes:t,removedNodes:n}of e)t.forEach(i=>{i.nodeType===1&&(i.matches?.("template[fez], xmp[fez], script[fez]")&&(O.compile(i),i.remove()),i.querySelectorAll?.("template[fez], xmp[fez], script[fez]").forEach(s=>{O.compile(s),s.remove()}))}),n.forEach(i=>{if(i.nodeType!==1)return;let s=r=>{r.fez&&!r.fez._destroyed&&queueMicrotask(()=>{!r.isConnected&&r.fez&&!r.fez._destroyed&&(O.instances.delete(r.fez.UID),r.fez.fezOnDestroy())})};s(i),i.querySelectorAll?.(".fez")?.forEach(s)})});Ke&&Pt.observe(document.documentElement,{childList:!0,subtree:!0});var Wn=O;})();
//# sourceMappingURL=fez.js.map
