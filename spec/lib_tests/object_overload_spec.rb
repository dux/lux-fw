require 'test_helper'

describe 'Object#try (ActiveSupport semantics)' do
  it 'sends when the receiver responds' do
    _('ab'.try(:upcase)).must_equal 'AB'
    _([1, 2].try(:fetch, 1)).must_equal 2
  end

  it 'returns nil for a missing method or a nil receiver' do
    _('ab'.try(:no_such_method)).must_be_nil
    _(nil.try(:upcase)).must_be_nil
  end

  it 'yields self to a bare block' do
    _(5.try { |n| n + 1 }).must_equal 6
  end
end
