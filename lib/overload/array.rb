class Array
  # Wrap all list elements with a tag
  def wrap name, opts={}
    map{ |el| el.tag(name, **opts) }
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

  def xuniq
    uniq.select { |it| it.present? }
  end

  # Convert list to HTML UL list
  # `@list.to_ul(:foo) # <ul class="foo"><li>...`
  def to_ul klass=nil
    %[<ul class="#{klass}">#{map{|el| "<li>#{el}</li>" }.join('')}</ul>]
  end
end
