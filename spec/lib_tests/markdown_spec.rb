require 'test_helper'

describe Lux::Utils::Markdown do
  it 'renders paragraphs and inline code' do
    html = Lux::Utils::Markdown.to_html('Hello `world`')
    _(html).must_include '<p>'
    _(html).must_include '<code>world</code>'
  end

  it 'renders GFM tables' do
    html = Lux::Utils::Markdown.to_html("| a | b |\n|---|---|\n| 1 | 2 |")
    _(html).must_include '<table>'
    _(html).must_include '<th>a</th>'
    _(html).must_include '<td>1</td>'
  end

  it 'renders fenced code blocks' do
    html = Lux::Utils::Markdown.to_html("```ruby\nputs 1\n```")
    _(html).must_include '<pre'
    _(html).must_include 'lang="ruby"'
    _(html).must_include 'puts'
  end

  it 'escapes raw HTML by default and allows it with unsafe: true' do
    _(Lux::Utils::Markdown.to_html('<script>x</script>')).must_include '&lt;script&gt;'
    _(Lux::Utils::Markdown.to_html('<b>x</b>', unsafe: true)).must_include '<b>x</b>'
  end
end
