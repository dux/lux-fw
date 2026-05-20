class ModelApi < ApplicationApi
  def call_me_in_child
    @number = 2345
  end

  ref do
    before do
      id = @ref.to_s == @ref.to_i.to_s ? @ref.to_i : nil

      if id == 1
        @model = Company.new
      else
        error 'Model not found'
      end
    end

    desc 'Show object creator'
    desc 'Even more description'
    params do
      show_all false
    end
    def creator
      '@dux'
    end

    desc 'Update the model'
    def update
      'updated'
    end

    def call_me_in_child
      @number = 1234
    end
  end
end
