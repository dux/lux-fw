require 'spec_helper'

describe Lux::Response::Header do
  let(:header) { Lux::Response::Header.new }

  describe '#[] and #[]=' do
    it 'sets and gets values (case-insensitive)' do
      header['Content-Type'] = 'text/html'
      expect(header['content-type']).to eq('text/html')
      expect(header['Content-Type']).to eq('text/html')
    end

    it 'returns nil for missing keys' do
      expect(header['x-missing']).to be_nil
    end
  end

  describe '#merge' do
    it 'merges a hash of headers (case-insensitive)' do
      header.merge({
        'Content-Type' => 'text/html',
        'X-Custom' => 'value'
      })

      expect(header['content-type']).to eq('text/html')
      expect(header['x-custom']).to eq('value')
    end

    it 'returns the merged data' do
      result = header.merge({ 'X-Test' => '1' })
      expect(result).to be_a(Hash)
      expect(result['x-test']).to eq('1')
    end
  end

  describe '#delete' do
    it 'removes a header (case-insensitive)' do
      header['X-Remove'] = 'value'
      header.delete('x-remove')
      expect(header['x-remove']).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns all headers as a hash' do
      header['x-foo'] = 'bar'
      header['x-baz'] = 'qux'

      h = header.to_h
      expect(h).to eq({ 'x-foo' => 'bar', 'x-baz' => 'qux' })
    end

    it 'returns empty hash when no headers set' do
      expect(header.to_h).to eq({})
    end
  end
end
