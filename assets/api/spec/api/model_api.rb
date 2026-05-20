class ModelApi < ApplicationApi
  define :call_me_in_child do
    proc { @number = 2345 }
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
    define :creator do
      proc { '@dux' }
    end

    desc 'Update the model'
    define :update do
      proc { 'updated' }
    end

    define :call_me_in_child do
      proc { @number = 1234 }
    end
  end
end
