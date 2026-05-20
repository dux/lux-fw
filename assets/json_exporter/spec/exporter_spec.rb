require 'spec_helper'

###

JxCompany = Struct.new(:name, :address) do
  def creator
    JxUser.new('dux', 'dux@.net.hr')
  end

  def user
    JxUser.new('dux', 'dux@.net.hr')
  end
end

JxUser = Struct.new(:name, :email) do
  def company
    JxCompany.new('ACME', 'Nowhere 123')
  end
end

class SimpleExporter < Lux::JsonExporter
  before do
    opts[:version] ||= 1
  end

  after do
    prop :foo, :bar

    response[:meta] = {
      class: model.class.to_s
    }
  end

  ###

  def user
    opts[:user]
  end

  ###

  define :jx_company do
    prop :name
    prop :address
    prop :v_check, :version_one

    if opts.version >= 3
      prop :v_check, :version_three
    end

    if opts.version >= 4
      prop :extra, :spicy
    end

    prop :creator, export(model.user)
  end

  define :generic_name do
    prop :name

    response[:foo] = :bar
  end

  define JxUser do
    export :company, version: opts.version

    prop :v_check, :version_one

    if opts.version == 3
      prop :v_check, :version_three
    end

    prop :name
    prop :email
    prop :is_admin do
      user && user.name.include?('dux') ? true : false
    end
  end
end

class GenericExporter < SimpleExporter
  before do
    response[:bhistory] = [:first]
  end

  after do
    response[:ahistory] ||= []
    response[:ahistory].push :parent
  end

  define do
    prop :name

    prop(:calc) { model.num * 3 }
  end
end

class GenericExporterChild < GenericExporter
  before do
    response[:bhistory].push :second
  end

  after do
    response[:ahistory].push :child
  end

  define do
    prop :name
    prop :ahistory, [:start]

    response[:bhistory].push :third

    prop(:calc) { model.num * 3 }
  end
end

###

describe Lux::JsonExporter do
  it 'expects basic export to work' do
    name    = 'ACME 1'
    address = 'Nowhere 123'

    company = JxCompany.new(name, address)
    result  = SimpleExporter.export(company)

    expect(result[:name]).to eq(name)
    expect(result[:address]).to eq(address)
  end

  it 'exports complex object' do
    some_user = JxUser.new 'dux', 'dux@net.hr'
    response  = SimpleExporter.export some_user, user: some_user
    expect(response[:is_admin]).to eq(true)

    user     = JxUser.new 'dino', 'dux@net.hr'
    response = SimpleExporter.export user, user: user
    expect(response[:is_admin]).to eq(false)
  end

  it 'exports naked object' do
    company = JxCompany.new 'ACME 1', 'Nowhere 123'
    data = SimpleExporter.export company, exporter: :generic_name
    expect(data[:address]).to be(nil)
    expect(data[:foo]).to be(:bar)
  end

  it 'exports deep if needed' do
    user     = JxUser.new 'dux', 'dux@net.hr'
    response = SimpleExporter.export user, user: user, export_depth: 3

    expect(response[:company][:creator][:company][:name]).to eq('ACME')
  end

  it 'uses after filter' do
    user     = JxUser.new 'dux', 'dux@net.hr'
    response = SimpleExporter.export user, user: user, export_depth: 3
    expect(response[:foo]).to eq(:bar)
    expect(response[:meta][:class]).to eq('JxUser')
  end

  it 'uses right versions' do
    user     = JxUser.new 'dux', 'dux@net.hr'
    response = SimpleExporter.export user, version: 3
    expect(response[:company][:v_check]).to eq(:version_three)
    expect(response[:company][:extra]).to eq(nil)

    response = SimpleExporter.export user, version: 4
    expect(response[:company][:v_check]).to eq(:version_three)
    expect(response[:company][:extra]).to eq(:spicy)
  end

  it 'exports via generic exporter' do
    data   = HashWia.new({ name: 'foo', surname: 'bar', num: 5 })
    result = GenericExporter.export data
    expect(result[:calc]).to eq(15)
  end

  it 'applies filters as it should' do
    data   = HashWia.new({ name: 'dux', num: 1 })
    result = GenericExporterChild.export data

    expect(result[:bhistory].join('-')).to eq('first-second-third')
    expect(result[:ahistory].join('-')).to eq('start-parent-child')
  end
end
