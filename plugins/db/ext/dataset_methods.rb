# frozen_string_literal: true

# Query-builder primitives. These are the low-level Sequel.lit shorthands
# and the smart-WHERE/LIKE helpers that the higher-level scopes in
# `dataset_scopes.rb` compose on top of.

Sequel::Model.dataset_module do
  def random
    order(Sequel.lit('random()'))
  end

  def xselect text
    select Sequel.lit text
  end

  def xorder text
    order Sequel.lit text
  end

  def xfrom text
    from Sequel.lit text
  end

  def xwhere hash_or_string, *args
    return self if hash_or_string.nil?
    return where(Sequel.lit("coalesce(%s,'')!=''" % hash_or_string)) if hash_or_string.is_a?(Symbol)
    return where(Sequel.lit(hash_or_string, *args))                  if hash_or_string.is_a?(String)

    # check if we do where in a array
    if hash_or_string.is_a?(Hash)
      key = hash_or_string.keys.first

      if model.db_schema[key]&.dig(:db_type)&.include?('[]')
        value = hash_or_string.values.first

        if value.is_a?(Array)
          # { skills: ['ruby', 'perl'] }, 'or'
          # { skills: ['ruby', 'perl'] }, 'and'
          join_type = args.first or die('Define join type for xwhere array search ("or" or "and")')

          data = value.map do |v|
            val =
            if v.is_a?(Integer)
              v
            else
              v = v.gsub(/['"]/,'')
              v = "'%s'" % v
            end

            "%s=any(#{key})" % v
          end
            .join(' %s ' % join_type)

          return where(Sequel.lit(data))
        else
          # skills: 'ruby'
          if value.present?
            return where(Sequel.lit("?=any(#{key})", value))
          end
        end
      end
    end

    q = hash_or_string.select{ |k,v| v.present? && v != 0 }
    q.keys.blank? ? self : where(q)
  end

  def xlike search, *args
    unless search.blank?
      search = search.to_s.downcase
      conditions = []
      params = []

      for str in search.split(/\s+/).select(&:present?)
        and_str = []
        pattern = "%#{str}%"

        for el in args
          schema = model.db_schema[el]
          schema = {} if el.to_s.include?('->>') # if we search inside hash, add fix not to break a code

          raise ArgumentError.new('Database field "%s" not found (xlike)' % el) unless schema

          if schema[:db_type] == 'jsonb'
            like_sql = "lower(CAST(#{el} -> ? as text)) ilike ?"
            params.push Locale.current.to_s, pattern

            if defined?(Locale::DEFAULT) && Locale::DEFAULT != Locale.current
              and_str << "(#{like_sql}) or lower(CAST(#{el} -> ? as text)) ilike ?"
              params.push Locale::DEFAULT.to_s, pattern
            else
              and_str << like_sql
            end
          else
            and_str << "lower((#{el})::text) ilike ?"
            params.push pattern
          end
        end

        conditions.push '(' + and_str.join(' or ') + ')'
      end

      return where(Sequel.lit(conditions.join(' and '), *params))
    end
    self
  end
end
