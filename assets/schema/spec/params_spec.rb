require 'spec_helper'

describe 'tesing params' do
  def set(*args)
    Lux.type(*args)
  end

  context 'global checks and' do
    it 'raises error on not existing required attribute' do
      expect { set :wtf, true }.to raise_error ArgumentError
    end
  end

  context 'validates' do
    it 'boolean' do
      expect(set :boolean, true).to eq true
      expect(set :boolean, 'true').to eq true
      expect(set :boolean, 'false').to eq false
      expect(set :boolean, 1).to eq true
      expect(set :boolean, 'on').to eq true
      expect(set :boolean, nil, default: false).to eq false
      expect { set :boolean, 'aaa' }.to raise_error TypeError
    end

    it 'integer' do
      expect(set :integer, 123).to eq 123
      expect(set :integer, '123').to eq 123
      expect(set :integer, 0).to eq 0
      expect(set :integer, '0').to eq 0
      expect(set :integer, nil, req: true).to eq(nil)
      expect(set :integer, nil).to eq nil
      expect(set :integer, nil, default: 1).to eq 1

      expect { set :integer, 100, max: 99  }.to raise_error TypeError
      expect { set :integer, 99,  min: 100 }.to raise_error TypeError
    end

    it 'string' do
      expect(set :string, 123).to eq '123'
      expect(set :string, ' 123 ').to eq '123'
      expect(set :string, nil, default: '').to eq ''
    end

    it 'float' do
      expect(set :float, '1.2345').to eq 1.2345
      expect(set :float, 1.2345).to eq 1.2345
      expect(set :float, 1.2345, round: 2).to eq 1.23
      expect(set :float, nil, round: 2).to eq nil

      expect { set :float, 100, max: 99  }.to raise_error TypeError
      expect { set :float, 99,  min: 100 }.to raise_error TypeError
    end

    it 'date' do
      expect(set :date, '1.2.2345.').to eq DateTime.parse('1.2.2345.')
      expect(set :date, '1.2.2345. 13:34').to eq DateTime.parse('1.2.2345.')
      expect { set :date, '1.2.2345.', min: '1.2.3345.' }.to raise_error TypeError
      expect { set :date, '1.2.2345.', max: '1.2.1345.' }.to raise_error TypeError
    end

    it 'datetime' do
      expect(set :datetime, '1.2.2345.').to eq DateTime.parse('1.2.2345.')
      expect(set :datetime, '1.2.2345. 13:34').to eq DateTime.parse('1.2.2345 13:34')
      expect { set :date, '1.2.2345.', min: '1.2.3345.' }.to raise_error TypeError
      expect { set :date, '1.2.2345.', max: '1.2.1345.' }.to raise_error TypeError
    end

    it 'hash' do
      expect(set :hash, { foo: 'bar' }).to eq({ foo: 'bar' })
      expect(set :hash, { foo: 'bar', bar: 'baz' }, allow: [:foo]).to eq({ foo: 'bar' })
    end
  end

  context 'various checks as' do
    it 'checks values in params' do
      expect(set :string, 'red', values: ['red', 'green', 'blue']).to eq 'red'
      expect { set :string, 'red', values: ['green', 'blue'] }.to raise_error TypeError
    end
  end
end
