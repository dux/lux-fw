class Lux::Api
  # name   'Show user data'
  # param  :email, type: :email, req: false
  # param  :pass
  # def show
  #   @user = User.where(email:@_email).first
  #   @user.slice(:id, :name, :avatar, :email)
  # end

  # helper for standard definition of parametars
  # param :o_id
  # param :o_id, Integer
  # param :o_id, Integer, req: false
  # param :o_id, req: false
  method_attr :param do |field, type=String, opts={}|
    opts = type.is_a?(Hash) ? type : opts.merge(type: type)
    opts[:name] = field
    opts[:req]  = true if opts[:req].nil?
    opts[:type] ||= String
    opts
  end

  # helper for standard definition of name
  method_attr :name

  # helper for standard definition of description
  method_attr :data

  ###

  before do
    if @method_attr[:param]
      local  = @method_attr[:param].inject({}) { |h, el| o=el.dup; h[o.delete(:name)] = o; h }
      rules  = Typero.new local
      errors = rules.validate(@params)

      if errors.keys.length > 0
        raise ArgumentError.new(errors.values.to_sentence) unless Lux.current

        Lux.current.response.status 400
        error errors.values.to_sentence
      end

      # define local prefixed @_ variables
      for key in local.keys.map(&:to_s)
        value = params[key]
        eval "@_#{key.downcase.gsub(/[^\w]/,'_')} = value" if key.length < 15 && value.present? && key =~ /^[\w]+$/
      end
    end
  end

end