require 'spec_helper'

# Guards for the custom inflections registered in lib/lux/boot.rb.
# These overrides matter for the enums plugin and any caller of
# String#singularize / String#pluralize.
describe 'String inflections (lux-fw overrides)' do
  describe 'pre-existing overrides' do
    it 'singularizes "statuses" to "status"' do
      expect('statuses'.singularize).to eq('status')
    end

    it 'singularizes "bonuses" to "bonus"' do
      expect('bonuses'.singularize).to eq('bonus')
    end

    it 'pluralizes "bonus" to "bonuses"' do
      expect('bonus'.pluralize).to eq('bonuses')
    end

    it 'leaves "news" as uncountable' do
      expect('news'.singularize).to eq('news')
      expect('news'.pluralize).to eq('news')
    end
  end

  describe 'uncountable: data, media' do
    %w[data media].each do |word|
      it %(treats "#{word}" as uncountable) do
        expect(word.singularize).to eq(word)
        expect(word.pluralize).to eq(word)
      end
    end
  end

  describe 'irregular plurals' do
    {
      'criterion' => 'criteria',
      'axis'      => 'axes',
      'leaf'      => 'leaves',
      'focus'     => 'focuses'
    }.each do |singular, plural|
      it %(singularizes "#{plural}" to "#{singular}") do
        expect(plural.singularize).to eq(singular)
      end

      it %(pluralizes "#{singular}" to "#{plural}") do
        expect(singular.pluralize).to eq(plural)
      end
    end
  end

  describe 'common enum names still resolve correctly' do
    {
      'statuses'    => 'status',
      'priorities'  => 'priority',
      'kinds'       => 'kind',
      'targets'     => 'target',
      'categories'  => 'category',
      'roles'       => 'role',
      'states'      => 'state',
      'modes'       => 'mode',
      'permissions' => 'permission',
      'tags'        => 'tag',
      'matrices'    => 'matrix',
      'indices'     => 'index',
      'children'    => 'child',
      'people'      => 'person'
    }.each do |plural, singular|
      it %("#{plural}".singularize == "#{singular}") do
        expect(plural.singularize).to eq(singular)
      end
    end
  end
end
