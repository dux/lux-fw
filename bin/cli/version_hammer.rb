task :version do
  desc 'Print the Lux build version'

  proc do
    say Lux::Version.string
  end
end
