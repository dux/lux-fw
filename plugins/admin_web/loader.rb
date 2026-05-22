# Boot hook for :admin_web. No runtime classes - the plugin's value is
# the mount/ tree (controller + views) and routes.rb (auto-mount at /admin).
# Kept as an empty loader so `Lux.plugin :admin_web` satisfies the
# at-least-one-of-config/loader/load requirement.
