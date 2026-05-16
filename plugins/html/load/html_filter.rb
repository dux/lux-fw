# create filter search forms
# = filter do |f|
#   = f.search

# class HtmlFilter
#   def search opts={}
#     opts[:name]        ||= :q
#     opts[:value]       ||= params[opts[:name]]
#     opts[:placeholder] ||= 'search...'
#     text opts
#   end

#   def text opts
#     opts[:class] ||= 'form-control'
#     opts[:type]  ||= 'text'
#     opts.tag(:input)
#   end
# end

class HtmlFilter
  HtmlTag self

  def initialize parent
    @parent = parent
    @out    = []
    @info   = []
  end

  def parent &block
    block ? @parent.instance_exec(&block) : @parent
  end

  def request
    @parent.request
  end

  def params
    @parent.params
  end

  def onsubmit what
    @onsubmit = what
  end

  def render_info
    return unless @info.first

    tag.ul(class: 'search-filter-info') do |n|
      for el in @info
        n.li { el }
      end
    end
  end

  def render_clear
    return if request.query_string == ''

    '<span style="padding: 0 10px;">&mdash;</span><a href="%s" class="btn btn-sm">clear</a>' % request.path
  end

  def render data
    opts = {}
    opts[:onsubmit] = @onsubmit if @onsubmit
    opts[:method]   = :get

    tag._search_filter do |n|
      n.form(opts) do |n|
        n.push data
        n.push render_clear
      end

      n.push render_info
    end
  end
end
