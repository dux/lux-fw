Lux.app do
  before do
    Thread.current[:db_q] = { time: 0.0, cnt: 0 }
  end

  after do
    Lux.log " #{Thread.current[:db_q][:cnt]} DB queries, #{(Thread.current[:db_q][:time]*1000).round(1)} ms" if Thread.current[:db_q][:cnt] > 0
  end
end
