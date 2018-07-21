ApplicationHelper.class_eval do

  def widget name, opts={}
    tag, name = name.split(':') if name === String

    tag = :div
    id  = Lux.current.uid

    { class: 'w %s' % name, id: id, 'data-json': opts.to_json }.tag(tag) +
    %[<script>Widget.bind('#{id}');</script>]
  end

end