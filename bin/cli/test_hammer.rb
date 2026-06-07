module LuxTest
  TEST_ENV_PREFIX ||= 'LUX_ENV=test RACK_ENV=test'

  module_function

  def detect_framework
    return :rspec if File.exist?('.rspec') || File.exist?('spec')
    return :minitest if File.exist?('test')

    gemfile = File.exist?('Gemfile') ? File.read('Gemfile') : ''
    return :rspec if gemfile.match?(/gem\s+['"]rspec['"]/)
    return :minitest if gemfile.match?(/gem\s+['"]minitest['"]/)

    nil
  end
end

task :test do
  desc 'Run tests (auto-detects rspec or minitest)'
  alt :t

  proc do |opts|
    args = opts[:args]
    fw = LuxTest.detect_framework
    error "No test framework found. Add 'rspec' or 'minitest' to your Gemfile." unless fw

    if args.empty?
      say.magenta 'Rebuilding test database from schema...'
      sh "#{LuxTest::TEST_ENV_PREFIX} bundle exec lux db:test:am"
      say ''
    end

    cmd =
      case fw
      when :rspec
        args.empty? ? 'rspec' : "rspec #{args.join(' ')}"
      when :minitest
        args.empty? ? 'ruby -Itest -e "Dir.glob(\'test/**/*_test.rb\').each { |f| require(File.expand_path(f)) }"' : "ruby -Itest #{args.join(' ')}"
      end

    say.magenta "Running #{fw}..."
    sh "#{LuxTest::TEST_ENV_PREFIX} bundle exec #{cmd}"
  end
end
