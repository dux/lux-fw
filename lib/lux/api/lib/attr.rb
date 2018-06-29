# - in ApplicationApi
# api_attr :secure_token do |name|
#   error 'User session required' unless User.current
#   error 'Secure token not found' unless params[:secure_token]
#   error 'Invalid secure token' if User.current.secure_token(name) != params.delete(:secure_token)
# end

# - in object api
# secure_token :delete
# def delete_me
#   'ok'
# end

class Lux::Api
  API_ATTR ||= {}

  def self.api_attr name, &block
    method_attr name

    API_ATTR[name] = block
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