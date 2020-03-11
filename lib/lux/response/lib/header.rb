module Lux
  class Response
    class Header
      attr_reader :data

      def initialize
        @data = {}
      end

      def [] key
        @data[key.downcase]
      end

      def []= key, value
        @data[key.downcase] = value
      end

      def merge hash
        for key, value in hash
          @data[key.downcase] = value
        end

        @data
      end

      def delete name
        @data.delete name.downcase
      end

      def to_h
        @data
      end
    end
 end
end
