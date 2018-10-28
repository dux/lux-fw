# frozen_string_literal: true

require_relative '../common/free_struct'

class Hash
  def h
    Hashie::Mash.new(self)
  end

  def h_wia
    HashWithIndifferentAccess.new(self)
  end

  def to_readonly name=nil
    Class.new.tap do |c|
      c.define_singleton_method(:to_h) do
        m_list = methods(false) - [:to_h]
        m_list.inject({}) do |h,m|
          h[m] = send(m)
          h[m] = h[m].to_h if h[m].class == Class
          h
        end
      end

      each do |k, v|
        v = v.to_readonly if v.class == Hash
        c.define_singleton_method(k) { v }
      end
    end
  end

  def to_opts! *keys
    self.keys.each { |key| raise 'Hash key :%s is not allowed!' % key unless keys.include?(key) }

    FreeStruct.new keys
      .inject({}) { |it, key| it[key] = self[key]; it }
  end

  def tag node=nil, text=nil
    HtmlTagBuilder.build self, node, text
  end

  def blank?
    self.keys.count == 0
  end

  def to_query namespace=nil
    self.keys.sort.map { |k|
      name = namespace ? "#{namespace}[#{k}]" : k
      "#{name}=#{CGI::escape(self[k].to_s)}"
    }.join('&')
  end

  def data_attributes
    self.keys.sort.map{ |k| 'data-%s="%s"' % [k, self[k].to_s.gsub('"', '&quot;')]}.join(' ')
  end

  def pluck *args
    string_args = args.map(&:to_s)
    self.select{ |k,v| string_args.index(k.to_s) }
  end

  def transform_keys
    return enum_for(:transform_keys) unless block_given?
    result = self.class.new
    each_key do |key|
      result[yield(key)] = self[key]
    end
    result
  end

  def transform_keys!
    return enum_for(:transform_keys!) unless block_given?
    keys.each do |key|
      self[yield(key)] = delete(key)
    end
    self
  end

  def symbolize_keys
    transform_keys{ |key| key.to_sym rescue key }
  end

  def symbolize_keys!
    transform_keys!{ |key| key.to_sym rescue key }
  end

  def slice *keys
    keys.map! { |key| convert_key(key) } if respond_to?(:convert_key, true)
    keys.each_with_object(self.class.new) { |k, hash| hash[k] = self[k] if has_key?(k) }
  end

  def slice! *keys
    keys.map! { |key| convert_key(key) } if respond_to?(:convert_key, true)
    omit = slice(*self.keys - keys)
    hash = slice(*keys)
    hash.default      = default
    hash.default_proc = default_proc if default_proc
    replace(hash)
    omit
  end

  def pretty_generate
    JSON.pretty_generate(self).gsub(/"([\w\-]+)":/) { %["#{$1.yellow}":] }
  end
end

