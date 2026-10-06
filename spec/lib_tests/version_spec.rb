require 'test_helper'

describe Lux::Version do
  it 'string is the dotted stamp or dev' do
    _(Lux::Version.string).must_match(/\A(v\d+\.\d\.\d|dev)\z/)
  end

  it 'VERSION is the semver gem version' do
    _(Lux::VERSION).must_equal Lux::Version.gem
  end

  it 'gem version drops the leading v' do
    _(Lux::Version.gem).must_match(/\A\d/)
  end
end
