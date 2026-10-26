// fez runtime must load before any fez component or $ helper that calls Fez.
// web_common has no auto-import: each app's bundler entry (e.g. shared.js under
// rollup) imports @web-common/js/... files explicitly, so it must import 'fez'
// (or this file) first.
import 'fez'
