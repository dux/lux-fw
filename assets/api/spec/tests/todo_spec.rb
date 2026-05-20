require_relative '../loader'

describe 'todo app' do
  describe 'boards' do
    it 'lists all boards' do
      response = BoardApi.render.list
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(2)
      expect(response[:data][0][:name]).to eq('Work')
      expect(response[:data][1][:name]).to eq('Personal')
    end

    it 'each board reports task_count of 7' do
      response = BoardApi.render.list
      response[:data].each do |board|
        expect(board[:task_count]).to eq(7)
      end
    end

    it 'shows a single board by id' do
      response = BoardApi.render.show(1)
      expect(response[:success]).to eq(true)
      expect(response[:data][:name]).to eq('Work')
      expect(response[:data][:task_count]).to eq(7)
    end

    it 'returns error for unknown board' do
      response = BoardApi.render.show(999)
      expect(response[:success]).to eq(false)
    end
  end

  describe 'tasks' do
    it 'lists all tasks for board 1' do
      response = BoardApi.render.tasks(1)
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(7)
    end

    it 'lists all tasks for board 2' do
      response = BoardApi.render.tasks(2)
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(7)
    end

    it 'filters active tasks only' do
      response = BoardApi.render.tasks(1, { active: 'true' })
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(4)
      response[:data].each do |task|
        expect(task[:active]).to eq(true)
      end
    end

    it 'filters inactive tasks only' do
      response = BoardApi.render.tasks(1, { active: 'false' })
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(3)
      response[:data].each do |task|
        expect(task[:active]).to eq(false)
      end
    end

    it 'filters active tasks for board 2' do
      response = BoardApi.render.tasks(2, { active: 'true' })
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(4)
    end

    it 'filters inactive tasks for board 2' do
      response = BoardApi.render.tasks(2, { active: 'false' })
      expect(response[:success]).to eq(true)
      expect(response[:data].size).to eq(3)
    end

    it 'each task has expected fields' do
      response = BoardApi.render.tasks(1)
      response[:data].each do |task|
        expect(task).to have_key(:id)
        expect(task).to have_key(:board_id)
        expect(task).to have_key(:title)
        expect(task).to have_key(:active)
      end
    end
  end
end
