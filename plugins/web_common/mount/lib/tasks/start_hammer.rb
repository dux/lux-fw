task :start do
  desc 'Prepare env and autorun app'
  needs :app
  proc do
    File.write "./app/assets/auto/shared/css/cells-generated.scss", Lux::ViewCell.css

    hammer 'mount'
    hammer 'assets:auto'

    system 'hivemind'
  end
end
