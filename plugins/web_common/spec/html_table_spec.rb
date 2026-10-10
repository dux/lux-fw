require 'test_helper'

require_relative '../load/html/table/html_table'
require_relative '../load/html/table/html_table_custom'

describe HtmlTable do
  def record **attrs
    Struct.new(*attrs.keys).new(*attrs.values)
  end

  # Stand-in for a Sequel dataset. HtmlTable only sorts when the scope
  # responds to :order, so xwhere/order exist only when orders: is given;
  # order raises KeyError for any sort expression not listed there.
  def dataset rows, orders: nil
    ds = Object.new
    ds.define_singleton_method(:first) { rows.first }
    ds.define_singleton_method(:all) { rows }

    if orders
      ds.define_singleton_method(:xwhere) { |*| ds }
      ds.define_singleton_method(:order) { |expr| orders.fetch(expr) }
    end

    ds
  end

  def request
    @request ||= Struct.new(:params, :path).new({}, '/')
  end

  def row1
    @row1 ||= record(name: 'Alice', email: 'alice@test.com')
  end

  def row2
    @row2 ||= record(name: 'Bob', email: 'bob@test.com')
  end

  def scope
    @scope ||= dataset([row1, row2])
  end

  # Lux::Test::Case clears Thread.current[:lux] after every test, so the stub cannot leak.
  before do
    Thread.current[:lux] = Struct.new(:request).new(request)
  end

  describe '#col' do
    it 'adds column by field name' do
      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      assert_includes html, 'Name'
      assert_includes html, 'Alice'
      assert_includes html, 'Bob'
    end

    it 'adds column with block' do
      t = HtmlTable.new(scope)
      t.col(title: 'Full') { |o| ">> #{o.name}" }
      html = t.render

      assert_includes html, 'Full'
      assert_includes html, '&gt;&gt; Alice'
    end

    it 'adds column with custom title' do
      t = HtmlTable.new(scope)
      t.col :name, title: 'User name'
      html = t.render

      assert_includes html, 'User name'
    end

    it 'adds column with width' do
      t = HtmlTable.new(scope)
      t.col :name, width: 200
      html = t.render

      assert_includes html, 'width: 200px'
      assert_includes html, '<colgroup>'
      assert_includes html, 'data-cols='
    end

    it 'adds column with min_width' do
      t = HtmlTable.new(scope)
      t.col :name, min_width: 180
      html = t.render

      assert_includes html, 'min-width: 180px'
      refute_includes html, 'width="180"'
    end

    it 'adds column with align shorthand' do
      t = HtmlTable.new(scope)
      t.col :name, align: :c
      html = t.render

      assert_includes html, 'text-align: center'
    end
  end

  describe '#render' do
    it 'wraps in app-table div' do
      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      assert_includes html, 'class="app-table"'
    end

    it 'renders thead and tbody' do
      t = HtmlTable.new(scope)
      t.col :name
      html = t.render

      assert_includes html, '<thead>'
      assert_includes html, '<tbody>'
    end

    it 'returns nil for empty scope' do
      t = HtmlTable.new(dataset([]))
      t.col :name

      _(t.render).must_be_nil
    end

    it 'applies table class from opts' do
      t = HtmlTable.new(scope, class: 'striped')
      t.col :name
      html = t.render

      assert_includes html, 'class="striped"'
    end
  end

  describe '#onclick' do
    it 'adds onclick to rows' do
      t = HtmlTable.new(scope)
      t.col :name
      t.onclick { |o| "alert('#{o.name}')" }
      html = t.render

      assert_includes html, "alert('Alice')"
      assert_includes html, "alert('Bob')"
    end
  end

  describe '#search' do
    it 'stores search definition' do
      t = HtmlTable.new(scope)
      t.search(:q) { |s, v| s }

      _(t.instance_variable_get(:@searches).length).must_equal 1
      _(t.instance_variable_get(:@searches).first[0]).must_equal :q
    end

    it 'defaults type to text' do
      t = HtmlTable.new(scope)
      t.search(:q) { |s, v| s }

      _(t.instance_variable_get(:@searches).first[1]).must_equal :text
    end

    it 'applies search filter from params' do
      filtered = dataset([row1])
      request.params = { 'q' => 'Alice' }

      t = HtmlTable.new(scope)
      t.col :name
      t.search(:q) { |s, v| filtered }
      html = t.render

      assert_includes html, 'Alice'
      refute_includes html, 'Bob'
    end

    it 'skips search when param is empty' do
      request.params = { 'q' => '' }

      t = HtmlTable.new(scope)
      t.col :name
      t.search(:q) { |s, v| raise 'should not be called' }
      html = t.render

      assert_includes html, 'Alice'
    end
  end

  describe '#default_order' do
    it 'applies default order when no sort param' do
      ordered = dataset([row2, row1])

      t = HtmlTable.new(scope)
      t.col :name
      t.default_order { |s| ordered }
      html = t.render

      assert_includes html, 'Bob'
    end
  end

  describe '#scope_filter' do
    it 'applies scope filter' do
      filtered = dataset([row1])

      t = HtmlTable.new(scope)
      t.col :name
      t.scope_filter { |s| filtered }
      html = t.render

      assert_includes html, 'Alice'
    end
  end

  describe '#before' do
    it 'can be overridden to filter scope' do
      t = HtmlTable.new(scope)
      t.col :name

      def t.before scope
        scope
      end

      assert_includes t.render, 'Alice'
    end
  end

  describe 'sorting' do
    it 'renders sort link when sort: true' do
      request.path = '/admin/users'

      t = HtmlTable.new(scope)
      t.col :name, sort: true
      html = t.render

      assert_includes html, 'table-sort'
      assert_includes html, 't-sort=a-name'
    end

    it 'toggles sort direction in link' do
      request.params = { 't-sort' => 'a-name' }
      request.path = '/admin/users'
      sortable = dataset([row1, row2], orders: { Sequel.asc(:name) => scope })

      t = HtmlTable.new(sortable)
      t.col :name, sort: true
      html = t.render

      assert_includes html, 't-sort=d-name'
    end

    it 'applies initial ascending sort with sort: :a' do
      sortable = dataset([row1, row2], orders: { Sequel.asc(:name) => dataset([row1, row2]) })

      t = HtmlTable.new(sortable)
      t.col :name, sort: :a
      html = t.render

      assert_includes html, 'Alice'
    end

    it 'applies initial descending sort with sort: :d' do
      sortable = dataset([row1, row2], orders: { Sequel.desc(:name) => dataset([row2, row1]) })

      t = HtmlTable.new(sortable)
      t.col :name, sort: :d
      html = t.render

      assert_includes html, 'Bob'
    end

    it 'params override initial sort' do
      request.params = { 't-sort' => 'd-name' }
      sortable = dataset([row1, row2], orders: { Sequel.desc(:name) => dataset([row2, row1]) })

      t = HtmlTable.new(sortable)
      t.col :name, sort: :a
      html = t.render

      assert_includes html, 'Bob'
    end

    it 'applies ascending sort from params' do
      request.params = { 't-sort' => 'a-name' }
      sortable = dataset([row1, row2], orders: { Sequel.asc(:name) => dataset([row1, row2]) })

      t = HtmlTable.new(sortable)
      t.col :name
      html = t.render

      assert_includes html, 'Alice'
    end

    it 'applies descending sort from params' do
      request.params = { 't-sort' => 'd-name' }
      sortable = dataset([row1, row2], orders: { Sequel.desc(:name) => dataset([row2, row1]) })

      t = HtmlTable.new(sortable)
      t.col :name
      html = t.render

      assert_includes html, 'Bob'
    end
  end

  describe 'prepare_as_blocks' do
    it 'raises for unknown as type' do
      t = HtmlTable.new(scope)
      t.col :name, as: :unknown_type

      err = assert_raises(ArgumentError) { t.render }
      assert_match(/not defined/, err.message)
    end
  end

  describe 'render_cell' do
    it 'raises when column has no field, as, or block' do
      t = HtmlTable.new(scope)
      t.col(title: 'Empty')

      err = assert_raises(ArgumentError) { t.render }
      assert_match(/requires :field, :as, or a block/, err.message)
    end
  end

  describe 'as types' do
    def now
      @now ||= Time.new(2025, 3, 15, 10, 30, 0)
    end

    def row1
      @row1 ||= record(active: true, created_at: now, price: 1234.5, score: 0.856, email: 'alice@test.com', tags: ['a', 'b'], bio: 'x' * 100, avatar: '/img/alice.png')
    end

    def row2
      @row2 ||= record(active: false, created_at: nil, price: nil, score: nil, email: nil, tags: [], bio: 'short', avatar: nil)
    end

    it 'as_boolean renders checkmark for true' do
      t = HtmlTable.new(scope)
      t.col :active, as: :boolean
      html = t.render

      assert_includes html, '&#10003;'
    end

    it 'as_date formats date' do
      t = HtmlTable.new(scope)
      t.col :created_at, as: :date
      html = t.render

      assert_includes html, '2025-03-15'
    end

    it 'as_datetime formats datetime' do
      t = HtmlTable.new(scope)
      t.col :created_at, as: :datetime
      html = t.render

      assert_includes html, '2025-03-15 10:30'
    end

    it 'as_number formats with commas' do
      t = HtmlTable.new(dataset([record(count: 1234567), record(count: 42)]))
      t.col :count, as: :number
      html = t.render

      assert_includes html, '1,234,567'
      assert_includes html, '42'
    end

    it 'as_currency formats to 2 decimals' do
      t = HtmlTable.new(scope)
      t.col :price, as: :currency
      html = t.render

      assert_includes html, '1234.50'
    end

    it 'as_truncate truncates long text' do
      t = HtmlTable.new(scope)
      t.col :bio, as: :truncate
      html = t.render

      assert_includes html, '...'
      assert_includes html, 'short'
    end

    it 'as_truncate respects custom limit' do
      t = HtmlTable.new(scope)
      t.col :bio, as: :truncate, limit: 10
      html = t.render

      assert_includes html, 'xxxxxxxxxx...'
    end

    it 'as_percent formats as percentage' do
      t = HtmlTable.new(scope)
      t.col :score, as: :percent
      html = t.render

      assert_includes html, '85.6%'
    end

    it 'as_email renders mailto link' do
      t = HtmlTable.new(scope)
      t.col :email, as: :email
      html = t.render

      assert_includes html, 'mailto:alice@test.com'
      assert_includes html, 'alice@test.com'
    end

    it 'as_list joins array values' do
      t = HtmlTable.new(scope)
      t.col :tags, as: :list
      html = t.render

      assert_includes html, 'a, b'
    end

    it 'as_image renders img tag' do
      t = HtmlTable.new(scope)
      t.col :avatar, as: :image
      html = t.render

      assert_includes html, '/img/alice.png'
      assert_includes html, 'width: 40px'
    end
  end
end
