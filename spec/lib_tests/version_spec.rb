require 'test_helper'

describe Lux::Version do
  describe '.format' do
    it 'renders v<digits> as v<a>.<b>.<c>' do
      {
        'v123'   => 'v1.2.3',
        'v1123'  => 'v11.2.3',
        'v81'    => 'v0.8.1',
        'v5'     => 'v0.0.5',
        'v100'   => 'v1.0.0',
        'v1234'  => 'v12.3.4',
        'dev'    => 'dev',
        ''       => '',
        'v1.2.3' => 'v1.2.3'
      }.each { |raw, want| _(Lux::Version.format(raw)).must_equal want }
    end
  end

  it 'VERSION is the semver gem version' do
    _(Lux::VERSION).must_equal Lux::Version.gem
  end

  it 'gem version drops the leading v' do
    _(Lux::Version.gem).must_match(/\A\d/)
  end
end
