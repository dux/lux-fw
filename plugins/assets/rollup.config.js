// bun i
// bun x rollup -c  # runs rollup from local install

import svelte from 'rollup-plugin-svelte'
import { sveltePreprocess } from 'svelte-preprocess';
import nodeResolve from 'rollup-plugin-node-resolve'
import commonjs from 'rollup-plugin-commonjs'
import { terser } from 'rollup-plugin-terser'
import coffee from 'rollup-plugin-coffee-script'
import livereload from 'rollup-plugin-livereload'
import alias from '@rollup/plugin-alias';
import fezImport from '@dinoreic/fez/rollup';

const fs = require('fs');
const production = !process.env.ROLLUP_WATCH;
const extensions = ['.js', '.coffee']

// Delete all files from public/assets when rollup starts
require('child_process').execSync('rm -rf ./public/assets/*', { stdio: 'inherit' })

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
        inlineDynamicImports: true,
      },
      external: [ 'window' ],
      plugins: [
        fezImport(),
        alias({
          entries: [
            { find: '@lib', replacement: `${process.cwd()}/app/assets/js/lib` },
          ]
        }),
        coffee({exclude: 'node_modules/**'}),
        svelte({
          dev: !production,
          accessors: true,
          preprocess: sveltePreprocess()
        }),
        nodeResolve({
          browser: true,
          extensions: extensions
        }),
        commonjs({
          extensions: extensions,
          ignoreGlobal: true,
          sourceMap: true,
        }),
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

if (production) {
  // In production, compile all SCSS files once
  scssFiles.forEach(file => {
    console.log(`\nCompiling SCSS file: ${file}`)
    const cmd = `bunx sass app/assets/${file} public/assets/${file.replace('.scss', '.css')} --style=compressed --silence-deprecation=color-functions --silence-deprecation=global-builtin --silence-deprecation=import`
    require('child_process').execSync(cmd, { stdio: 'inherit' })
  })
} else {
  // In development, run in watch mode
  console.log('\nWatching SCSS files...')
  const scssProcesses = scssFiles.map(file => {
    const cmd = `bunx sass app/assets/${file} public/assets/${file.replace('.scss', '.css')} --style=expanded --source-map --watch --silence-deprecation=color-functions --silence-deprecation=global-builtin --silence-deprecation=import`
    return require('child_process').spawn('bunx', cmd.split(' ').slice(1), { stdio: 'inherit' })
  })

  // Clean up when rollup exits
  process.on('exit', () => scssProcesses.forEach(p => p.kill()))
  process.on('SIGINT', () => {
    scssProcesses.forEach(p => p.kill())
    process.exit()
  })
}

export default config.list

