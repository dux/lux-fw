ApplicationHelper.class_eval do

  # swelte widget gets props inline
  def svelte name, opts = {}, &block
    Svelte.tag "s-#{name}", opts, &block
  end

  def request
    Lux.current.request
  end

  def response
    Lux.current.response
  end

end
