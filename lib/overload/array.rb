class Array
  # Wrap all list elements with a tag
  def wrap name, opts={}
    map { |el| el.to_s.tag(name, **opts) }
  end

  # Set last element of an array
  def last= what
    self[self.length-1] = what
  end

  # Convert list to sentence, Rails like
  # `@list.to_sentence(words_connector: ', ', two_words_connector: ' and ', last_word_connector: ', and ')`
  def to_sentence words_connector: ', ', two_words_connector: ' and ', last_word_connector: ', and '
    case length
    when 0 then ''
    when 1 then self[0].to_s
    when 2 then join(two_words_connector)
    else self[0..-2].join(words_connector) + last_word_connector + self[-1].to_s
    end
  end

  # Toggle existance of an element in array and return true when one added
  # `@list.toggle(:foo)`
  def toggle element
    return push(element) && true unless include?(element)
    delete(element)
    false
  end

  # for easier Sequel query
  def all
    self
  end

  def xuniq
    uniq.select { |it| it.present? }
  end

  # Convert list to HTML UL list, items escaped unless already markup
  # `@list.to_ul(:foo) # <ul class="foo"><li>...`
  def to_ul klass=nil
    Lux::SafeString.join(map { |el| el.to_s.tag(:li) }).tag(:ul, class: klass)
  end
end
