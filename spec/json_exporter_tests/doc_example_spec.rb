require 'spec_helper'

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
    expect(export).to eq({ name: 'Dux', foo: '1-2-3' })
  end
end

describe UserExporter do
  let!(:model)  { Struct.new(:name, :email, :bio) }
  let(:opts)    { nil }
  let!(:user)   { model.new('Dux', 'DUX@foo.bar', 'charming chonker') }
  let(:export)  { UserExporter.export(user, opts) }

  context 'without opts' do
    it 'exports slim user' do
      expect(export).to eq({ name: 'Dux', email: 'dux@foo.bar' })
    end
  end

  context 'with opts' do
    let(:opts) { { full: true } }

    it 'exports slim user' do
      expect(export).to eq({ name: 'Dux', email: 'dux@foo.bar', bio: 'Full user bio: %s' % user.bio })
    end
  end
end
