module Lux
  class ViewCell
    include HtmlTag

    # exports "template_root" class attr
    cattr :template_root, class: true

    class << self
      # load cell based on a name, pass context and optional vars
      # Lux::ViewCell.get(self, :user) -> UserCell.new(self)
      def get parent, name, vars = {}
        ('%sCell' % name.to_s.classify)
          .constantize
          .new parent, vars
      end

      # delegate current scope methods to parent binding
      # delegate :image_tag, :request, params
      def delegate *list
        list.each do |el|
          define_method(el) { |*args, **kwargs, &block| parent.send(el, *args, **kwargs, &block) }
        end
      end

      # = cell @users
      # = cell @user
      # = cell.user.template @user
      # = cell(:user, user: @user).template
      def cell parent, *args
        first = args.first
        return Lux::ViewCell::Proxy.new(parent) unless first
        return Lux::ViewCell.get(parent, *args) if first.is_a?(::String) || first.is_a?(::Symbol)

        list = first.is_a?(::Array) ? first : [first]
        Lux::SafeString.join(list.map { |object| Lux::ViewCell.get(parent, object.class.to_s.underscore).render object })
      end

      # can be called as a block or a method
      # block do ...
      # def block; super; ...
      def before &block
        define_method :before do
          super() if self.class != Lux::ViewCell
          instance_exec(&block)
        end
      end
    end
  end
end
