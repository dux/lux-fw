# frozen_string_literal: true

module StringBase
  extend self

  KEYS = 'bcdghjklmnpqrstvwxyz'
  MULTIPLIER = 99

  def encode value
    value = value * MULTIPLIER
    ring = Hash[KEYS.chars.map.with_index.to_a.map(&:reverse)]
    base = KEYS.length
    result = []
    until value == 0
      result << ring[ value % base ]
      value /= base
    end
    result.reverse.join
  end

  def decode string
    ring = Hash[KEYS.chars.map.with_index.to_a]
    base = KEYS.length
    ret = string.reverse.chars.map.with_index.inject(0) do |sum,(char,i)|
      sum + ring[char] * (base**i)
    end
    raise 'Invalid decode base' if ret%MULTIPLIER>0
    ret/MULTIPLIER
  end

  # extract ID from url
  def extract(url_part)
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
    StringBase.decode self
  end
end