class Struct
  def to_hash
    Hash[*members.zip(values).flatten]
  end
end
