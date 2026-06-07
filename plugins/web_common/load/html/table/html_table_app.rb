class AppTable < HtmlTable
  def before scope
    scope.respond_to?(:page) ? scope.page(size: @opts[:size] || 20) : scope
  end

  def id
    col(width: 60, align: :right, title: 'ID') { |o| o.id }
  end

  def callback *fields
    fields = [:ref, :name] unless fields[0]
    onclick { |o| 'Dialog.callback(%s)' % o.slice(*fields).to_json }
  end

  def href &block
    block ||= proc do |o|
      case Lux.current.request.path.split('/')[1].to_sym
      when :dboard
        o.dboard_path
      when :admin
        o.admin_path
      else
        o.path
      end
    end
    onclick { |o| "Pjax.load('%s');" % block.call(o) }
  end

  def dialog &block
    onclick do |o|
      if path = block.call(o)
        "Dialog.load('%s')" % path
      else
        nil
      end
    end
  end

  def idialog name, &block
    onclick { false }
    col(name) { |o| { onclick: "Dialog.inline('#{block.call(o)}', { node: this })" }.tag(:span, o.send(name)) }
  end

  def avatar
    col :avatar, as: :image, width: 40, title: ''
  end

  def count name, opts = {}
    opts[:title] ||= name.to_s.humanize
    opts[:width] ||= 50
    opts[:align] ||= :right
    col(opts) { |o| o.send(name).count }
  end

  def delete
    col(align: :right, width: 40) do |object|
      { size: :xs, type: :danger, onclick: "if (confirm('Sure?')) { Api('#{object.api_path(:destroy)}').refresh() }; return false" }.tag('ui-btn', '&times;')
    end
  end

  ###

  def as_boolean opts
    opts[:width] ||= 100
    opts[:align] ||= :center

    proc do |o|
      base = opts[:proc] ? opts[:proc].call(o) : o.send(opts[:field])
      base ? 'Yes'.wrap(:span, style: 'color:#080') : '-'
    end
  end

  def as_image opts
    opts[:width] ||= 120

    proc do |o|
      src = o.send(opts[:field])
      if src.present?
        if src[0] == '<'
          src
        else
          src = "/a/r/#{src}/100" unless src.include?('/')
          %[<ui-asset src="#{src}" style="width:100%; margin: -3px 0; vertical-align: middle;" size="200"></ui-asset>]
        end
      else
        ''
      end
    end
  end

  def as_avatar opts
    opts[:width] ||= 50
    opts[:title] ||= ''

    proc do |o|
      target = opts[:field] ? o.send(opts[:field]) : o
      next '' unless target.respond_to?(:d_avatar)
      target.d_avatar(size: 32).wrap(:div, style: 'margin: -3px 0 -13px;')
    end
  end

  def as_scope_link opts
    proc do |o|
      el = o.send(opts[:field])
      { class: 'btn', href: el.scope_path }.tag(:a, el.name)
    end
  end

  def as_bold opts
    proc { |o| o.send(opts[:field]).wrap(:b) }
  end

  def as_url opts
    proc do |o|
      value = o.send(opts[:field])
      value ? value.wrap(:a, href: value) : '-'
    end
  end

  def as_email opts
    proc do |o|
      value = o.send(opts[:field])
      value ? value.wrap(:a, href: 'mailto:%s' % value) : '-'
    end
  end

  def as_object opts
    proc do |o|
      value = o.send(opts[:field])
      value.as_scope_link
    end
  end

  def as_sentence opts
    proc do |o|
      values = o.send(opts[:field])
      values = values.map(&:as_scope_link) if values.first && values.first.is_a?(ApplicationModel)
      values.to_sentence
    end
  end

  def as_ago opts
    opts[:field] ||= :created_at
    opts[:align] ||= :right
    opts[:sort]  ||= true if opts[:sort].nil?

    proc do |o|
      Time.ago o.send(opts[:field]) rescue '-'
    end
  end

  def as_user opts
    opts[:title] ||= 'User'
    opts[:sort]  ||= :created_by

    proc do |o|
      user = o.creator
      name = user.name
      name += " &sdot; #{user.email}" if opts[:email]
      name
    end
  end

  def as_delete opts
    opts[:align] ||= :right
    opts[:width] ||= 30

    proc do |o|
      onclick = opts.delete(:onclick) || Proc.new { |o| "Api('#{o.api_path(:destroy)}').refresh(); return false;" }
      onclick = onclick.call o
      onclick = %[event.stopPropagation(); if (confirm('Sure to delete?')) { #{onclick} }]
      %[<i class="icon icon-trash gray" onmouseover="$(this).toggleClass('gray')" onmouseout="$(this).toggleClass('gray')" onclick="#{onclick}"></i>]
    end
  end

  def as_date opts
    opts[:align] ||= :right
    opts[:width] ||= 130

    proc do |o|
      o[opts[:field]].try(:short)
    end
  end

  def as_time opts
    opts[:align] ||= :right
    opts[:width] ||= 160

    proc do |o|
      o[opts[:field]].long
    end
  end

  def as_html opts
    proc do |o|
      o.send(opts[:field]).html_safe
    end
  end

  def as_tags opts
    proc do |o|
      tags = o.send(opts[:field] || :tags)
      tags.join(' &sdot; ')
    end
  end
end

###

module ApplicationHelper
  def table list, opts = {}, &block
    opts[:class] ||= 'table hover'

    table = AppTable.new list, opts
    table.href { |o| o.respond_to?(:scope_path) ? o.scope_path : nil }

    yield(table)

    if data = table.render
      unless opts[:no_box] || request.path.include?('dialog')
        data = data.tag(:div, class: 'box')
      end

      data += paginate(list).to_s if list.respond_to?(:paginate_page)
      data
    else
      unless opts[:not_found] == false
        not_found = opts[:not_found] || 'No records found'
        not_found = not_found.split($/).map { _1.tag(:p) }.join($/)
        not_found.tag('div', class: 'gray')
      end
    end
  end
end
