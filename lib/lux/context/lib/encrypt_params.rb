# Signed (not encrypted - the holder can read them) form params with a 1 day TTL:
# hidden_input('user[id]', 5) emits a _data_* field that decrypt turns back
# into params[:user][:id] = '5' on submit.

module Lux
  class Context
    module EncryptParams
      extend self

      Field   ||= Struct.new(:name, :value)
      PURPOSE ||= 'form_param'

      # encrypt_param('dux', 'foo')
      # #<struct name="_data_1", value="...sealed token...">
      def encrypt name, value
        base = name.include?('[') ? name.split(/[\[\]]/).first(2).join('::') : name
        Field.new("_data_#{Lux.ctx.uid}", Lux::Utils::Crypt.seal("#{base}##{value}", ttl: 1.day, purpose: PURPOSE))
      end

      def hidden_input name, value
        data = encrypt name, value
        Lux::SafeString.new %[<input type="hidden" name="#{data.name}" value="#{data.value}" />]
      end

      # decrypts params starting with _data_
      def decrypt hash
        for key in hash.keys
          next unless key.start_with?('_data_')
          data = Lux::Utils::Crypt.unseal(hash.delete(key), purpose: PURPOSE) or next
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
        Lux.log ' Lux::Context::EncryptParams decrypt error: %s'.colorize(:red) % e.message
        hash
      end
    end
  end
end
