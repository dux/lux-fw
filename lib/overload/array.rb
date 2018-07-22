class Array

  def to_csv
    ret = []
    for row in self
    	add = []
    	for el in row
    		add << '"'+el.to_s.gsub(/\s+/,' ').gsub(/"/,"''")+'"'
	    end
	    ret.push(add.join(';'))
    end
    ret.join("\n")
  end

  def wrap(name, opts={})
    map{ |el| opts.tag(name, opts) }
  end

  def last=(what)
    self[self.length-1] = what
  end

  def to_sentence(opts={})
    opts[:words_connector]     ||= ', '
    opts[:two_words_connector] ||= ' and '
    opts[:last_word_connector] ||= ', and '

    len = self.length

    return '' if len == 0
    return self[0] if len == 1
    return self.join(opts[:two_words_connector]) if len == 2

    last_word = self.pop

    self.join(opts[:words_connector]) + opts[:last_word_connector] + last_word
  end

  # toggle element in array and return true when added
  def toggle(element)
    self.uniq!
    self.compact!
    if self.include?(element)
      self.delete(element)
      false
    else
      self.push(element)
      true
    end
  end

  def all
    self
  end

  # will return fixed element for any random string
  def random_by_string string
    i = string.split('').map{ |_| _.ord }.sum
    self[i % length]
  end

  def push? data
    self.push data if data.present?
    self
  end

  # Sequel specific
  def precache field, klass=nil
    all if respond_to?(:all)

    list = self.map(&field).uniq.sort
    klass ||= field.to_s.sub(/_ids?$/, '').classify.constantize

    for el in klass.where(id: list).all
      key = "#{el.class}/#{el.id}"
      Lux.current.cache(key) { el.dup }
    end

    self
  end
end
