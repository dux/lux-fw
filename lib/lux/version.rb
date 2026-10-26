require 'pathname'

module Lux
  # Build version: the commit count rendered dotted (371 -> 3.7.1), stamped
  # into `.version` (YAML, `version: X.Y.Z`) by `hammer deploy` via vstamp;
  # a checkout with no stamp reports `dev`.
  module Version
    Dev ||= 'dev'

    # Stamped version of the lux-fw tree at `root`, nil when it has no stamp.
    # `lux new` reads the framework that runs it, which may not be the loaded one.
    def self.read root
      path = File.join(root.to_s, '.version')
      File.exist?(path) ? File.read(path)[/^version:[ \t]*([^\s#]+)/, 1] : nil
    end

    # `X.Y.Z` or `dev`. LUX_VERSION overrides the file, so a build can pin a
    # version without touching the repo.
    def self.string
      @string ||=
        if (env = ENV['LUX_VERSION']) && !env.empty?
          env
        else
          read(File.expand_path('../..', __dir__)) || Dev
        end
    end

    # Gem::Specification version: no leading v, 0.0.0 for dev.
    def self.gem = string == Dev ? '0.0.0' : string.delete_prefix('v')
  end
end
