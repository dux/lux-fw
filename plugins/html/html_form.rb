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
  def initialize target, opts={}
    opts[:method]   = 'get' if opts.delete(:get)
    opts[:method] ||= 'get' unless @target
    opts[:method] ||= 'post'
    opts[:method]   = opts[:method].upcase

    opts[:id] ||= 'form-%s' % Lux.current.uid

    @target = target
    @opts   = opts
    @before = []     # add stuff to the begining of the form block

    if @target.respond_to?(:update)
      @object = @target
      @opts['data-model'] = @object.class.to_s.underscore.singularize
    end

    before

    @opts[:action] = @target if @target
  end

  # render full form, accepts block
  def render
    data  = @before.join('')
    data += yield self
    data = form data

    @opts.tag(:form, data)
  end

  # run stuff after block initialize
  def before
    true
  end

  # hidden filed
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

      if opts[:value].present?
        Lux::Current::EncryptParams.hidden_input(name, opts[:value])
      else
        ''
      end
    end
  end

  # standard input linked to HtmlInput class
  def input name, opts={}
    @name          = name
    opts[:id]    ||= Lux.current.uid
    opts[:value] ||= Lux.current.request.params[name] if @opts[:method] == 'GET'
    input_object   = HtmlInput.new(@object)
    data           = input_object.render(name, opts)
    @type          = input_object.type
    data
  end

  # submit button
  def submit name=nil
    name ||= 'Submit'
    %[<li><button type="submit">#{name}</button></li>]
  end

  # render simple row
  def row name, opts={}
    node  = input(name, opts)
    label = %[<label for="#{opts[:id]}">#{opts[:label] || name.to_s.humanize}</label>]
    %[<li class="as-#{opts[:as]}">#{label}#{node}<span class="error"></span></li>]
  end

  private

  def form data
    @opts[:class]  = 'ul-form'
    %[<ul>#{data}</ul>]
  end

  def encrypt data
    return unless data
    '[protected]:%s' % Crypt.encrypt(data)
  end
end

