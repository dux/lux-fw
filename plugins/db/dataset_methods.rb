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
    if hash_or_string.class == Hash
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
      search = search.to_s.gsub(/'/,"''").downcase
      where_str = []

      for str in search.split(/\s+/).select(&:present?)
        and_str = []
        str = "%#{str}%".downcase

        for el in args
          schema = model.db_schema[el]
          schema = {} if el.to_s.include?('->>') # if we search inside hash, add fix not to break a code

          raise ArgumentError.new('Database field "%s" not found (xlike)' % el) unless schema

          if schema[:db_type] == 'jsonb'
            like_sql = "lower(CAST(#{el} -> '#{Locale.current}' as text)) ilike '#{str}'"

            if Locale::DEFAULT != Locale.current
              and_str << "(#{like_sql}) or lower(CAST(#{el} -> '#{Locale::DEFAULT}' as text) ilike '#{str}')"
            else
              and_str << like_sql
            end
          else
            and_str << "lower((#{el})::text) ilike '#{str}'"
          end
        end

        where_str.push '('+and_str.join(' or ')+')'
      end

      return where(Sequel.lit(where_str.join(' and ')))
    end
    self
  end

  # Card.last_updated
  # Card.last_updated epic_ids: @epic.id
  def last_updated rules=nil
    field = model.db_schema[:updated_at] && :updated_at
    field ||= model.db_schema[:created_at] && :created_at
    field ||= :id
    base = rules ? xwhere(rules) : self
    base.order(Sequel.desc(field)).first
  end

  def for obj
    # column_names
    field_name = "#{obj.class.name.underscore}_ref".to_sym
    n1 = model.to_s.underscore
    n2 = obj.class.to_s.underscore

    cname = n1[0] < n2[0] ? n1+'_'+n2.pluralize : n2+'_'+n1.pluralize

    if (cname.classify.constantize rescue false)
      where Sequel.lit 'id in (select %s_id from %s where %s_id=%i)' % [n1, cname, n2, obj.id]
    elsif model.db_schema[field_name]
      where field_name => obj.ref
    elsif model.db_schema["#{n2}_refs".to_sym]
      where Sequel.lit '%i=any(%s_refs)' % [obj.ref, n2]
    elsif model.db_schema[:parent_key]
      where(parent_key: obj.key)
    elsif model.db_schema[:parent_type]
      where(parent_type: obj.class.to_s, parent_ref: obj.ref)
    else
      r "Unknown link for #{obj.class} (probably missing db field)"
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

  # Job.active.ids(:org_id) -> distinct array of org_id
  # Job.active.ids          -> array of id
  def ids field = nil
    field ||= model.db_schema[:ref] ? :ref : :id
    sql = [:id, :ref].include?(field) ? select(field).sql : select(field).order(nil).distinct(field).sql
    db[sql].to_a.map { |it| it[field] }
      .tap do |out|
        type = model.db_schema[field][:db_type]
        out[0] ||= type == 'text' || type.include?('varying') ? '0' : 0
      end
  end

  def last num = nil
    base = xorder('%s desc' % [model.db_schema[:ref] ? :created_at : :id])
    num ? base.limit(num).all : base.first
  end
end

