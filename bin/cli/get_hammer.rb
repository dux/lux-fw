define :get do
  desc 'Get single page by path: lux get /login -b'
  needs :app
  opt :body, alias: :b, type: :boolean, default: false, desc: 'Show body'
  opt :info, alias: :i, type: :boolean, default: false, desc: 'Show info'
  opt :type, type: :boolean, default: false, desc: 'Request type'

  proc do |opts|
    path = opts[:args].first
    error "Use\n -b to show body\n -i to show info" unless opts[:body] || opts[:info]

    data = Lux.app.new(path).render_page

    if opts[:body]
      puts data[:body]
    elsif opts[:info]
      data[:body] = 'BODY length: %s kB' % (data[:body].length.to_f / 1024).round(1)
      ap data.to_h
    end
  end
end
