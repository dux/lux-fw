require 'pathname'

module Lux
  class ViewCell
    include HtmlTag

    DATA ||= { css: {} }

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

      def css text = nil
        text = yield if block_given?

        if text
          require 'sassc' unless Object.const_defined?('SassC')

          unless text.include?('{')
            dir_name = self.template_root || File.dirname(caller[0].split(':')[0])
            class_part = to_s.underscore.sub(/_cell$/, '')
            dir_name = dir_name % class_part if dir_name.include?('%s')
            css_file = Pathname.new(dir_name).join(text)
            text = css_file.read
          end

          key = caller[0].split(':in ')[0]
          DATA[:css][key] = SassC::Engine.new(text, style: :compact).render.gsub(/\n+/, $/).chomp
        else
          DATA[:css].inject([]) do |list, el|
            name = el[0].split('/').last.split('.')[0].gsub('_', '-')
            list.push("/* #{name} */\n" + el[1])
          end.join("\n\n")
        end
      end
    end
  end
end
