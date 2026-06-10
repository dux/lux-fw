require 'test_helper'

# Behavior lock for the vendored class-attributes macro
# (Lux::Utils::ClassAttributes). `cattr` is patched onto Class/Object; these
# cover the paths Controller/Mailer/ViewCell and the db plugins rely on.
describe 'Lux::Utils::ClassAttributes (cattr)' do
  describe 'class: true' do
    it 'defines a class getter/setter seeded with the default' do
      k = Class.new { cattr :layout, class: true, default: 'main' }
      _(k.layout).must_equal 'main'
      k.layout = 'admin'
      _(k.layout).must_equal 'admin'
    end

    it 'inherits the default but lets a subclass override without touching the parent' do
      parent = Class.new { cattr :root, class: true, default: './app/views' }
      child  = Class.new(parent)

      _(child.root).must_equal './app/views'    # inherited
      child.root = './engine/views'
      _(child.root).must_equal './engine/views'
      _(parent.root).must_equal './app/views'   # parent untouched
    end
  end

  describe 'instance: true' do
    it 'reads and writes the class-level value from an instance' do
      k   = Class.new { cattr :mode, class: true, instance: true, default: :ro }
      obj = k.new

      _(obj.mode).must_equal :ro
      obj.mode = :rw
      _(obj.mode).must_equal :rw
      _(k.mode).must_equal :rw                  # same backing store as the class
    end
  end

  describe 'proxy form (no declared accessor)' do
    it 'stores and reads via cattr.<name>= / cattr.<name>' do
      k = Class.new { cattr.token = 'abc' }
      _(k.cattr.token).must_equal 'abc'
    end
  end

  describe 'defaults' do
    it 'seeds a literal default once and shares it' do
      k = Class.new { cattr :list, class: true, default: [] }
      k.list << 1
      _(k.list).must_equal [1]                  # same array, append persists
    end

    it 'treats a proc default as a lazy value re-evaluated on each read' do
      k = Class.new { cattr :fresh, class: true, default: proc { Object.new } }
      _(k.fresh).wont_be_same_as k.fresh
    end
  end

  it 'raises when reading an undeclared attribute' do
    k = Class.new
    _ { k.cattr.nope }.must_raise ArgumentError
  end
end
