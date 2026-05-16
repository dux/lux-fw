# DB tree structures via postgres text array

module ModelTree
  def self.included base
    expected = 'text[]'

    unless base.db_schema[:parent_refs]&.dig(:db_type) == expected
      die %[Expected #{base}.parent_refs field to be of type "#{expected}"]
    end
  end

  ###

  def parent
    self.class.find(parent_refs[0])
  end

  def children
    self.class.order(:name).xwhere('parent_refs[1]=?', self[:ref]).all
  end

  def children_refs
    [self[:ref]] + self.class.xwhere('?=any(parent_refs)', self[:ref]).ids
  end

  # sets full path
  def parent_ref= val
    el   = self.class.find(val)
    list = [el[:ref]]
    seen = Set.new(list)

    while el = el.parent
      break if seen.include?(el[:ref])
      seen.add(el[:ref])
      list.push el[:ref]
    end

    self[:parent_refs] = list
  end
end
