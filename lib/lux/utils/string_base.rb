# frozen_string_literal: true

require 'securerandom'

module Lux
module Utils
class StringBase
  SHORT_KEYS   ||= 'bcdghjklmnpqrstvwxyz'
  MEDIUM_KEYS  ||= 'abcdefghijklmnopqrstuvwxyz0123456789'
  LONG_KEYS    ||= 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

  class << self
    def encode text
      short.encode text
    end

    def decode text
      short.decode text
    end

    def short
      new(keys: SHORT_KEYS, multiplier: 99)
    end

    def medium
      new(keys: MEDIUM_KEYS)
    end

    def long
      new(keys: LONG_KEYS)
    end

    def uid
      [
        Time.now.to_f,
        rand.to_s.sub('0.',''),
      ].join('').to_s.sub('.','').to_i.to_s(36)[0, 16]
    end
  end

  ###

  def initialize keys: nil, multiplier: 1
    @keys = keys
    @multiplier = multiplier
  end

  def encode value
    value = value * @multiplier
    ring = ::Hash[@keys.chars.map.with_index.to_a.map(&:reverse)]
    base = @keys.length
    result = []
    until value == 0
      result << ring[ value % base ]
      value /= base
    end
    result.reverse.join
  end

  def decode string
    ring = ::Hash[@keys.chars.map.with_index.to_a]
    base = @keys.length
    ret = string.reverse.chars.map.with_index.inject(0) do |sum, (char, i)|
      sum + ring[char] * (base**i)
    end
    raise 'Invalid decode base' if ret % @multiplier > 0
    ret / @multiplier
  end

  # extract ID from url
  def extract url_part
    id_str = url_part.split('-').last
    return nil unless id_str
    StringBase.decode(id_str) rescue nil
  end

  # StringBase.medium.rand(16) -> ref 16 chars
  #
  # Draws WITH replacement from a CSPRNG. sample(n) drew without replacement off
  # the global PRNG, so asking for more characters than the alphabet holds
  # silently returned a shuffle of the whole alphabet - the same characters every
  # time, in an order seeded RNG could reproduce. Callers use this for refs and
  # credentials, where both of those are wrong.
  def rand num
    chars = @keys.chars
    Array.new(num.to_i) { chars[SecureRandom.random_number(chars.length)] }.join
  end
end
end
end

class Integer
  def string_id
    Lux::Utils::StringBase.encode self
  end
end

class String
  def string_id
    begin
      Lux::Utils::StringBase.decode self.split('-').last
    rescue
      raise ArgumentError.new('Bad ID for string_id')
    end
  end
end
