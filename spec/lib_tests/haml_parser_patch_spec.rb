require 'test_helper'

describe 'Haml parser patch (Tailwind classes)' do
  def render(src)
    Tilt['haml'].new(escape_html: false) { src }.render.strip
  end

  def parse_classes(src)
    line = src.start_with?('%') ? src : "%div#{src}"
    attrs = line.match(/\A%[-:\w]+(.*)\z/m)[1]
    Haml::Parser.consume_class_and_id(attrs)
    Haml::Parser.parse_class_and_id(attrs[0...Haml::Parser.consume_class_and_id(attrs)])
  end

  it 'keeps arbitrary values with colons as one class' do
    _(parse_classes('.arbitrary-[value:with:colons]')['class']).must_equal 'arbitrary-[value:with:colons]'
    _(render('%div.arbitrary-[value:with:colons] x')).must_equal '<div class="arbitrary-[value:with:colons]">x</div>'
  end

  it 'keeps dots inside bracket arbitrary values' do
    _(parse_classes('.max-w-[1.5rem]')['class']).must_equal 'max-w-[1.5rem]'
    _(render('%div.max-w-[1.5rem] x')).must_equal '<div class="max-w-[1.5rem]">x</div>'
  end

  it 'treats hash inside brackets as class text, not an id' do
    _(parse_classes('.bg-[#fff]')['class']).must_equal 'bg-[#fff]'
    _(render('%div.bg-[#fff] x')).must_equal '<div class="bg-[#fff]">x</div>'
  end

  it 'treats hash after hyphen as class text' do
    _(parse_classes('.bg-#fff')['class']).must_equal 'bg-#fff'
  end

  it 'still parses a real id when hash is a delimiter' do
    attrs = parse_classes('#sidebar.bg-[#fff]')
    _(attrs['id']).must_equal 'sidebar'
    _(attrs['class']).must_equal 'bg-[#fff]'
    _(render('%div#sidebar.bg-[#fff] x')).must_equal '<div class="bg-[#fff]" id="sidebar">x</div>'
  end

  it 'allows slash and important modifiers in dot classes' do
    _(render('%div.w-1/2 x')).must_equal '<div class="w-1/2">x</div>'
    _(render('%div.!text-red x')).must_equal '<div class="!text-red">x</div>'
  end

  it 'keeps tailwind variant colons in dot classes' do
    _(render('%div.hover:underline x')).must_equal '<div class="hover:underline">x</div>'
    # attribute escaper entity-encodes & in the HTML source; DOM class is still [&_b]:...
    _(render('%div.[&_b]:text-amber x')).must_equal '<div class="[&amp;_b]:text-amber">x</div>'
  end

  it 'does not treat inline = output as part of the class' do
    _(render('.flex-1= "hello"')).must_equal '<div class="flex-1">hello</div>'
    nested = render(".flex.gap-3\n  .flex-1= \"a\"\n  .w-24= \"b\"")
    _(nested).must_include '<div class="flex gap-3">'
    _(nested).must_include '<div class="flex-1">a</div>'
    _(nested).must_include '<div class="w-24">b</div>'
    _(nested).wont_include 'flex-1='
    _(nested).wont_include 'w-24='
  end
end
