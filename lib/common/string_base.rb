# frozen_string_literal: true

class StringBase
  SHORT_KEYS   ||= 'bcdghjklmnpqrstvwxyz'
  MDEIUM_KEYS  ||= 'abcdefghijklmnopqrstuvwxyz0123456789'
  LONG_KEYS    ||= 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

  class << self
    def encode text
      short.encode text
    end

    def decode text
      short.decode text
    end

    def medium
      new(keys: MDEIUM_KEYS)
    end

    def short
      new(keys: SHORT_KEYS, multiplier: 99)
    end

    def long
      new(keys: LONG_KEYS)
    end
  end

  ###

  def initialize keys: nil, multiplier: 1
    @keys = keys
    @multiplier = multiplier
  end

  def encode value
    value = value * @multiplier
    ring = Hash[@keys.chars.map.with_index.to_a.map(&:reverse)]
    base = @keys.length
    result = []
    until value == 0
      result << ring[ value % base ]
      value /= base
    end
    result.reverse.join
  end

  def decode string
    ring = Hash[@keys.chars.map.with_index.to_a]
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
end

class Integer
  def string_id
    StringBase.encode self
  end
end

class String
  def string_id
    begin
      StringBase.decode self.split('-').last
    rescue
      raise ArgumentError.new('Bad ID for string_id')
    end
  end
end
