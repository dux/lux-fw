Sequel::Model.dataset_module do
  # Show all tags on recordset
  # Bucket.can.all_tags -> all_tags mora biti zadnji
  def all_tags opts = {}
    opts = {tags: opts} if opts.class == Symbol
    limit = opts[:limit] || 20
    field = opts[:tags] || :tags
    sqlq = sql.split(' FROM ')[1]
    sqlq = "select lower(unnest(#{field})) as tag FROM " + sqlq
    sqlq = "select tag as name, count(tag) as cnt from (#{sqlq}) as tags group by tag order by cnt desc limit #{limit}"
    DB.fetch(sqlq).map(&:to_hwia).or([])
  end

  # were users.id in (select unnest(user_ids) from doors)
  # def where_unnested klass
  #   target_table = klass.to_s.tableize
  #   where("#{table_name}.id in (select unnest(#{table_name.singularize}_ids) from #{target_table})")
  # end
  # assumes field name is tags
  # Example: Job.where_any(@location.id, :location_ids).count
  def where_any data, field = :tags
    if data.present?
      data = [data] unless data.is_a?(Array)

      clauses = data.map { '?=any(%s)' % field }
      params  = data.map { |v| v.to_s }

      where(Sequel.lit(clauses.join(' or '), *params))
    else
      self
    end
  end
end

