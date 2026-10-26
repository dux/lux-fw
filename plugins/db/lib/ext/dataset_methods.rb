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

    if hash_or_string.is_a?(::Hash)
      ds    = self
      plain = {}
      hash_or_string.each do |key, value|
        next if value.blank? || value == 0
        if model.db_schema[key.to_sym]&.dig(:db_type).to_s.end_with?('[]')
          col = Sequel.identifier(key)
          if value.is_a?(Array)
            # { skills: ['ruby', 'perl'] }, 'or' | 'and'
            join = args.first.to_s.downcase
            raise ArgumentError, 'xwhere array search needs join type "or" or "and"' unless %w[or and].include?(join)
            conds = value.map { |v| Sequel.lit('? = any(?)', v, col) }
            ds = ds.where(join == 'or' ? Sequel.|(*conds) : Sequel.&(*conds))
          else
            ds = ds.where(Sequel.lit('? = any(?)', value, col))
          end
        else
          plain[key] = value
        end
      end
      return plain.empty? ? ds : ds.where(plain)
    end
    self
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
            cur = Lux.respond_to?(:locale) ? Lux.locale.current.to_s : 'en'
            dft = Lux.respond_to?(:locale) ? Lux.locale.default.to_s : cur
            like_sql = "lower(CAST(#{el} -> ? as text)) ilike ?"
            params.push cur, pattern
            if dft != cur
              and_str << "(#{like_sql}) or lower(CAST(#{el} -> ? as text)) ilike ?"
              params.push dft, pattern
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
