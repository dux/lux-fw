class Main::RootController < ApplicationController
  mock :about

  def index
    @title = 'Yay, you are on Lux'
  end

  def text
    render text: 'Hello world'
  end

  # auto-renders app/views/main/root/markdown.md via the Tilt CommonMarker
  # adapter registered in config/initializers/markdown.rb
  def markdown
    @title = 'Markdown view demo'
  end
end
