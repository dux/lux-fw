Sequel::Model.dataset_module do
  # only postgree
  # Bucket.can.all_tags -> can_tags mora biti zadnji
  def all_tags field=:tags, *args
    sqlq = sql.split(' FROM ')[1]
    sqlq = "select lower(unnest(#{field})) as tag FROM " + sqlq
    sqlq = "select tag as name, count(tag) as cnt from (#{sqlq}) as tags group by tag order by cnt desc"
    DB.fetch(sqlq).map(&:h).or([])
  end

  # were users.id in (select unnest(user_ids) from doors)
  # def where_unnested klass
  #   target_table = klass.to_s.tableize
  #   where("#{table_name}.id in (select unnest(#{table_name.singularize}_ids) from #{target_table})")
  # end
  # assumes field name is tags
  def where_any data, field
    return self unless data.present?

    if data.is_a?(Array)
      xwhere data.map { |v| "#{v}=any(#{field})" }.join(' or ')
    else
      xwhere('?=any(%s)' % field, data)
    end
  end
end

