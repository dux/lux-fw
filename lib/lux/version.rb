require 'pathname'

module Lux
  # Build version, mirroring dboss. The raw value is `v<commit count>` stamped
  # into `.version` by `hammer version:stamp` and by the release workflow; a
  # checkout with no stamp reports `dev`. `v<count>` renders dotted:
  # v123 -> v1.2.3, v1123 -> v11.2.3, a shorter count left-padded (v5 -> v0.0.5).
  module Version
    Dev ||= 'dev'

    def self.file
      Pathname.new(__dir__).join('../../.version')
    end

    # Stamp value: `v<count>`, a dotted tag, or `dev`. LUX_VERSION overrides the
    # file, so a build can pin a version without touching the repo.
    def self.raw
      @raw ||=
        if (env = ENV['LUX_VERSION']) && !env.empty?
          env
        elsif file.exist?
          file.read.strip
        else
          Dev
        end
    end

    def self.string = format(raw)

    # Gem::Specification version: dotted form without the leading v.
    def self.gem = string.start_with?('v') ? string[1..] : '0.0.0'

    # "v<digits>" rendered as v<a>.<b>.<c>; anything else (dev, a dotted tag)
    # returned unchanged.
    def self.format(version)
      version = version.to_s
      return version unless version.start_with?('v')

      count = version[1..]
      return version unless count.match?(/\A\d+\z/)

      count = count.rjust(3, '0')
      "v#{count[0..-3]}.#{count[-2]}.#{count[-1]}"
    end
  end
end
