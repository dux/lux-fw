# class ApplicationApi
#   api_method_attr :secure_token do |name|
#     error 'User session required' unless User.current
#     error 'Secure token not found' unless params[:secure_token]
#     error 'Invalid secure token' if User.current.secure_token(name) != params.delete(:secure_token)
#   end
#
#   secure_token :delete
#   def delete_me
#     'ok'
#   end
# end

class ApplicationApi
  API_ATTR ||= {}

  method_attr :desc

  # block is evaluated in runtime when param is defined, not on method_attr defeinition
  class << self
    def api_method_attr name, &block
      method_attr name

      API_ATTR[name] = block
    end

    def documentation_hash
      data = {}
      data.merge! ancestors[1].method_attr if ancestors[1].respond_to?(:method_attr)
      data.merge! method_attr
    end
  end

  ## api_attr check
  before do
    for method_attr_name, block in API_ATTR
      for data in @method_attr[method_attr_name].or([])
        instance_exec data, &block
      end
    end
  end
end