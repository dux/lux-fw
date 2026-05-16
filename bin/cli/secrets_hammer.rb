define :secrets do
  desc 'Edit, show and compile secrets'
  needs :env

  proc do |_opts|
    say.magenta 'dump for ENV %s' % Lux.env
    say.magenta 'dump for secrets'
    puts Lux.secrets.to_h.to_jsonp(true)
  end
end
