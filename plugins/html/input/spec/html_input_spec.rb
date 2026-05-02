require 'spec_helper'

Lux.plugin Lux.fw_root.join('plugins/html')

describe HtmlInput do
  let(:mock_current) { double('current', uid: 'test123') }

  before do
    allow(Lux).to receive(:current).and_return(mock_current)
  end

  describe '#initialize' do
    it 'accepts hash as first argument' do
      input = HtmlInput.new(disabled: true)
      expect(input[:disabled]).to eq(true)
    end

    it 'removes disabled when value is false string' do
      input = HtmlInput.new(disabled: 'false')
      expect(input[:disabled]).to be_nil
    end
  end

  describe '#render without model' do
    it 'renders text input by default' do
      input = HtmlInput.new
      html = input.render :name, value: 'Alice'

      expect(html).to include('type="text"')
      expect(html).to include('value="Alice"')
    end

    it 'renders with explicit as: :string' do
      input = HtmlInput.new
      html = input.render :name, as: :string, value: 'test'

      expect(html).to include('type="text"')
    end

    it 'renders password input' do
      input = HtmlInput.new
      html = input.render :pass, as: :password

      expect(html).to include('type="password"')
    end

    it 'renders email input' do
      input = HtmlInput.new
      html = input.render :mail, as: :email

      expect(html).to include('type="email"')
    end

    it 'renders hidden input' do
      input = HtmlInput.new
      html = input.render :token, as: :hidden, value: 'abc'

      expect(html).to include('type="hidden"')
      expect(html).to include('value="abc"')
    end

    it 'renders file input' do
      input = HtmlInput.new
      html = input.render :avatar, as: :file

      expect(html).to include('type="file"')
    end

    it 'auto-sets email placeholder' do
      input = HtmlInput.new
      html = input.render :email, as: :string

      expect(html).to include('placeholder="email..."')
    end

    it 'auto-sets url placeholder' do
      input = HtmlInput.new
      html = input.render :website_url, as: :string

      expect(html).to include('placeholder="https://..."')
    end

    it 'generates unique id' do
      input = HtmlInput.new
      html = input.render :name, as: :string

      expect(html).to include('id="i_test123"')
    end
  end

  describe '#render with select' do
    it 'renders select from array collection' do
      input = HtmlInput.new
      html = input.render :role, as: :select, collection: [['admin', 'Admin'], ['user', 'User']]

      expect(html).to include('<select')
      expect(html).to include('Admin')
      expect(html).to include('User')
    end

    it 'marks selected option' do
      input = HtmlInput.new
      html = input.render :role, as: :select, value: 'admin', collection: [['admin', 'Admin'], ['user', 'User']]

      expect(html).to include('selected="true"')
    end

    it 'renders null option' do
      input = HtmlInput.new
      html = input.render :role, as: :select, null: '-- pick --', collection: [['a', 'A']]

      expect(html).to include('-- pick --')
      expect(html).to include('<option value="">')
    end
  end

  describe '#render with select from hash' do
    it 'renders select from hash collection' do
      input = HtmlInput.new
      html = input.render :status, as: :select, collection: { active: 'Active', inactive: 'Inactive' }

      expect(html).to include('Active')
      expect(html).to include('Inactive')
    end
  end

  describe 'datetime input' do
    it 'renders datetime-local input' do
      input = HtmlInput.new
      html = input.render :starts_at, as: :datetime

      expect(html).to include('type="datetime-local"')
    end
  end

  describe 'disabled input' do
    it 'renders disabled text input' do
      input = HtmlInput.new
      html = input.render :name, as: :disabled, value: 'locked'

      expect(html).to include('disabled')
    end
  end
end
