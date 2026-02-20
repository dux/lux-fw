require 'spec_helper'

describe TimeDifference do
  describe '#humanize' do
    context 'past dates' do
      it 'shows "just happened" for very recent times' do
        td = TimeDifference.new(Time.now, Time.now - 5)
        expect(td.humanize).to eq('just happened')
      end

      it 'shows minutes for recent past' do
        td = TimeDifference.new(Time.now, Time.now - 180) # 3 minutes ago
        expect(td.humanize).to eq('before 3 minutes')
      end

      it 'shows hours for past within a day' do
        td = TimeDifference.new(Time.now, Time.now - 7200) # 2 hours ago
        expect(td.humanize).to eq('before 2 hours')
      end

      it 'shows days for past within a month' do
        td = TimeDifference.new(Time.now, Time.now - 86400 * 5) # 5 days ago
        expect(td.humanize).to eq('before 5 days')
      end

      it 'shows months for past within a year' do
        td = TimeDifference.new(Time.now, Time.now - 86400 * 60) # ~2 months ago
        expect(td.humanize).to eq('before 2 months')
      end

      it 'shows years for distant past' do
        td = TimeDifference.new(Time.now, Time.now - 86400 * 400) # ~1 year ago
        expect(td.humanize).to eq('before 1 year')
      end
    end

    context 'future dates' do
      it 'shows "in few seconds" for very near future' do
        td = TimeDifference.new(Time.now, Time.now + 5)
        expect(td.humanize).to eq('in few seconds')
      end

      it 'shows minutes for near future' do
        td = TimeDifference.new(Time.now, Time.now + 300) # 5 minutes
        expect(td.humanize).to eq('in 5 minutes')
      end

      it 'shows hours for future within a day' do
        td = TimeDifference.new(Time.now, Time.now + 3600) # 1 hour
        expect(td.humanize).to eq('in 1 hour')
      end

      it 'shows days for future within a month' do
        td = TimeDifference.new(Time.now, Time.now + 86400 * 3) # 3 days
        expect(td.humanize).to eq('in 3 days')
      end
    end

    context 'singular vs plural' do
      it 'uses singular for value of 1' do
        td = TimeDifference.new(Time.now, Time.now - 3600) # 1 hour ago
        expect(td.humanize).to eq('before 1 hour')
      end

      it 'uses plural for values greater than 1' do
        td = TimeDifference.new(Time.now, Time.now - 7200) # 2 hours ago
        expect(td.humanize).to eq('before 2 hours')
      end
    end

    context 'single argument (end_date only)' do
      it 'compares against Time.now' do
        td = TimeDifference.new(Time.now - 3600) # 1 hour ago
        result = td.humanize
        expect(result).to match(/before 1 hour/)
      end
    end

    context 'with Date class' do
      it 'shows "today" for same-day dates' do
        td = TimeDifference.new(Date.today, Date.today, Date)
        expect(td.humanize).to eq('today')
      end
    end
  end
end
