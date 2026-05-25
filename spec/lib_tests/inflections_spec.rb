require 'test_helper'

# Guards for the custom inflections registered in lib/lux/loader.rb.
# These overrides matter for the enums plugin and any caller of
# String#singularize / String#pluralize.
describe 'String inflections (lux-fw overrides)' do
  describe 'pre-existing overrides' do
    it 'singularizes "statuses" to "status"' do
      _('statuses'.singularize).must_equal 'status'
    end

    it 'singularizes "bonuses" to "bonus"' do
      _('bonuses'.singularize).must_equal 'bonus'
    end

    it 'pluralizes "bonus" to "bonuses"' do
      _('bonus'.pluralize).must_equal 'bonuses'
    end

    it 'leaves "news" as uncountable' do
      _('news'.singularize).must_equal 'news'
      _('news'.pluralize).must_equal 'news'
    end
  end

  describe 'uncountable: data, media' do
    %w[data media].each do |word|
      it %(treats "#{word}" as uncountable) do
        _(word.singularize).must_equal word
        _(word.pluralize).must_equal word
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
        _(plural.singularize).must_equal singular
      end

      it %(pluralizes "#{singular}" to "#{plural}") do
        _(singular.pluralize).must_equal plural
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
        _(plural.singularize).must_equal singular
      end
    end
  end
end
