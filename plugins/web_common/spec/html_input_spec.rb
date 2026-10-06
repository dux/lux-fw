require 'test_helper'

require_relative '../load/html/input/html_input'
require_relative '../load/html/input/html_input_custom'

describe HtmlInput do
  # Lux::Test::Case clears Thread.current[:lux] after every test, so the stub cannot leak.
  before do
    Thread.current[:lux] = Struct.new(:uid).new('test123')
  end

  describe '#initialize' do
    it 'accepts hash as first argument' do
      input = HtmlInput.new(disabled: true)
      _(input[:disabled]).must_equal true
    end

    it 'removes disabled when value is false string' do
      input = HtmlInput.new(disabled: 'false')
      _(input[:disabled]).must_be_nil
    end
  end

  describe '#render without model' do
    it 'renders text input by default' do
      input = HtmlInput.new
      html = input.render :name, value: 'Alice'

      assert_includes html, 'type="text"'
      assert_includes html, 'value="Alice"'
    end

    it 'renders with explicit as: :string' do
      input = HtmlInput.new
      html = input.render :name, as: :string, value: 'test'

      assert_includes html, 'type="text"'
    end

    it 'renders password input' do
      input = HtmlInput.new
      html = input.render :pass, as: :password

      assert_includes html, 'type="password"'
    end

    it 'renders email input' do
      input = HtmlInput.new
      html = input.render :mail, as: :email

      assert_includes html, 'type="email"'
    end

    it 'renders hidden input' do
      input = HtmlInput.new
      html = input.render :token, as: :hidden, value: 'abc'

      assert_includes html, 'type="hidden"'
      assert_includes html, 'value="abc"'
    end

    it 'renders file input' do
      input = HtmlInput.new
      html = input.render :avatar, as: :file

      assert_includes html, 'type="file"'
    end

    it 'auto-sets email placeholder' do
      input = HtmlInput.new
      html = input.render :email, as: :string

      assert_includes html, 'placeholder="email..."'
    end

    it 'auto-sets url placeholder' do
      input = HtmlInput.new
      html = input.render :website_url, as: :string

      assert_includes html, 'placeholder="https://..."'
    end

    it 'generates unique id' do
      input = HtmlInput.new
      html = input.render :name, as: :string

      assert_includes html, 'id="i_test123"'
    end
  end

  describe '#render with select' do
    it 'renders select from array collection' do
      input = HtmlInput.new
      html = input.render :role, as: :select, collection: [['admin', 'Admin'], ['user', 'User']]

      assert_includes html, '<select'
      assert_includes html, 'Admin'
      assert_includes html, 'User'
    end

    it 'marks selected option' do
      input = HtmlInput.new
      html = input.render :role, as: :select, value: 'admin', collection: [['admin', 'Admin'], ['user', 'User']]

      assert_includes html, 'selected="true"'
    end

    it 'renders null option' do
      input = HtmlInput.new
      html = input.render :role, as: :select, null: '-- pick --', collection: [['a', 'A']]

      assert_includes html, '-- pick --'
      assert_includes html, '<option value="">'
    end
  end

  describe '#render with select from hash' do
    it 'renders select from hash collection' do
      input = HtmlInput.new
      html = input.render :status, as: :select, collection: { active: 'Active', inactive: 'Inactive' }

      assert_includes html, 'Active'
      assert_includes html, 'Inactive'
    end
  end

  describe 'datetime input' do
    it 'renders datetime-local input' do
      input = HtmlInput.new
      html = input.render :starts_at, as: :datetime

      assert_includes html, 'type="datetime-local"'
    end
  end

  describe 'disabled input' do
    it 'renders disabled text input' do
      input = HtmlInput.new
      html = input.render :name, as: :disabled, value: 'locked'

      assert_includes html, 'disabled'
    end
  end
end
