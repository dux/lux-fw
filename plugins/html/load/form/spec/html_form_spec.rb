require 'spec_helper'

Lux.plugin Lux.fw_root.join('plugins/html')

describe HtmlForm do
  let(:mock_params) { {} }
  let(:mock_request) { double('request', params: mock_params) }
  let(:mock_current) { double('current', uid: 'test123', request: mock_request, locale: 'en') }

  before do
    allow(Lux).to receive(:current).and_return(mock_current)
  end

  describe '#initialize' do
    it 'accepts string as action' do
      form = HtmlForm.new('/submit')
      expect(form.opts[:action]).to eq('/submit')
      expect(form.object).to be_nil
    end

    it 'defaults method to post' do
      form = HtmlForm.new
      expect(form.opts[:method]).to eq('post')
    end

    it 'generates unique id' do
      form = HtmlForm.new
      expect(form.opts[:id]).to eq('form-test123')
    end

    it 'accepts custom opts' do
      form = HtmlForm.new(action: '/foo', method: 'get')
      expect(form.opts[:method]).to eq('get')
      expect(form.opts[:action]).to eq('/foo')
    end
  end

  describe '#render' do
    it 'renders form tag' do
      form = HtmlForm.new('/submit')
      html = form.render { |f| 'content' }

      expect(html).to include('<form')
      expect(html).to include('</form>')
      expect(html).to include('content')
      expect(html).to include('method="post"')
    end

    it 'renders with pushed data' do
      form = HtmlForm.new('/submit')
      form.push '<input name="a">'
      form.push '<input name="b">'
      html = form.render

      expect(html).to include('<input name="a">')
      expect(html).to include('<input name="b">')
    end

    it 'wraps in disabled fieldset when disabled' do
      form = HtmlForm.new('/submit', disabled: true)
      html = form.render { 'content' }

      expect(html).to include('<fieldset')
      expect(html).to include('disabled')
    end

    it 'adds enctype for file inputs' do
      form = HtmlForm.new('/upload')
      html = form.render { '<input type="file">' }

      expect(html).to include('enctype="multipart/form-data"')
    end

    it 'skips enctype for get method' do
      form = HtmlForm.new('/search', method: 'get')
      html = form.render { '<input type="file">' }

      expect(html).not_to include('enctype')
    end
  end

  describe '#input' do
    it 'renders input via HtmlInput' do
      form = HtmlForm.new
      html = form.input :email, as: :email

      expect(html).to include('type="email"')
    end
  end

  describe '#row' do
    it 'renders labeled row with block' do
      form = HtmlForm.new
      html = form.row('Name') { '<input>' }

      expect(html).to include('form-row')
      expect(html).to include('Name')
      expect(html).to include('<input>')
    end

    it 'renders row with input' do
      form = HtmlForm.new
      html = form.row :name, as: :string, value: 'test'

      expect(html).to include('form-row')
      expect(html).to include('Name')
    end

    it 'renders hidden row directly' do
      form = HtmlForm.new
      html = form.row :token, as: :hidden, value: 'abc'

      expect(html).to include('type="hidden"')
      expect(html).not_to include('form-row')
    end

    it 'renders hint' do
      form = HtmlForm.new
      html = form.row :name, as: :string, hint: 'Enter your name'

      expect(html).to include('Enter your name')
      expect(html).to include('<small')
    end

    it 'renders info' do
      form = HtmlForm.new
      html = form.row :name, as: :string, info: 'Required field'

      expect(html).to include('Required field')
    end
  end

  describe '#submit' do
    it 'renders submit button' do
      form = HtmlForm.new
      html = form.submit 'Save'

      expect(html).to include('type="submit"')
      expect(html).to include('Save')
      expect(html).to include('form-submit')
    end

    it 'defaults to create when no object' do
      form = HtmlForm.new
      html = form.submit

      expect(html).to include('create')
      expect(html).to include('ui-icon')
    end

    it 'renders cancel link' do
      form = HtmlForm.new
      html = form.submit 'Save', cancel: '/back'

      expect(html).to include('href="/back"')
      expect(html).to include('cancel')
    end

    it 'renders back link' do
      form = HtmlForm.new
      html = form.submit 'Save', back: '/list'

      expect(html).to include('href="/list"')
      expect(html).to include('go back')
    end

    it 'accepts hash as first argument' do
      form = HtmlForm.new
      html = form.submit class: 'btn-lg'

      expect(html).to include('class="btn-lg"')
    end
  end

  describe '#fieldset' do
    it 'renders fieldset with title' do
      form = HtmlForm.new
      html = form.fieldset('Details') { 'content' }

      expect(html).to include('<fieldset>')
      expect(html).to include('<legend>Details</legend>')
      expect(html).to include('content')
    end

    it 'renders fieldset with description' do
      form = HtmlForm.new
      html = form.fieldset('Details', 'Extra info') { 'content' }

      expect(html).to include('Extra info')
    end

    it 'hides border when no title' do
      form = HtmlForm.new
      html = form.fieldset { 'content' }

      expect(html).to include('border-top: none')
    end
  end
end
