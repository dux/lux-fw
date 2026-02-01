# DB tree structures via postgress array

module ModelTree
  def self.included base
    expected = 'integer[]'

    unless base.db_schema[:parent_ids][:db_type] == expected
      die %[Expted #{base}.parent_ids field to be of type "#{expected}"]
    end
  end

  ###

  def parent
    self.class.find(parent_ids[0])
  end

  def children
    self.class.order(:name).xwhere('parent_ids[1]=?', id).all
  end

  def children_ids
    [id] + self.class.xwhere('?=any(parent_ids)', id).ids
  end

  # sets full path
  def parent_id= val
    el   = self.class.find(val)
    list = [el.id]

    while el = el.parent
      list.push el.id
    end

    self[:parent_ids] = list
  end
end