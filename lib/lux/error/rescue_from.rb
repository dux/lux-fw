module Lux
  # The one `rescue_from` class macro, shared by Lux::Application, Lux::Controller
  # and Lux::Api:
  #
  #   rescue_from { |err| ... }                  # any error (key :all)
  #   rescue_from ArgumentError do |err| ... end # that class and its subclasses
  #   rescue_from :not_found, 'No such record'   # named error, Api `error :not_found`
  #
  # Handlers are inherited; the most specific error class wins, and for the same
  # key the nearest class in the hierarchy wins.
  module RescueFrom
    def rescue_from key = :all, desc = nil, &block
      (@rescue_handlers ||= {})[key] = desc || block
    end

    # Handler (a Proc, or a String for a named error) for an exception or a
    # named-error key; nil when nothing matches.
    def rescue_handler_for error
      keys = error.is_a?(Exception) ? [*error.class.ancestors.take_while { _1 != Object }, :all] : [error]

      keys.each do |key|
        ancestors.each do |klass|
          handlers = klass.instance_variable_get(:@rescue_handlers)
          return handlers[key] if handlers&.key?(key)
        end
      end

      nil
    end

    # every handler declared on this class and its ancestors, nearest first
    def rescue_handlers
      ancestors.reverse.each_with_object({}) do |klass, out|
        out.merge! klass.instance_variable_get(:@rescue_handlers) || {}
      end
    end
  end
end
