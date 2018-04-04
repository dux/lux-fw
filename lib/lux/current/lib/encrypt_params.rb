# used for encrypting and decrypting data in forms

module Lux::Current::EncryptParams
  extend self

  @cnt = 0

  # encrypt_param('dux', 'foo')
  # <OpenStruct name="_data_1", value="eyJ0eXAiOiJKV1QiLCJhbGciOi..."
  def encrypt name, value
    base = name.include?('[') ? name.split(/[\[\]]/).first(2).join('::') : name
    base += '#%s' % value

    OpenStruct.new(name: "_data_#{@cnt+=1}", value: Crypt.encrypt(base))
  end

  def hidden_input name, value
    data = encrypt name, value

    %[<input type="hidden" name="#{data.name}" value="#{data.value}" />]
  end

  # decrypts params starting with _data_
  def decrypt hash
    for key in hash.keys
      next unless key.starts_with?('_data_')
      data = Crypt.decrypt(hash.delete(key))
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
  rescue
    Lux.log ' Lux::Current::EncryptParams decrypt error'.red
    {}
  end
end