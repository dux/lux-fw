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
    @meta = {}
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
    if data
      @error_hash ||= {}
      @error_hash[key.to_s] = data
      data
    else
      @errors ||= []
      @errors.push key unless @errors.include?(key)
      key
    end
  end

  def message what
    @message = what
  end

  def redirect url
    @meta['location'] = url
  end

  def errors?
    (@error_hash || @errors) ? true : false
  end

  def render
    output = {}

    if errors?
      status 400

      output[:error] ||= {}
      output[:error][:messages] = @errors if @errors
      output[:error][:hash] = @error_hash if @error_hash
    end

    Lux.current.response.status status

    output[:data]    = @data    if @data.present?
    output[:meta]    = @meta    if @meta.present?
    output[:message] = @message if @message.present?

    output
  end
  alias :to_hash :render
end