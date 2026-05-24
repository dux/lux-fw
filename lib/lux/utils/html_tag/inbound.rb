require_relative './html_tag'

module Lux
  module Utils
    module HtmlTag
      # Builds an HTML tree node by node into a string buffer.
      # Designed to be both a one-shot renderer (`Inbound.new.tag(...).render`)
      # and a host inside `instance_exec`'d builder blocks, where unknown
      # method calls fall through to the original host (`@_context`).
      class Inbound
        TAGS ||= Set.new %i(
          a article b button code center colgroup dd div dl dt em fieldset form h1 h2 h3 h4 h5 h6
          header i iframe label legend li main map nav noscript object ol optgroup option p pre q
          script section select small span sub strong style summary table tbody td textarea tfoot th thead title tr u ul video
        )

        EMPTY_TAGS ||= Set.new %i(area base br col embed hr img input keygen link meta param source track wbr)

        # Register a custom tag method so it short-circuits method_missing.
        #   Lux::Utils::HtmlTag.define :foo
        #   Lux::Utils::HtmlTag.define :hr2, empty: true
        def self.define(name, empty: false)
          name = name.to_sym
          EMPTY_TAGS.add(name) if empty

          define_method(name) do |inner = nil, **attrs, &block|
            tag(name, inner, **attrs, &block)
          end
        end

        (TAGS + EMPTY_TAGS).each { |name| define name }

        def initialize(context = nil)
          if context
            context.instance_variables.each do |iv|
              next if iv.to_s.start_with?('@_')
              instance_variable_set(iv, context.instance_variable_get(iv))
            end
          end

          @_context = context
          @_buffer  = []
          @_depth   = 0
        end

        # Explicit access to the host inside blocks (`tag.h1 this.title`).
        def parent(&block)
          raise 'Host scope is not available' unless @_context
          block ? @_context.instance_exec(&block) : @_context
        end
        alias :context :parent
        alias :this    :parent

        def render
          @_buffer.join.gsub(/\n+/, $/)
        end

        # Single canonical signature:
        #   tag(name, inner = nil, **attrs, &block)
        # Attributes are always kwargs (no arg-order swap). Inner is text/value
        # placed between the tags; an explicit block overrides it.
        #
        # Names starting with `_` are a div+class shortcut:
        #   tag._card__lead { 'x' }  ->  <div class="card lead">x</div>
        #   tag._btn_primary         ->  <div class="btn-primary"></div>
        # (`__` separates classes; remaining `_` become `-`.)
        def tag(name, inner = nil, **attrs, &block)
          name = name.to_sym
          name, attrs = _expand_class_shortcut(name, attrs) if name.start_with?('_')
          empty = EMPTY_TAGS.include?(name)

          @_buffer << _open_tag(name, attrs)

          if empty
            @_buffer << ' />'
            return @_buffer
          end

          @_buffer << '>'

          if block
            @_depth += 1
            before = @_buffer.length
            result = @_context ? instance_exec(self, &block) : block.call(self)
            # If the block returned a String and pushed nothing, use it as inner.
            @_buffer << result if result.is_a?(::String) && @_buffer.length == before
            @_depth -= 1
          elsif inner
            @_buffer << (inner.is_a?(::Array) ? inner.join : inner.to_s)
          end

          @_buffer << _indent << "</#{name}>#{_newline}"
          @_buffer
        end

        # Raw insertion - already-rendered HTML or a block returning one.
        def push(data = nil)
          data = yield if block_given?
          @_buffer << data
        end

        # Bridges builder DSL to host. Three cases:
        #   1. `_dot` / `_card__lead` -> the div+class shortcut (handled by #tag)
        #   2. inside a builder block, unknown names flow to @_context (cell, etc.)
        #   3. no context -> NoMethodError
        def method_missing(name, *args, **kwargs, &block)
          if name.to_s.start_with?('_')
            tag(name, *args, **kwargs, &block)
          elsif @_context
            @_context.send(name, *args, **kwargs, &block)
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          name.to_s.start_with?('_') ||
            (@_context && @_context.respond_to?(name, include_private)) ||
            super
        end

        private

        def _expand_class_shortcut(name, attrs)
          classes = name.to_s.sub(/^_/, '').split('__').map { |s| s.gsub('_', '-') }.join(' ')
          merged  = [classes, attrs[:class]].compact.reject(&:empty?).join(' ')
          [:div, attrs.merge(class: merged)]
        end

        def _open_tag(name, attrs)
          head = "#{_newline}#{_indent}<#{name}"
          return head if attrs.empty?

          head + ' ' + attrs.flat_map { |k, v| _attr_pair(k, v) }.join(' ')
        end

        def _attr_pair(key, value)
          case value
          when ::Hash
            # data: { foo: 'x' } -> data-foo="x"
            value.map { |k, v| %(#{key}-#{k}=#{_escape(v)}) }
          when ::Array
            %(#{_dasherize(key)}=#{_escape(value.join(' '))})
          else
            %(#{_dasherize(key)}=#{_escape(value)})
          end
        end

        def _dasherize(key)
          key.to_s.sub(/^data_/, 'data-')
        end

        # Use single quotes when value contains " (e.g. embedded JSON) so the
        # markup stays readable.
        def _escape(value)
          s = value.to_s
          s.include?('"') ? "'#{s.gsub(/'/, '&apos;')}'" : %("#{s}")
        end

        def _indent
          OPTS[:format] ? ' ' * 2 * @_depth : ''
        end

        def _newline
          OPTS[:format] ? $/ : ''
        end
      end
    end
  end
end
