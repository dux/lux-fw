import babel from 'rollup-plugin-babel'
import svelte from 'rollup-plugin-svelte'
import { scss } from '@kazzkiq/svelte-preprocess-scss';
import nodeResolve from 'rollup-plugin-node-resolve'
import commonjs from 'rollup-plugin-commonjs'
import { terser } from 'rollup-plugin-terser'
import coffee from 'rollup-plugin-coffee-script'
import fs from 'fs'

const production = !process.env.ROLLUP_WATCH;

// js compile template
let configFor = function(name) {
  return {
    //external: ['react', 'react-dom'],
    input: `app/assets/${name}`,
    output: {
      // sourcemap: !production,
      sourcemap: false,
      format: 'iife',
      file: `public/assets/${name}`,
      name: name,
    },
    external: [
      "react",
      "react-dom"
    ],
    plugins: [
      coffee({exclude: 'node_modules/**'}),
      svelte({
        dev: !production,
        preprocess: { style: scss() }
      }),
      nodeResolve({
        browser: true,
        extensions: ['.js', '.coffee']
      }),
      babel({
        extensions: ['.js', '.coffee'],
        plugins: [
          '@babel/plugin-proposal-object-rest-spread',
          '@babel/plugin-proposal-optional-chaining',
          '@babel/plugin-syntax-dynamic-import',
          '@babel/plugin-proposal-class-properties',
          'transform-react-remove-prop-types',
        ],
        exclude: 'node_modules/**',
      }),
      commonjs({
        extensions: ['.js', '.coffee'],
        ignoreGlobal: true,
      }),
      production && terser()
    ]
  }
}

// glob files
export default fs
  .readdirSync('app/assets')
  .filter((f)=>{ return (f.endsWith('.js') || f.endsWith('.coffee')) })
  .map((f)=>{ return configFor(f) })

