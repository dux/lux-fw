class Main::RootController < ApplicationContrller
  mock :about

  def index
    @title = 'Yay, you are on Lux'
  end

  def text
    render text: 'Hello world'
  end
end
