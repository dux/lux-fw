# frozen_string_literal: true

# = form Lux.current.var.user do |f|
#   = f.hidden :company_id
#   = f.row :name
#   = f.row :counrty_id, :as=>:country
#   .custom= f.input :email
#   = f.submit 'Save'

ApplicationApi.before do
  name = '[protected]:'
  params.each do |k,v|
    params[k] = Crypt.decrypt(v.split(name, 2)[1]) if v.class == String && v.starts_with?(name)
  end
end

class HtmlForm
  def initialize action, form_opts={}
    form_opts[:method]   = 'get' if form_opts.delete(:get)
    form_opts[:method] ||= 'get' unless action
    form_opts[:method] ||= 'post'
    form_opts[:method]   = form_opts[:method].upcase

    form_opts[:id] ||= 'form-%s' % Lux.current.uid

    @action    = action
    @object    = action if action.respond_to?(:update)
    @form_opts = form_opts
  end

  def encrypt data
    return unless data
    '[protected]:%s' % Crypt.encrypt(data)
  end

  def hidden name, opts={}
    fname  = @object.class.name.tableize.singularize rescue nil

    if name.respond_to?(:update)
      oname = name.class.name.tableize.singularize
      if @object && @object.respond_to?("#{oname}_id") # grp
        Lux::Current::EncryptParams.hidden_input "#{fname}[#{oname}_id]", name.id
      else
        [
          Lux::Current::EncryptParams.hidden_input("#{fname}[model_id]", name.id),
          Lux::Current::EncryptParams.hidden_input("#{fname}[model_type]", name.class.name),
        ].join('')
      end
    else
      opts[:value] ||= @object[name] if @object && name.is_a?(Symbol)
      name = '%s[%s]' % [fname, name] if fname && name.is_a?(Symbol)
      Lux::Current::EncryptParams.hidden_input(name, opts[:value])
    end
  end

  def input name, opts={}
    @name          = name
    opts[:id]    ||= Lux.current.uid
    opts[:value] ||= Lux.current.request.params[name] if @form_opts[:method] == 'GET'
    input_object   = HtmlInput.new(@object)
    data           = input_object.render(name, opts)
    @type          = input_object.type
    data
  end

  def data= body
    @data = body
  end

  def render
    render_form
    @form_opts.tag(:form, @data)
  end

  def render_form
    @data = %[<ul>#{@data}</ul>]
    @form_opts[:class] = 'custom-class'
  end

  def submit name=nil
    name ||= 'Submit'
    %[<button type="submit">#{name}</button>]
  end

  def row name, opts={}
    node  = input(name, opts)
    label = %[<label for="#{opts[:id]}">#{opts[:label] || name.to_s.humanize}</label>]
    %[<p class="as-#{opts[:as]}">#{label}#{node}<span class="error"></span></p>]
  end
end

