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
          return where(Sequel.lit("?=any(#{key})", value))
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

  def last_updated
    field = model.db_schema[:updated_at] ? :updated_at : :id
    order(Sequel.desc(field)).first
  end

  def for obj
    # column_names
    field_name = "#{obj.class.name.underscore}_id".to_sym
    n1         = model.to_s.underscore
    n2         = obj.class.to_s.underscore

    cname = n1[0] < n2[0] ? n1+'_'+n2.pluralize : n2+'_'+n1.pluralize

    if (cname.classify.constantize rescue false)
      where Sequel.lit 'id in (select %s_id from %s where %s_id=%i)' % [n1, cname, n2, obj.id]
    elsif model.db_schema["#{n2}_ids".to_sym]
      return where Sequel.lit '%i=any(%s_ids)' % [obj.id, n2]
    elsif model.db_schema[field_name]
      return where Sequel.lit '%s=%i' % [field_name, obj.id]
    elsif model.db_schema[:model_type]
      return where(:model_type=>obj.class.to_s, :model_id=>obj.id)
    elsif obj.class.to_s == 'User'
      if obj.respond_to?(field_name)
        return where Sequel.lit '%s=?' % [field_name, obj.id]
      end
      return where Sequel.lit 'created_by=%i' % obj.id
    else
      r "Unknown link for #{obj.class} (probably missing db field)"
    end
  end

  def desc
    xorder('%s.id desc' % model.to_s.tableize)
  end

  def asc
    xorder('%s.id asc' % model.to_s.tableize)
  end

  def pluck field
    select_map field
  end

  # Job.active.ids(:org_id) -> distinct array of org_id
  # Job.active.ids          -> array of id
  def ids field=:id
    db[select(field).distinct(field).sql].to_a.map { |it| it[field] }
  end
end

