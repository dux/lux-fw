# Class-level (and optional instance-level) attributes with ancestor-walk
# inheritance. Vendored from the `class-cattr` gem (0.3.1) so we own it and can
# adapt it. Public entry stays the global `cattr` macro:
#
#   class Foo
#     cattr :layout, class: true, default: 'main'
#   end
#   Foo.layout            # => 'main'
#   Foo.layout = 'admin'  # subclass values win via the ancestor walk
#
# `cattr.foo` / `cattr.foo=` (proxy form) read/write without declaring an
# accessor; values live in `@cattr_<name>` ivars on the class.
#
# Core constants are written as ::Hash / ::Proc / ::Object: this module lives
# under Lux, where a bare `Hash` would resolve to Lux::Hash and break is_a?.
module Lux
  module Utils
    module ClassAttributes
      SUPPORTED ||= %i[default class instance].freeze

      # Reads/writes @cattr_<name> on the host, walking ancestors on read so
      # subclasses inherit (and may override) a parent's value. A Proc value is
      # treated as a lazy default and re-evaluated in the host's context.
      class Proxy
        def initialize host
          @host = host
        end

        def method_missing key, value = nil
          name = '@cattr_%s' % key

          if name.sub!(/=$/, '')
            @host.instance_variable_set name, value
          else
            raise ::ArgumentError, 'Please use setter cattr.%s= to set argument' % key unless value.nil?

            for el in @host.ancestors
              if el.respond_to?(:superclass) && el != ::Object && el.instance_variable_defined?(name)
                local = el.instance_variable_get name
                local = @host.instance_exec(&local) if local === ::Proc
                return local
              end
            end

            raise ::ArgumentError, 'Cattr class variable "cattr.%s" not defined on "%s".' % [name.sub('@cattr_', ''), @host]
          end
        end
      end

      # Declares an attribute on `klass`. Keeps the gem's original order:
      # define accessors -> validate opts -> seed the default value.
      def self.define klass, name, opts = {}, &block
        raise ::ArgumentError, 'Options are not a Hash' unless opts.is_a?(::Hash)

        opts = opts.dup
        opts[:default] = block if block

        if opts[:class]
          klass.define_singleton_method('%s=' % name) { |arg| Proxy.new(self).send('%s=' % name, arg) }
          klass.define_singleton_method(name) do |arg = :_nil|
            arg.equal?(:_nil) ? Proxy.new(self).send(name) : Proxy.new(self).send('%s=' % name, arg)
          end
        end

        if opts[:instance]
          klass.define_method('%s=' % name) { |arg| Proxy.new(self.class).send('%s=' % name, arg) }
          klass.define_method(name)         { Proxy.new(self.class).send(name) }
        end

        invalid = opts.keys - SUPPORTED
        raise ::ArgumentError, 'Invalid argument :%s, supported: %s' % [invalid.first, SUPPORTED.join(', ')] if invalid.first

        Proxy.new(klass).send('%s=' % name, opts[:default])
      end
    end
  end
end

# Global macro, preserved so every existing `cattr ...` call site keeps working.
# Class receiver -> declare (or return its proxy); plain instance -> read via class.
class Class
  def cattr name = nil, opts = {}, &block
    return Lux::Utils::ClassAttributes::Proxy.new(self) unless name
    Lux::Utils::ClassAttributes.define self, name, opts, &block
  end
end

class Object
  def cattr name = nil
    proxy = Lux::Utils::ClassAttributes::Proxy.new(self.class)
    name ? proxy.send(name) : proxy
  end
end
