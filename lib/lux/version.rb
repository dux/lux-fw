require 'pathname'

module Lux
  # Build version: the commit count rendered dotted (371 -> 3.7.1), stamped
  # into `.version` (YAML, `version: X.Y.Z`) by `hammer deploy` via vstamp;
  # a checkout with no stamp reports `dev`.
  module Version
    Dev ||= 'dev'

    def self.file
      Pathname.new(__dir__).join('../../.version')
    end

    # `X.Y.Z` or `dev`. LUX_VERSION overrides the file, so a build can pin a
    # version without touching the repo.
    def self.string
      @string ||=
        if (env = ENV['LUX_VERSION']) && !env.empty?
          env
        elsif file.exist?
          file.read[/^version:[ \t]*([^\s#]+)/, 1] || Dev
        else
          Dev
        end
    end

    # Gem::Specification version: no leading v, 0.0.0 for dev.
    def self.gem = string == Dev ? '0.0.0' : string.delete_prefix('v')
  end
end
