module LuxTest
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

define :test do
  desc 'Run tests (auto-detects rspec or minitest)'
  alt :t

  proc do |opts|
    args = opts[:args]
    fw = LuxTest.detect_framework
    error "No test framework found. Add 'rspec' or 'minitest' to your Gemfile." unless fw

    if args.empty?
      say.magenta 'Recreating test database...'
      sh 'bundle exec lux db:test:create'
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
    sh "RACK_ENV=test bundle exec #{cmd}"
  end
end
