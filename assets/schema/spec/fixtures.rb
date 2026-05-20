class Test
  attr_accessor :name
  attr_accessor :speed
  attr_accessor :email
  attr_accessor :email_nil
  attr_accessor :emails
  attr_accessor :tags
  attr_accessor :eyes
  attr_accessor :age
  attr_accessor :date
  attr_accessor :datetime
  attr_accessor :point
  attr_accessor :http_loc
  attr_accessor :sallary

  def [] key
    send key
  end

  def []= key, value
    send '%s=' % key, value
  end
end

TestSchema ||= Lux.schema do
  name?       # String
  speed?      :float, min: 10, max: 200
  email       :email
  email_nil?  :email
  emails?     Array[:email]
  tags        Array[:label], max_count: 3
  eyes        default: 'blue'
  set         :age, Integer
  date        :date
  datetime    :datetime
  point       :point
  http_loc    :url
  sallary     Integer, name: 'Plata', min: 1000, meta: { min_value_error: '%s a ne %s' }

  db :timestamps
end
