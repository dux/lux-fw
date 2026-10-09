// fez runtime must load before any fez component. The auto-asset compiler emits
// imports depth-first (see Hammerfile / Dir.find), so this top-level loader boots
// fez ahead of everything under ./dollar and the sys-* components beside it.
import 'fez'
