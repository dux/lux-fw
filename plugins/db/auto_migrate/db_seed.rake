class ApplicationModel
  def seed_name
    value = nil
    value ||= self.slug  if respond_to?(:slug)
    value ||= self.email if respond_to?(:email)
    value ||= self.name  if respond_to?(:name)

    if value
      [self.class.to_s.underscore, value.split(' ').first.underscore.gsub(/[^\w]+/, '_')].join('_')
    else
      nil
    end
  end

  # overload for custom export
  # def seed_hash
  #   super.tap do |out|
  #     out['expert_in_city_ids'] = out['expert_in_city_ids'].map { |el| '@%s.id' % City.find(el).seed_name }
  #   end

  def seed_hash
    attributes
      .reject { |k, _| %w[id created_at updated_at created_by updated_by].include?(k) }
      .reject { |k, v| v.nil? || (v.blank? && v.class != FalseClass)}
  end

  def seed_generate
    out = []

    name = self.seed_name
    name = "@#{name} = " if name
    out.push "#{name}#{self.class.to_s}.create({"

    for k, v in seed_hash
      if k.ends_with?('_id')
        m = k.sub(/_id$/, '')
        o = respond_to?(m) ? self.send(m) : nil

        if o && o.seed_name
          v = "@#{o.seed_name}.id"
        end
      end

      value = JSON.generate(v)
      value = value.gsub(/"\@([\w\.]+)"/) { %[@#{$1}] }

      out.push "  %s: %s," % [k, value]
    end

    out.push "})"
    out.join($/)
  end
end

# seed creator helper
# lux e seed 'User.select(:name, :email, :cached_avatar).all'

namespace :db do
  namespace :seed do
    desc "Create seeds from models"
    task gen: :app do
      ARGV.shift

      klass = ARGV.first

      if klass == 'all'
        # "# rake db:seed:gen #{klass} > db/seeds/#{klass.to_s.tableize}.rb\n\n" + list.join($/)
      elsif klass
        klass = klass.constantize
        klass.order(:id).each do |o|
          puts o.seed_generate
          exit
        end
      else
        puts 'Usage:'
        Lux.info 'rake db:seed:gen User'
        Lux.info 'rake db:seed:gen all'
        exit
      end

      # unless ARGV.first
      #   list = Sequel::Model
      #     .descendants
      #     .sort_by(&:to_s)

      #   for klass in list
      #     count    = (klass.count rescue '-').to_s.ljust(10)
      #     location = "db/seeds/#{klass.to_s.tableize}.rb"
      #     location = location.sub('.rb', '_.rb') if File.exist?(location)
      #     command  = "rake db:seed #{klass} > #{location}"
      #     line     = '%s: %s # %s' % [klass.to_s.ljust(20), count, command]
      #     line     = line.green if line.include?('_.rb')

      #     if @all
      #       if count.to_i > 0
      #         puts line
      #         File.write(location, seed(klass))
      #       end
      #     else
      #       puts line
      #     end
      #   end

      #   exit
      # end

      # puts seed ARGV.shift.constantize

      exit
    end

    desc "Load seeds from db/seeds"
    task load: :app do
      for file in Dir['db/seeds/*'].sort
        puts file.green
        load file
      end
    end
  end
end
