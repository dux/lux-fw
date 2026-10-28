require 'securerandom'
require_relative './ref'
require_relative './base'

module Lux
  module Ref
    # UUID version 7 - a 128-bit id whose leading 48 bits are a millisecond
    # timestamp, so values sort by creation time. The alternative primary-key
    # format for apps that want time-ordered uuids instead of short refs.
    #
    #   Lux.config.ref_format = :uuid7
    #
    #   Lux::Ref::Uuid7.new.generate.value   # => "0190a1b2-c3d4-7e8f-9a0b-1c2d3e4f5a6b"
    #   Lux::Ref::Uuid7.new(segment).valid?  # => true / false
    #
    # Layout (RFC 9562): 48-bit big-endian unix_ts_ms, 4-bit version (7),
    # 12 random bits, 2-bit variant (0b10), 62 random bits.
    class Uuid7 < Base
      FORMAT ||= /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
      LENGTH ||= 36

      # `at` is milliseconds since the epoch - passed in by specs that need a
      # fixed value; production always mints from the clock.
      def generate at = nil
        ms    = at || (Time.now.to_f * 1000).floor
        bytes = [ms >> 40, ms >> 32, ms >> 24, ms >> 16, ms >> 8, ms].map { _1 & 0xff }
        bytes += SecureRandom.bytes(10).bytes

        bytes[6] = (bytes[6] & 0x0f) | 0x70   # version 7
        bytes[8] = (bytes[8] & 0x3f) | 0x80   # variant 0b10

        hex = bytes.map { '%02x' % _1 }.join
        with [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
      end

      def valid?
        return false unless @value.is_a?(::String)

        @value.match? FORMAT
      end

      def db_limit
        LENGTH
      end
    end

    register :uuid7, Uuid7
  end
end
