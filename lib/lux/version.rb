require 'pathname'

module Lux
  # Build version, mirroring dboss: the commit count rendered dotted
  # (v371 -> v3.7.1), stamped into `.version` by `.githooks/pre-commit`; a
  # checkout with no stamp reports `dev`.
  module Version
    Dev ||= 'dev'

    def self.file
      Pathname.new(__dir__).join('../../.version')
    end

    # `v<a>.<b>.<c>` or `dev`. LUX_VERSION overrides the file, so a build can
    # pin a version without touching the repo.
    def self.string
      @string ||=
        if (env = ENV['LUX_VERSION']) && !env.empty?
          env
        elsif file.exist?
          file.read.strip
        else
          Dev
        end
    end

    # Gem::Specification version: dotted form without the leading v.
    def self.gem = string.start_with?('v') ? string[1..] : '0.0.0'
  end
end
