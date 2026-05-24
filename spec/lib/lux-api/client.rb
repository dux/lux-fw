require 'json'

# Minimal client used by spec/api_tests/tests/client_spec.rb.
# Each method call appends to the URL path and POSTs immediately via
# HTTP.post(url, form: kwargs); the parsed JSON result is wrapped so that
# further method calls extend the URL and re-POST.
class LuxApiClient
  class Result
    def initialize url, hash
      @url  = url
      @hash = hash
    end

    def [] key
      @hash[key]
    end

    def method_missing name, *args, **kwargs
      segments = [name.to_s]
      segments << args.first.to_s if args.length == 1
      url  = "#{@url}/#{segments.join('/')}"
      data = JSON.parse(HTTP.post(url, form: kwargs))
      Result.new(data['url'], data)
    end

    def respond_to_missing? _name, _include_private = false
      true
    end
  end

  def initialize base_url
    @base_url = base_url.chomp('/')
  end

  def method_missing name, *args, **kwargs
    segments = [name.to_s]
    segments << args.first.to_s if args.length == 1
    url  = "#{@base_url}/#{segments.join('/')}"
    data = JSON.parse(HTTP.post(url, form: kwargs))
    Result.new(data['url'], data)
  end

  def respond_to_missing? _name, _include_private = false
    true
  end
end
