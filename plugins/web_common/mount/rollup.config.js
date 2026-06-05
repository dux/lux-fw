// bun i
// bun x rollup -c  # runs rollup from local install

import fs from 'fs';
import { execSync, spawn } from 'child_process';
import svelte from 'rollup-plugin-svelte'
import { sveltePreprocess } from 'svelte-preprocess';
import { nodeResolve } from '@rollup/plugin-node-resolve'
import commonjs from '@rollup/plugin-commonjs'
import terser from '@rollup/plugin-terser'
import coffee from 'rollup-plugin-coffee-script'
import livereload from 'rollup-plugin-livereload'
import alias from '@rollup/plugin-alias';
import fezPlugin from 'fez/rollup';

const production = !process.env.ROLLUP_WATCH;
const extensions = ['.js', '.coffee']

// Delete all files from public/assets when rollup starts
execSync('rm -rf ./public/assets/*', { stdio: 'inherit' })

class Config {
  constructor(init) {
    this.list = []
  }

  default(name) {
    return {
      context: 'window',
      input: `app/assets/${name}`,
      output: {
        sourcemap: !production,
        format: 'iife',
        file: `public/assets/${name.replace('.tmp.', '.')}`,
        name: name,
        inlineDynamicImports: true,
      },
      external: [ 'window' ],
      plugins: [
        alias({
          entries: [
            { find: '@lib', replacement: `${process.cwd()}/app/assets/js/lib` },
            // resolve bare `fez` from app node_modules even when imported by a
            // gem-symlinked source file (nodeResolve would look in the gem dir)
            { find: /^fez$/, replacement: `${process.cwd()}/node_modules/fez/dist/fez.js` },
          ]
        }),
        coffee({ include: /\.coffee$/ }),
        svelte({
          compilerOptions: {
            dev: !production,
            accessors: true,
          },
          emitCss: false,
          preprocess: sveltePreprocess({
            scss: {
              silenceDeprecations: ['legacy-js-api'],
              quietDeps: true
            }
          })
        }),
        nodeResolve({
          browser: true,
          extensions: extensions
        }),
        commonjs({
          extensions: extensions,
          ignoreGlobal: true,
          sourceMap: true,
          // fez dist is a self-running IIFE that sets window.Fez; if commonjs
          // wraps it, its side effects only fire when a binding is required,
          // which a bare `import 'fez'` never does. Let rollup run it inline.
          exclude: [/fez[\/\\]dist[\/\\]fez\.js$/],
        }),
        fezPlugin(),
        production && terser()
      ],
      onwarn: (warning, defaultHandler) => {
        let show = true
        if (warning.code === 'EVAL') { show = false }
        if (warning.pluginCode === 'missing-declaration') { show = false }
        if (warning.message === 'Empty block') { show = false }
        if (warning.message.includes('A11y')) { show = false }
        if (warning.message.includes("was created with unknown prop")) return;
        if (warning.message.includes("has unused export property")) return;
        if (show) { console.log(warning) }
      }
    }

  }

  add(name, func) {
    let opts = this.default(name)
    if (func) { func(opts) }
    this.list.push(opts)
  }
}

let config = new Config()

// Handle all JS files
fs.readdirSync('app/assets').forEach(file => {
  if (/\.js$/.test(file)) {
    config.add(file, (cfg) => {
      cfg.plugins.push(
        !production && livereload({ watch: './public/assets' })
      )
    })
  }
})

// Run SCSS compilation
const scssFiles = fs.readdirSync('app/assets').filter(file => file.endsWith('.scss'))

// auto-<name>.tmp.scss is a generated entry file; emit it as auto-<name>.css
const cssOut = file => file.replace('.tmp.scss', '.css').replace(/\.scss$/, '.css')

if (production) {
  // In production, compile all SCSS files once
  scssFiles.forEach(file => {
    console.log(`\nCompiling SCSS file: ${file}`)
    execSync(`bunx sass app/assets/${file} public/assets/${cssOut(file)} --style=compressed --silence-deprecation=color-functions --silence-deprecation=global-builtin --silence-deprecation=import`, { stdio: 'inherit' })
  })
} else {
  // In development, run in watch mode
  console.log('\nWatching SCSS files...')
  const scssProcesses = scssFiles.map(file => {
    const args = ['sass', `app/assets/${file}`, `public/assets/${cssOut(file)}`, '--style=expanded', '--source-map', '--watch', '--silence-deprecation=color-functions', '--silence-deprecation=global-builtin', '--silence-deprecation=import']
    return spawn('bunx', args, { stdio: 'inherit' })
  })

  // Clean up when rollup exits
  process.on('exit', () => scssProcesses.forEach(p => p.kill()))
  process.on('SIGINT', () => {
    scssProcesses.forEach(p => p.kill())
    process.exit()
  })
}

export default config.list
