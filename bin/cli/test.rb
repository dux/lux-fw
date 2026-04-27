ARGV[0] = 'test' if ARGV[0] == 't'

LuxCli.class_eval do
  desc :test, 'Run tests (auto-detects rspec or minitest)'
  def test *args
    fw = detect_test_framework
    unless fw
      puts "No test framework found. Add 'rspec' or 'minitest' to your Gemfile.".colorize(:red)
      exit 1
    end

    if args.empty?
      Cli.info 'Recreating test database...'
      Cli.run 'bundle exec rake db:create:test'
      puts
    end

    case fw
    when :rspec
      cmd = args.empty? ? 'rspec' : "rspec #{args.join(' ')}"
    when :minitest
      cmd = args.empty? ? 'ruby -Itest -e "Dir.glob(\'test/**/*_test.rb\').each { |f| require(File.expand_path(f)) }"' : "ruby -Itest #{args.join(' ')}"
    end

    Cli.info "Running #{fw}..."
    Cli.run "RACK_ENV=test bundle exec #{cmd}"
  end

  no_commands do
    def detect_test_framework
      return :rspec if File.exist?('.rspec') || File.exist?('spec')
      return :minitest if File.exist?('test')

      gemfile = File.exist?('Gemfile') ? File.read('Gemfile') : ''
      return :rspec if gemfile.match?(/gem\s+['"]rspec['"]/)
      return :minitest if gemfile.match?(/gem\s+['"]minitest['"]/)

      nil
    end
  end
end
