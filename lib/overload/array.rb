class Array
  # Aonvert list of lists to CSV
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

  # Wrap all list elements with a tag
  def wrap name, opts={}
    map{ |el| opts.tag(name, opts) }
  end

  # Set last element of an array
  def last= what
    self[self.length-1] = what
  end

  # Convert list to sentence, Rails like
  # `@list.to_sentence(words_connector: ', ', two_words_connector: ' and ', last_word_connector: ', and ')`
  def to_sentence opts={}
    opts[:words_connector]     ||= ', '
    opts[:two_words_connector] ||= ' and '
    opts[:last_word_connector] ||= ', and '

    len = self.length

    return '' if len == 0
    return self[0] if len == 1
    return self.join(opts[:two_words_connector]) if len == 2

    last_word = self.pop

    self.join(opts[:words_connector]) + opts[:last_word_connector].to_s + last_word.to_s
  end

  # Toggle existance of an element in array and return true when one added
  # `@list.toggle(:foo)`
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

  # Will return fixed element for any random string
  # `@list.random_by_string('foo')`
  def random_by_string string
    i = string.split('').map{ |_| _.ord }.sum
    self[i % length]
  end

  def xuniq
    uniq.select { |it| it.present? }
  end

  # Convert list to HTML UL list
  # `@list.to_ul(:foo) # <ul class="foo"><li>...`
  def to_ul klass=nil
    %[<ul class="#{klass}">#{map{|el| "<li>#{el}</li>" }.join('')}</ul>]
  end
  
  def shift_push
    next_item = shift
    push next_item
    next_item
  end

  def xmap
    count = 0
    map do |el|
      yield el, ++count
      el
    end
  end
end
