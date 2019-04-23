class Array
  # convert list of lists to CSV
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

  # wrap all list elements with a tag
  def wrap name, opts={}
    map{ |el| opts.tag(name, opts) }
  end

  # set last element of an array
  def last= what
    self[self.length-1] = what
  end

  # convert list to sentence, Rails like
  def to_sentence opts={}
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

  # toggle existance of an element in array and return true when one added
  def toggle element
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

  # for easier Sequel query
  def all
    self
  end

  # will return fixed element for any random string
  def random_by_string string
    i = string.split('').map{ |_| _.ord }.sum
    self[i % length]
  end

  def xuniq
    uniq.select { |it| it.present? }
  end

end
