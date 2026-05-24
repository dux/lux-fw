require 'test_helper'

class ApiExporter < Lux::JsonExporter
  before do
    opts[:full] ||= false
  end

  after do
    if json[:email]
      json[:email] = json[:email].downcase
    end
  end
end

class UserExporter < ApiExporter
  define do |opt|
    prop :name
    prop :email

    if opt[:full]
      prop :bio, 'Full user bio: %s' % model.bio
    end
  end
end

####

class CustomExporter < Lux::JsonExporter
  def before
    # this runs first
    json[:foo] = [1]
  end

  after do
    json[:foo] = json[:foo].join('-')
  end
end

class ChildExporter < CustomExporter
  def before
    super
    response[:foo].push 2
  end

  define do
    prop :name

    # once defined, params in opts and response can be accessed as method names
    # response is alias to json
    response[:foo].push 3
  end
end

###

describe Lux::JsonExporter do
  it 'expects as expected' do
    model  = Struct.new(:name).new('Dux')
    export = ChildExporter.export(model)
    _(export).must_equal({ name: 'Dux', foo: '1-2-3' })
  end
end

describe UserExporter do
  def model
    @model ||= Struct.new(:name, :email, :bio)
  end

  def opts
    nil
  end

  def user
    @user ||= model.new('Dux', 'DUX@foo.bar', 'charming chonker')
  end

  def export
    UserExporter.export(user, opts)
  end

  describe 'without opts' do
    it 'exports slim user' do
      _(export).must_equal({ name: 'Dux', email: 'dux@foo.bar' })
    end
  end

  describe 'with opts' do
    def opts
      { full: true }
    end

    it 'exports slim user' do
      _(export).must_equal({ name: 'Dux', email: 'dux@foo.bar', bio: 'Full user bio: %s' % user.bio })
    end
  end
end
