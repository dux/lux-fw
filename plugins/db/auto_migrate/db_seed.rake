# seed creator helper
# lux e seed 'User.select(:name, :email, :cached_avatar).all'
def seed list, klass=nil
  klass ||= list
  list = list.all if respond_to?(:all) && !list.is_a?(Array)
  list = list.map do |el|
    o = el
      .to_h
      .compact
      .select do |k, v|
        if v.respond_to?(:keys)
          v.keys.length > 0
        elsif v.is_array?
          v = v.compact
          v.length > 0 && v.first.present?
        elsif v.respond_to?(:length)
          v.length > 0
        else
          true
        end
      end
      .except(:id, :created_at, :updated_at, :created_by, :updated_by)

    o = JSON.pretty_generate o
    o = o.gsub(/"(\w+)":/) { "#{$1}:" }

    "#{el.class}.create(#{o})\n"
  end

  "# db:seed #{klass} > db/seeds/#{klass.to_s.tableize}.rb\n\n" + list.join($/)
end

namespace :db do
  desc "create seeds for models"
  task seed: :app do
    ARGV.shift

    @all = ARGV.shift if ARGV.first == 'all'

    unless ARGV.first
      list = Sequel::Model
        .descendants
        .sort_by(&:to_s)

      for klass in list
        count    = (klass.count rescue '-').to_s.ljust(10)
        location = "db/seeds/#{klass.to_s.tableize}.rb"
        location = location.sub('.rb', '_.rb') if File.exist?(location)
        command  = "rake db:seed #{klass} > #{location}"
        line     = '%s: %s # %s' % [klass.to_s.ljust(20), count, command]
        line     = line.green if line.include?('_.rb')

        if @all
          if count.to_i > 0
            puts line
            File.write(location, seed(klass))
          end
        else
          puts line
        end
      end

      exit
    end

    puts seed ARGV.shift.constantize

    exit
  end

  namespace :seed do
    desc 'Generate seeeds from DB data'
    task generate: :app do
      ap 123
    end
  end
end
