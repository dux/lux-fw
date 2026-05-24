require 'test_helper'

describe Lux::Utils::TimeDifference do
  describe '#humanize' do
    describe 'past dates' do
      it 'shows "just happened" for very recent times' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 5)
        _(td.humanize).must_equal 'just happened'
      end

      it 'shows minutes for recent past' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 180) # 3 minutes ago
        _(td.humanize).must_equal 'before 3 minutes'
      end

      it 'shows hours for past within a day' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 7200) # 2 hours ago
        _(td.humanize).must_equal 'before 2 hours'
      end

      it 'shows days for past within a month' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 86400 * 5) # 5 days ago
        _(td.humanize).must_equal 'before 5 days'
      end

      it 'shows months for past within a year' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 86400 * 60) # ~2 months ago
        _(td.humanize).must_equal 'before 2 months'
      end

      it 'shows years for distant past' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 86400 * 400) # ~1 year ago
        _(td.humanize).must_equal 'before 1 year'
      end
    end

    describe 'future dates' do
      it 'shows "in few seconds" for very near future' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now + 5)
        _(td.humanize).must_equal 'in few seconds'
      end

      it 'shows minutes for near future' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now + 300) # 5 minutes
        _(td.humanize).must_equal 'in 5 minutes'
      end

      it 'shows hours for future within a day' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now + 3600) # 1 hour
        _(td.humanize).must_equal 'in 1 hour'
      end

      it 'shows days for future within a month' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now + 86400 * 3) # 3 days
        _(td.humanize).must_equal 'in 3 days'
      end
    end

    describe 'singular vs plural' do
      it 'uses singular for value of 1' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 3600) # 1 hour ago
        _(td.humanize).must_equal 'before 1 hour'
      end

      it 'uses plural for values greater than 1' do
        td = Lux::Utils::TimeDifference.new(Time.now, Time.now - 7200) # 2 hours ago
        _(td.humanize).must_equal 'before 2 hours'
      end
    end

    describe 'single argument (end_date only)' do
      it 'compares against Time.now' do
        td = Lux::Utils::TimeDifference.new(Time.now - 3600) # 1 hour ago
        result = td.humanize
        _(result).must_match(/before 1 hour/)
      end
    end

    describe 'with Date class' do
      it 'shows "today" for same-day dates' do
        td = Lux::Utils::TimeDifference.new(Date.today, Date.today, Date)
        _(td.humanize).must_equal 'today'
      end
    end
  end
end
