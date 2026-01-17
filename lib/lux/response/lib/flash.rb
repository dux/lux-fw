# flash.info = 'Test'
# flash.clear -> get hash
# flash.clear_for_js -> get JS optimized hash

module Lux
  class Response
    class Flash
      # flash.info 'messsage ...'
      # flash.info = 'messsage ...'
      def self.add_type name
        define_method(name) { |message| add name, message }
        alias_method "#{name}=", name
      end

      add_type :info
      add_type :error
      add_type :warning

      ###

      def initialize h = nil
        @msg = (h || {}).to_hwia
      end

      def clear
        to_h.tap { @msg = {} }
      end

      def present?
        @msg.keys.first
      end

      def empty?
        !present?
      end

      def to_h
        @msg
      end

      # clears white space, replaces quotes
      def clear_for_js
        {}.tap do |msg|
          clear.each do |k, v|
            msg[k] = v.join(', ').gsub(/\s+/, ' ')
          end
        end
      end

      private

      def add name, message
        return if message.blank?

        @msg[name] ||= []

        return if @msg[name].last == message
        return if @msg[name].length > 4

        @msg[name].push message.to_s
      end
    end
  end
end
