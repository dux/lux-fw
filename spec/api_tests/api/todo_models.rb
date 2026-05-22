class Board < Struct.new(:id, :name)
  STORE = []

  def tasks
    Task::STORE.select { |t| t.board_id == id }
  end

  def to_h
    { id: id, name: name, task_count: tasks.size }
  end

  def self.find(id)
    STORE.find { |b| b.id == id.to_i }
  end
end

class Task < Struct.new(:id, :board_id, :title, :active)
  STORE = []

  def to_h
    { id: id, board_id: board_id, title: title, active: active }
  end
end

# 2 boards
Board::STORE.push(
  Board.new(1, 'Work'),
  Board.new(2, 'Personal')
)

# 7 tasks per board (4 active, 3 inactive each)
Task::STORE.push(
  Task.new(1,  1, 'Review PRs',        true),
  Task.new(2,  1, 'Deploy staging',     true),
  Task.new(3,  1, 'Write specs',        true),
  Task.new(4,  1, 'Update docs',        false),
  Task.new(5,  1, 'Fix login bug',      true),
  Task.new(6,  1, 'Refactor API',       false),
  Task.new(7,  1, 'Team standup',       false),
  Task.new(8,  2, 'Buy groceries',      true),
  Task.new(9,  2, 'Call dentist',       false),
  Task.new(10, 2, 'Read book',          true),
  Task.new(11, 2, 'Clean kitchen',      true),
  Task.new(12, 2, 'Pay bills',          false),
  Task.new(13, 2, 'Plan weekend trip',  true),
  Task.new(14, 2, 'Fix bike',           false)
)
