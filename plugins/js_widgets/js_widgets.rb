ApplicationHelper.class_eval do

  def widget name, object=nil, opts=nil
    if object.is_a?(Hash)
      opts = object
    elsif object.is_a?(Sequel::Model)
      opts       ||= {}
      opts[:id]    = object.id
      opts[:model] = object.class.to_s.tableize
    end

    tag, name = name.split(':') if name === String

    tag = :div
    id  = Lux.current.uid

    data = block_given? ? yield : nil

    { class: 'w %s' % name, id: id, 'data-json': opts.to_json }.tag(tag, data) +
    %[<script>Widget.bind('#{id}');</script>]
  end

end