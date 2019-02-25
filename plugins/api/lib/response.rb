class Lux::Api::Response
  def self.error text
    response = new
    response.error text
    response.render
  end

  ###

  attr_accessor :data
  attr_accessor :message

  def initialize
    @meta = {}.h_wia
  end

  def status num=nil
    meta 'http_status', num.to_i if num && !@meta['http_status']
    @meta['http_status']
  end

  def meta key, value
    value = value.to_i if key == :status
    @meta[key.to_s] = value
  end

  def error key, data=nil
    unless data
      data = key
      key  = :base
    end

    key = key.to_s

    @errors ||= {}
    @errors[key] ||= []
    @errors[key].push data unless @errors[key].include?(data)
  end

  def errors?
    !!@errors
  end

  def message what=:undefined
    @message = what if what != :undefined
    @message
  end

  def redirect url
    @meta['location'] = url
  end

  def event name, opts={}
    @meta['event'] ||= []
    @meta['event'].push([name, opts])
  end

  def render
    output = {}

    if @errors
      status 400

      errors = @errors.inject({}) { |t, (k, v)| t[k] = v.join(', '); t }
      base   = errors.values.uniq

      errors.delete('base')

      output[:error]          ||= {}
      output[:error][:messages] = base
      output[:error][:hash]     = errors if errors.keys.first
    end

    @meta||= {}
    @meta['http_status'] ||= 200

    output[:meta]    = @meta
    output[:data]    = @data    if @data.present?
    output[:message] = @message if @message.present?

    output
  end
  alias :to_hash :render

  def write
    Lux.current.response.status status
    Lux.current.response.body render
  end
end