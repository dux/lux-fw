require 'spec_helper'

class Foo
  method_attr :name
  method_attr :param do |field, opts={}|
    opts = { type: opts } if opts.class != Hash
    opts[:name] = field
    opts[:type] ||= String
    opts
  end

  name "Test method desc"
  param :email, :email
  param :age, Integer
  def test1
  end

  name "Test method desc"
  param :email1, req: 'Email1 is req'
  param :email2, req: true
  def test2
  end
end

###

describe MethodAttributes do

  it 'should return valid data hash' do
    data = Foo.method_attr

    expect(data[:test1][:param][0][:name]).to eq :email
    expect(data[:test1][:param][0][:type]).to eq :email

    expect(data[:test1][:param][1][:name]).to eq :age
    expect(data[:test1][:param][1][:type]).to be Integer

    expect(data[:test2][:param][0][:name]).to eq :email1
    expect(data[:test2][:param][0][:req]).to eq 'Email1 is req'

    expect(data[:test2][:param][1][:name]).to eq :email2
    expect(data[:test2][:param][1][:req]).to be true
  end

end
