require 'securerandom'
require_relative './ref'
require_relative './base'

module Lux
  module Ref
    # The opaque short ref lux apps use as a primary key. Letters and digits
    # only, fixed length. Registered as :string, the default ref format.
    #
    #   Lux::Ref::Short.new.generate.value   # => "k3p9x2mq7wd1nb84"
    #   Lux::Ref::Short.new(segment).valid?  # => true / false
    #
    # Attributes (see Lux::Ref.register) parameterise the family rather than
    # needing a subclass per variant:
    #
    #   length: 26     how many characters (default 16)
    #   upcase: true   A-Z0-9 instead of a-z0-9 (default false)
    #
    #   Lux::Ref.register :ulid_ish, Lux::Ref::Short, length: 26, upcase: true
    class Short < Base
      LOWER  ||= 'abcdefghijklmnopqrstuvwxyz0123456789'
      UPPER  ||= 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
      LENGTH ||= 16

      # Nav lowercases URL segments, so an upcase family normalises its input
      def initialize value = nil, **attrs
        value = value.upcase if attrs[:upcase] && value.is_a?(::String)
        super
      end

      def length
        attrs[:length] || LENGTH
      end

      def generate length = self.length
        with Array.new(length) { alphabet[SecureRandom.random_number(alphabet.length)] }.join
      end

      def valid?
        return false unless @value.is_a?(::String)

        @value.length == length && @value.match?(pattern)
      end

      # a little headroom over the exact length, as the ref column always had
      def db_limit
        length + 4
      end

      private

      def alphabet
        attrs[:upcase] ? UPPER : LOWER
      end

      def pattern
        attrs[:upcase] ? /\A[A-Z0-9]+\z/ : /\A[a-z0-9]+\z/
      end
    end

    register :string, Short
  end
end
