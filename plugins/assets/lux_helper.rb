ApplicationHelper.class_eval do

  def widget name, object=nil, opts=nil
    if object.is_a?(Hash)
      opts = object
    elsif object.is_a?(Sequel::Model)
      # = @project, field: :state_id -> id: 1, model: 'projects', value: 1, field: :state_id
      opts       ||= {}
      opts[:id]    = object.id
      opts[:model] = object.class.to_s.tableize

      if opts[:field] && opts[:value].nil? && object.respond_to?(opts[:field])
        opts[:value] = object.send(opts[:field])
      end
    end

    tag, name = name.split(':') if name === String

    tag = :div
    id  = Lux.current.uid

    data = block_given? ? yield : nil

    { id: id, 'data-json': opts.to_json }.tag('w-%s' % name, data)
  end

end