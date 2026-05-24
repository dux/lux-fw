require 'test_helper'

describe Lux::Response::Header do
  def header
    @header ||= Lux::Response::Header.new
  end

  describe '#[] and #[]=' do
    it 'sets and gets values (case-insensitive)' do
      header['Content-Type'] = 'text/html'
      _(header['content-type']).must_equal 'text/html'
      _(header['Content-Type']).must_equal 'text/html'
    end

    it 'returns nil for missing keys' do
      _(header['x-missing']).must_be_nil
    end
  end

  describe '#merge' do
    it 'merges a hash of headers (case-insensitive)' do
      header.merge({
        'Content-Type' => 'text/html',
        'X-Custom' => 'value'
      })

      _(header['content-type']).must_equal 'text/html'
      _(header['x-custom']).must_equal 'value'
    end

    it 'returns the merged data' do
      result = header.merge({ 'X-Test' => '1' })
      _(result).must_be_kind_of Hash
      _(result['x-test']).must_equal '1'
    end
  end

  describe '#delete' do
    it 'removes a header (case-insensitive)' do
      header['X-Remove'] = 'value'
      header.delete('x-remove')
      _(header['x-remove']).must_be_nil
    end
  end

  describe '#to_h' do
    it 'returns all headers as a hash' do
      header['x-foo'] = 'bar'
      header['x-baz'] = 'qux'

      h = header.to_h
      _(h).must_equal({ 'x-foo' => 'bar', 'x-baz' => 'qux' })
    end

    it 'returns empty hash when no headers set' do
      _(header.to_h).must_equal({})
    end
  end
end
