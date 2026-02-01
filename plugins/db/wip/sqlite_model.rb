# TRY to create unified interface to SQLITE, but switch file name based on some param
#   why: for example keep all site data in a single sqlite file, every new site is a new file
#   state: feels hacky and I do not like it
# # how?
# # * creates parent class that gets dataset from Thread.current
# # * recreate all important Sequel class methods

# EXAMPLE ON THE END
# REMEMBER that you have to migrate schema on db init for sqlite

class SqliteModel
  DB_CONN    ||= {}
  DB_SCHEMAS ||= {}

  cattr :db_block

  class << self
    def logger target = nil
      Logger.new(target || STDOUT).tap do |l|
        l.formatter = proc {|_, _, _, msg| 'SQLite ' + msg + $/ }
      end
    end

    def db &block
      if block_given?
        DB_CONN[to_s] = block
      else
        klass = self.ancestors[1] == SqliteModel ? self : self.ancestors[1]
        DB_CONN[klass.to_s].call
      end
    end

    def set_fields *list
      for el in ([:id] + list.flatten)
        # create static methods from values in schema
        unless method_defined?(el)
          eval %[
            #{to_s}.class_eval do
              def #{el}; @values[:#{el}]; end
              def #{el}= val; @values[:#{el}] = val; end
            end
          ]
        end
      end
    end

    def schema &block
      name ||= self.to_s.split('::').last.tableize

      parent = ancestors[1]
      parent::DB_SCHEMAS[parent.to_s] ||= {}
      parent::DB_SCHEMAS[parent.to_s][name] = block
    end

    def auto_migrate db_conn
      for table, block in  DB_SCHEMAS[to_s]
        fields = SequelTable db_conn, table, &block
        set_fields fields
      end
    end

    def table_name klass = nil
      (klass || to_s).to_s.split('::').last.tableize.to_sym
    end

    def dataset name = nil
      self.db[name || table_name]
    end

    def create data = {}
      new(data).save
    end

    def find id
      new dataset.where(id: id).first
    end

    def first n = nil
      list = dataset.order(:id).first(n || 1).all.map{ new _1 }
      n ? list : list.first
    end

    def last n = nil
      list = dataset.order(:id).last(n || 1).all.map{ new _1 }
      n ? list : list.first
    end

    def where *args
      dataset.where *args
    end

    def order str
      dataset.order(str.class == String ? Sequel.lit(str) : str)
    end

    def fetch opts = {}
      out = yield(self)
      Paginate out, **opts.merge(klass: self)
    end

    def fetch! opts = {}, &block
      out = instance_exec(&block)
      if out.class == Array
        out.map { new(_1) }
      else
        opts[:size] ||= out.opts[:limit]
        Paginate out, **opts.merge(klass: self)
      end
    end
    alias :map :fetch!
  end

  ###

  def initialize data = {}
    @values = (data || {})
  end

  def validate; end
  def before_destroy; end
  def after_destroy; end

  def dataset
    self.class.dataset.where(id: @values[:id])
  end

  def save
    validate

    copy = @values.map do |k, v|
      v = v.to_json if v.class == Hash
      [k, v]
    end.to_h

    if @values[:id]
      copy[:updated_at] = Time.now if respond_to?(:updated_at)
      copy[:updated_by] = User.current.id if respond_to?(:updated_by)
      dataset.update copy.except(:id)
    else
      copy[:created_at] = Time.now if respond_to?(:created_at)
      copy[:created_by] = User.current.id if respond_to?(:created_by)
      @values[:id] = dataset.insert copy
    end

    self
  end

  def update data
    dataset.update data
    @values = @values.merge data
    self
  end

  def destroy
    dataset.destroy
  end

  def to_h
    @values.to_h
  end
  alias :attributes :to_h
end

# class SimpleFeedback < SqliteModel
#   db do
#     @db ||= begin
#       path = './sqlite/simple_feedback.sqlite'
#       Sequel.sqlite(path).tap do |c|
#         auto_migrate c
#         c.loggers.push SqliteModel.logger if Lux.env.local?
#       end
#     end
#   end

#   class Feedback < SimpleFeedback
#     schema do
#       col :name, String   # base to show something
#       col :data, String   # all other json data
#       col :url, String    # Current page URL
#       col :group, String  # group (site or 'admin')
#       col :kind, String   # suggestion, bug, ...
#       col :email, String  # user email
#       col :created_at, Time
#     end
#   end
# end

# f = SimpleFeedback::Feedback.new
# f.name = 'Dux %s' % Time.now
# f.email = '%s@foo.bar' % rand
# f.save

# rr SimpleFeedback::Feedback.dataset.all
