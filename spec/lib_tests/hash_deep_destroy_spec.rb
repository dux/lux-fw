require 'test_helper'

describe Hash do
  describe '#deep_destroy' do
    it 'removes the named keys' do
      hash = { name: 'plan', creator_ref: 'x', updated_at: 'y' }

      _(hash.deep_destroy(:creator_ref, :updated_at)).must_equal({ name: 'plan' })
    end

    it 'removes keys nested under any hash, string or symbol' do
      hash = { plan: { 'creator_ref' => 'x', name: 'p' }, outer: { inner: { creator_ref: 'y' } } }

      result = hash.deep_destroy(:creator_ref)
      _(result).must_equal({ plan: { name: 'p' }, outer: { inner: {} } })
    end

    it 'removes keys inside arrays of hashes' do
      hash = { rows: [{ creator_ref: 'x', name: 'a' }, { name: 'b' }, 'plain'] }

      _(hash.deep_destroy(:creator_ref)).must_equal({ rows: [{ name: 'a' }, { name: 'b' }, 'plain'] })
    end

    it 'does not mutate the receiver' do
      hash = { creator_ref: 'x' }
      hash.deep_destroy(:creator_ref)

      _(hash).must_equal({ creator_ref: 'x' })
    end
  end

  describe '#deep_destroy!' do
    it 'mutates the receiver in place' do
      hash = { plan: { creator_ref: 'x', name: 'p' } }
      hash.deep_destroy!(:creator_ref)

      _(hash).must_equal({ plan: { name: 'p' } })
    end
  end
end
