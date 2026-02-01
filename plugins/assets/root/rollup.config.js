import svelte from 'rollup-plugin-svelte'
import { scss } from '@kazzkiq/svelte-preprocess-scss';
import nodeResolve from 'rollup-plugin-node-resolve'
import commonjs from 'rollup-plugin-commonjs'
import { terser } from 'rollup-plugin-terser'
import coffee from 'rollup-plugin-coffee-script'
import livereload from 'rollup-plugin-livereload'

const production = !process.env.ROLLUP_WATCH;
const extensions = ['.js', '.coffee']

class Config {
  constructor(init) {
    this.list = []
  }

  default(name) {
    return {
      context: 'window',
      input: `app/assets/${name}`,
      output: {
        sourcemap: false,
        format: 'iife',
        file: `public/assets/${name}`,
        name: name,
      },
      plugins: [
        coffee({exclude: 'node_modules/**'}),
        nodeResolve({
          browser: true,
          extensions: extensions
        }),
        commonjs({
          extensions: extensions,
          ignoreGlobal: true,
        }),
        production && terser()
      ]
    }
  }

  add(name, func) {
    let opts = this.default(name)
    if (func) { func(opts) }
    this.list.push(opts)
  }
}

let config = new Config()

config.add('main.js', (cfg) => {
  cfg.plugins.push(
    livereload({ watch: './public/assets' })
  )
})

config.add('main-react.js', (cfg) => {
  cfg.output.globals = {
    'react': 'React',
    'react-dom':'ReactDOM'
  }
  cfg.external = [
    "react",
    "react-dom"
  ]
})

config.add('main-svelte.js', (cfg) => {
  cfg.plugins.push(
    svelte({
      dev: !production,
      preprocess: { style: scss() }
    })
  )
})

export default config.list

