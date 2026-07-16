require 'spec_helper'

Lux.plugin Lux.fw_root.join('plugins/html')

describe HtmlTable do
  let(:mock_request) { double('request', params: {}, path: '/') }
  let(:mock_current) { double('current', request: mock_request) }

  let(:row1) { double('row1', name: 'Alice', email: 'alice@test.com') }
  let(:row2) { double('row2', name: 'Bob', email: 'bob@test.com') }

  let(:scope) do
    double('scope').tap do |s|
      allow(s).to receive(:first).and_return(row1)
      allow(s).to receive(:all).and_return([row1, row2])
    end
  end

  before do
    allow(Lux).to receive(:current).and_return(mock_current)
  end

  describe '#col' do
    it 'adds column by field name' do
      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      expect(html).to include('Name')
      expect(html).to include('Alice')
      expect(html).to include('Bob')
    end

    it 'adds column with block' do
      t = HtmlTable.new(scope)
      t.col(title: 'Full') { |o| ">> #{o.name}" }
      html = t.render

      expect(html).to include('Full')
      expect(html).to include('>> Alice')
    end

    it 'adds column with custom title' do
      t = HtmlTable.new(scope)
      t.col :name, title: 'User name'
      html = t.render

      expect(html).to include('User name')
    end

    it 'adds column with width' do
      t = HtmlTable.new(scope)
      t.col :name, width: 200
      html = t.render

      expect(html).to include('width: 200px')
      expect(html).to include('<colgroup>')
      expect(html).to include('data-cols=')
    end

    it 'adds column with min_width' do
      t = HtmlTable.new(scope)
      t.col :name, min_width: 180
      html = t.render

      expect(html).to include('min-width: 180px')
      expect(html).not_to include('width="180"')
    end

    it 'adds column with align shorthand' do
      t = HtmlTable.new(scope)
      t.col :name, align: :c
      html = t.render

      expect(html).to include('text-align: center')
    end
  end

  describe '#render' do
    it 'wraps in app-table div' do
      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      expect(html).to include('class="app-table"')
    end

    it 'renders thead and tbody' do
      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      expect(html).to include('<thead>')
      expect(html).to include('<tbody>')
    end

    it 'returns nil for empty scope' do
      empty = double('empty', first: nil)
      t = HtmlTable.new(empty)
      t.col :name

      expect(t.render).to be_nil
    end

    it 'applies table class from opts' do
      t = HtmlTable.new(scope, class: 'striped')
      t.col :name
      html = t.render

      expect(html).to include('class="striped"')
    end
  end

  describe '#onclick' do
    it 'adds onclick to rows' do
      t = HtmlTable.new(scope)
      t.col :name
      t.onclick { |o| "alert('#{o.name}')" }
      html = t.render

      expect(html).to include("alert('Alice')")
      expect(html).to include("alert('Bob')")
    end
  end

  describe '#search' do
    it 'stores search definition' do
      t = HtmlTable.new(scope)
      t.search(:q) { |s, v| s }

      expect(t.instance_variable_get(:@searches).length).to eq(1)
      expect(t.instance_variable_get(:@searches).first[0]).to eq(:q)
    end

    it 'defaults type to text' do
      t = HtmlTable.new(scope)
      t.search(:q) { |s, v| s }

      expect(t.instance_variable_get(:@searches).first[1]).to eq(:text)
    end

    it 'applies search filter from params' do
      filtered = double('filtered')
      allow(filtered).to receive(:first).and_return(row1)
      allow(filtered).to receive(:all).and_return([row1])
      allow(mock_request).to receive(:params).and_return({ 'q' => 'Alice' })

      t = HtmlTable.new(scope)
      t.col :name
      t.search(:q) { |s, v| filtered }
      html = t.render

      expect(html).to include('Alice')
      expect(html).not_to include('Bob')
    end

    it 'skips search when param is empty' do
      allow(mock_request).to receive(:params).and_return({ 'q' => '' })

      t = HtmlTable.new(scope)
      t.col :name
      t.search(:q) { |s, v| raise 'should not be called' }
      html = t.render

      expect(html).to include('Alice')
    end
  end

  describe '#default_order' do
    it 'applies default order when no sort param' do
      ordered = double('ordered')
      allow(ordered).to receive(:first).and_return(row2)
      allow(ordered).to receive(:all).and_return([row2, row1])

      t = HtmlTable.new(scope)
      t.col :name
      t.default_order { |s| ordered }
      html = t.render

      expect(html).to include('Bob')
    end
  end

  describe '#scope_filter' do
    it 'applies scope filter' do
      filtered = double('filtered')
      allow(filtered).to receive(:first).and_return(row1)
      allow(filtered).to receive(:all).and_return([row1])

      t = HtmlTable.new(scope)
      t.col :name
      t.scope_filter { |s| filtered }
      html = t.render

      expect(html).to include('Alice')
    end
  end

  describe '#before' do
    it 'can be overridden to filter scope' do
      t = HtmlTable.new(scope)
      t.col :name

      def t.before scope
        scope
      end

      expect(t.render).to include('Alice')
    end
  end

  describe 'sorting' do
    it 'renders sort link when sort: true' do
      allow(mock_request).to receive(:params).and_return({})
      allow(mock_request).to receive(:path).and_return('/admin/users')

      t = HtmlTable.new(scope)
      t.col :name, sort: true
      html = t.render

      expect(html).to include('table-sort')
      expect(html).to include('t-sort=a-name')
    end

    it 'toggles sort direction in link' do
      allow(mock_request).to receive(:params).and_return({ 't-sort' => 'a-name' })
      allow(mock_request).to receive(:path).and_return('/admin/users')
      allow(scope).to receive(:respond_to?).with(:order).and_return(true)
      allow(scope).to receive(:xwhere).and_return(scope)
      allow(scope).to receive(:order).and_return(scope)

      t = HtmlTable.new(scope)
      t.col :name, sort: true
      html = t.render

      expect(html).to include('t-sort=d-name')
    end

    it 'applies initial ascending sort with sort: :a' do
      sorted_scope = double('sorted')
      allow(scope).to receive(:respond_to?).with(:order).and_return(true)
      allow(scope).to receive(:xwhere).and_return(scope)
      allow(scope).to receive(:order).with(Sequel.asc(:name)).and_return(sorted_scope)
      allow(sorted_scope).to receive(:first).and_return(row1)
      allow(sorted_scope).to receive(:all).and_return([row1, row2])

      t = HtmlTable.new(scope)
      t.col :name, sort: :a
      html = t.render

      expect(html).to include('Alice')
    end

    it 'applies initial descending sort with sort: :d' do
      sorted_scope = double('sorted')
      allow(scope).to receive(:respond_to?).with(:order).and_return(true)
      allow(scope).to receive(:xwhere).and_return(scope)
      allow(scope).to receive(:order).with(Sequel.desc(:name)).and_return(sorted_scope)
      allow(sorted_scope).to receive(:first).and_return(row2)
      allow(sorted_scope).to receive(:all).and_return([row2, row1])

      t = HtmlTable.new(scope)
      t.col :name, sort: :d
      html = t.render

      expect(html).to include('Bob')
    end

    it 'params override initial sort' do
      allow(mock_request).to receive(:params).and_return({ 't-sort' => 'd-name' })

      sorted_scope = double('sorted')
      allow(scope).to receive(:respond_to?).with(:order).and_return(true)
      allow(scope).to receive(:xwhere).and_return(scope)
      allow(scope).to receive(:order).with(Sequel.desc(:name)).and_return(sorted_scope)
      allow(sorted_scope).to receive(:first).and_return(row2)
      allow(sorted_scope).to receive(:all).and_return([row2, row1])

      t = HtmlTable.new(scope)
      t.col :name, sort: :a
      html = t.render

      expect(html).to include('Bob')
    end

    it 'applies ascending sort from params' do
      allow(mock_request).to receive(:params).and_return({ 't-sort' => 'a-name' })

      sorted_scope = double('sorted')
      allow(scope).to receive(:respond_to?).with(:order).and_return(true)
      allow(scope).to receive(:xwhere).and_return(scope)
      allow(scope).to receive(:order).with(Sequel.asc(:name)).and_return(sorted_scope)
      allow(sorted_scope).to receive(:first).and_return(row1)
      allow(sorted_scope).to receive(:all).and_return([row1, row2])

      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      expect(html).to include('Alice')
    end

    it 'applies descending sort from params' do
      allow(mock_request).to receive(:params).and_return({ 't-sort' => 'd-name' })

      sorted_scope = double('sorted')
      allow(scope).to receive(:respond_to?).with(:order).and_return(true)
      allow(scope).to receive(:xwhere).and_return(scope)
      allow(scope).to receive(:order).with(Sequel.desc(:name)).and_return(sorted_scope)
      allow(sorted_scope).to receive(:first).and_return(row2)
      allow(sorted_scope).to receive(:all).and_return([row2, row1])

      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      expect(html).to include('Bob')
    end
  end

  describe 'prepare_as_blocks' do
    it 'raises for unknown as type' do
      t = HtmlTable.new(scope)
      t.col :name, as: :unknown_type

      expect { t.render }.to raise_error(ArgumentError, /not defined/)
    end
  end

  describe 'render_cell' do
    it 'raises when column has no field, as, or block' do
      t = HtmlTable.new(scope)
      t.col(title: 'Empty')

      expect { t.render }.to raise_error(ArgumentError, /requires :field, :as, or a block/)
    end
  end

  describe 'as types' do
    let(:now) { Time.new(2025, 3, 15, 10, 30, 0) }
    let(:row1) { double('row1', active: true, created_at: now, price: 1234.5, score: 0.856, email: 'alice@test.com', tags: ['a', 'b'], bio: 'x' * 100, avatar: '/img/alice.png') }
    let(:row2) { double('row2', active: false, created_at: nil, price: nil, score: nil, email: nil, tags: [], bio: 'short', avatar: nil) }

    it 'as_boolean renders checkmark for true' do
      t = HtmlTable.new(scope)
      t.col :active, as: :boolean
      html = t.render

      expect(html).to include('&#10003;')
    end

    it 'as_date formats date' do
      t = HtmlTable.new(scope)
      t.col :created_at, as: :date
      html = t.render

      expect(html).to include('2025-03-15')
    end

    it 'as_datetime formats datetime' do
      t = HtmlTable.new(scope)
      t.col :created_at, as: :datetime
      html = t.render

      expect(html).to include('2025-03-15 10:30')
    end

    it 'as_number formats with commas' do
      allow(row1).to receive(:count).and_return(1234567)
      allow(row2).to receive(:count).and_return(42)

      t = HtmlTable.new(scope)
      t.col :count, as: :number
      html = t.render

      expect(html).to include('1,234,567')
      expect(html).to include('42')
    end

    it 'as_currency formats to 2 decimals' do
      t = HtmlTable.new(scope)
      t.col :price, as: :currency
      html = t.render

      expect(html).to include('1234.50')
    end

    it 'as_truncate truncates long text' do
      t = HtmlTable.new(scope)
      t.col :bio, as: :truncate
      html = t.render

      expect(html).to include('...')
      expect(html).to include('short')
    end

    it 'as_truncate respects custom limit' do
      t = HtmlTable.new(scope)
      t.col :bio, as: :truncate, limit: 10
      html = t.render

      expect(html).to include('xxxxxxxxxx...')
    end

    it 'as_percent formats as percentage' do
      t = HtmlTable.new(scope)
      t.col :score, as: :percent
      html = t.render

      expect(html).to include('85.6%')
    end

    it 'as_email renders mailto link' do
      t = HtmlTable.new(scope)
      t.col :email, as: :email
      html = t.render

      expect(html).to include('mailto:alice@test.com')
      expect(html).to include('alice@test.com')
    end

    it 'as_list joins array values' do
      t = HtmlTable.new(scope)
      t.col :tags, as: :list
      html = t.render

      expect(html).to include('a, b')
    end

    it 'as_image renders img tag' do
      t = HtmlTable.new(scope)
      t.col :avatar, as: :image
      html = t.render

      expect(html).to include('/img/alice.png')
      expect(html).to include('width: 40px')
    end
  end
end
