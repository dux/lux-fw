# frozen_string_literal: true

# input = HtmlInput.new(User.first)
# input.render :email

class HtmlInput
  attr_accessor :type

  def self.as name, &block
    define_method "as_#{name}", &block
  end

  ###

  def initialize obj=nil, opts={}
    @object  = obj
    @globals = opts.dup
  end

  # if type is written in parameter :as=> use this helper function
  def render name, opts={}
    if name.is_hash?
      opts = name
      name  = :null
    end

    opts  = opts_prepare name, opts.dup
    @type = opts.delete(:as) || :text
    send("as_#{@type}") rescue Lux::Error.inline("as_#{@type} (HtmlInput)")
  end

  private

  # exports @name and @opts globals
  def opts_prepare name, opts={}
    opts[:as] ||= lambda do
      return :select if opts[:collection]

      data_type = @object[name].class.name rescue 'String'

      if ['TrueClass','FalseClass'].index(data_type)
        :checkbox
      else
        :string
      end
    end.call

    # experimental, figure out collection unless defined
    if name =~ /_id$/ && opts[:as] == :select && !opts[:collection]
      class_name = name.to_s.split('_id')[0].capitalize
      opts[:collection] = eval "#{class_name}.order('name').all"
    end

    opts[:as]    ||= :select if opts[:collection]
    opts[:id]    ||= Lux.current.uid
    opts[:value] ||= @object.send(name) if @object && name.is_a?(Symbol)
    opts[:value]   = opts[:default] if opts[:value].blank?
    opts[:name]    = name.kind_of?(Symbol) && @object ? "#{@object.class.name.underscore}[#{name}]" : name

    # convert decimal numbers to float
    opts[:value] = opts[:value].to_f if opts[:value].class == BigDecimal

    @label = opts.delete :label
    @wrap  = opts.delete(:wrap) || @globals[:wrap]
    @name  = name
    @opts  = opts
  end

  def prepare_collection data
    ret = []

    if data.is_hash?
      # { id: {name:'Foo'} } : { id: 'Foo' }
      for id, name in data
        name = name[:name] if name.is_hash?
        ret.push [id.to_s, name]
      end
    else
      for el in data
        if data[0].respond_to?(:select_name)
          ret.push [el.id.to_s, el.select_name]
        elsif data[0].respond_to?(:name)
          ret.push [el.id.to_s, el.name]
        elsif data[0].kind_of?(Array)
          ret.push [el[0].to_s, el[1]]
        elsif data.is_hash?
          ret.push el
        else
          ret.push [el.to_s, el]
        end
      end
    end

    ret
  end

  def tag
    HtmlTagBuilder
  end
end
