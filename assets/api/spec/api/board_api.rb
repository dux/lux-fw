class BoardApi < ApplicationApi
  documented

  class_desc 'Todo boards'

  define :list do
    desc 'List all boards'
    proc do
      Board::STORE.map(&:to_h)
    end
  end

  ref do
    before do
      @board = Board.find(@ref)
      error 'Board not found' unless @board
    end

    define :show do
      desc 'Show a single board'
      proc do
        @board.to_h
      end
    end

    define :tasks do
      desc 'List tasks in a board'
      detail 'Pass active=true or active=false to filter by status'
      params do
        active? String
      end
      proc do
        tasks = @board.tasks
        unless params[:active].to_s.empty?
          is_active = params[:active].to_s == 'true'
          tasks = tasks.select { |t| t.active == is_active }
        end
        tasks.map(&:to_h)
      end
    end
  end
end
