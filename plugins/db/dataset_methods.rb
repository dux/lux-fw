# frozen_string_literal: true

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

      if model.db_schema[key][:db_type].include?('[]')
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
              and_str << "(#{like_sql}) or lower(CAST(#{el} -> ? as text) ilike ?)"
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

  # Card.last_updated
  # Card.last_updated epic_ref: @epic.ref
  def last_updated rules=nil
    field = model.db_schema[:updated_at] && :updated_at
    field ||= model.db_schema[:created_at] && :created_at
    field ||= :ref
    base = rules ? xwhere(rules) : self
    base.order(Sequel.desc(field)).first
  end

  def for obj
    n2 = obj.class.name.underscore
    field_name = "#{n2}_ref".to_sym

    if model.db_schema[field_name]
      where field_name => obj.ref
    elsif model.db_schema["#{n2}_refs".to_sym]
      where Sequel.lit("?=any(#{n2}_refs)", obj.ref.to_s)
    elsif model.db_schema[:parent_key]
      where(parent_key: obj.key)
    elsif model.db_schema[:parent_type]
      where(parent_type: obj.class.to_s, parent_ref: obj.ref)
    else
      raise "Unknown link for #{obj.class} (probably missing db field)"
    end
  end

  def desc field = nil
    field ||= :created_at
    xorder('%s.%s desc' % [model.to_s.tableize, field])
  end

  def asc
    xorder('%s.created_at asc' % model.to_s.tableize)
  end

  def pluck field
    select_map field
  end

  # Job.active.ids(:org_ref) -> distinct array of org_ref
  # Job.active.ids           -> array of ref
  def ids field = nil
    field ||= :ref
    sql = field == :ref ? select(field).sql : select(field).order(nil).distinct(field).sql
    db[sql].to_a.map { |it| it[field] }
      .tap do |out|
        type = model.db_schema[field][:db_type]
        out[0] ||= (type == 'text' || type.include?('varying')) ? '0' : 0
      end
  end

  def last num = nil
    base = xorder('%s desc' % :created_at)
    num ? base.limit(num).all : base.first
  end
end

