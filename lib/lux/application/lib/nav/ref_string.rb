require 'securerandom'
require_relative './base'

module Lux
  class Application
    class Nav
      # The opaque short ref lux apps use as a primary key. Letters and digits
      # only, fixed length.
      #
      #   Nav::RefString.new.generate.value   # => "k3p9x2mq7wd1nb84"
      #   Nav::RefString.new(segment).valid?  # => true / false
      #
      # Attributes (see Base.register) parameterise the family rather than
      # needing a subclass per variant:
      #
      #   length: 26     how many characters (default 16)
      #   upcase: true   A-Z0-9 instead of a-z0-9 (default false)
      #
      #   Nav::Base.register :ulid_ish, Nav::RefString, length: 26, upcase: true
      class RefString < Base
        LOWER  ||= 'abcdefghijklmnopqrstuvwxyz0123456789'
        UPPER  ||= 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        LENGTH ||= 16

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

      Base.register :string, RefString
    end
  end
end
