# used for encrypting and decrypting data in forms

module Lux
  class Current
    module EncryptParams
      extend self

      Field ||= Struct.new(:name, :value)

      # encrypt_param('dux', 'foo')
      # #<struct name="_data_1", value="eyJ0eXAiOiJKV1QiLCJhbGciOi...">
      def encrypt name, value
        base = name.include?('[') ? name.split(/[\[\]]/).first(2).join('::') : name
        base += '#%s' % value

        Field.new("_data_#{Lux.current.uid}", Lux::Utils::Crypt.encrypt(base))
      end

      def hidden_input name, value
        data = encrypt name, value

        %[<input type="hidden" name="#{data.name}" value="#{data.value}" />]
      end

      # decrypts params starting with _data_
      def decrypt hash
        for key in hash.keys
          next unless key.start_with?('_data_')
          data = Lux::Utils::Crypt.decrypt(hash.delete(key))
          data, value = data.split('#', 2)
          data = data.split('::')

          if data[1]
            hash[data[0]] ||= {}
            hash[data[0]][data[1]] = value
          else
            hash[data[0]] = value
          end
        end

        hash
      rescue StandardError => e
        Lux.log ' Lux::Current::EncryptParams decrypt error: %s'.colorize(:red) % e.message
        hash
      end
    end
  end
end
