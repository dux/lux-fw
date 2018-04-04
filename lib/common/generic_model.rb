# frozen_string_literal: true

# class FooBar < GenericModel
#
#   values [1, 'LinkedIn'],
#          [2, 'Facebook'],
#          [3, 'Twitter'],
#          [4, 'Google'],
#          [5, 'Email'],
#          [6, 'Mobile']
#
#   def ico
#     %{<img src="/images/type/#{code}.png" style="width:16px; height:16px; vertical-align:middle; " />}
#   end
#
# end

class GenericModel

  @@values = {}

  class << self
    def values vals
      @@values[self.to_s] = []
      vals.map { |el| add_value(el) }
    end

    def add_value val
      o = new(val)
      for key in val.keys
        eval %[def o.#{key}; @_vals[:#{key}]; end]
      end
      @@values[self.to_s].push(o)
    end

    def find id
      for el in all
        return el if el.id == id
      end
      nil
    end

    def all
      @@values[self.to_s]
    end

    def where opts
      @@values[self.to_s].select{ |el| el[opts.keys[0]] == opts.values[0] }
    end
  end

  ###

  def initialize vals
    @_vals = vals
  end

  def [] key
    @_vals[key]
  end

end