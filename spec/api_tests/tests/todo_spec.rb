require 'test_helper'
require_relative '../loader'

describe 'todo app' do
  describe 'boards' do
    it 'lists all boards' do
      response = BoardApi.render.list
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 2
      _(response[:data][0][:name]).must_equal 'Work'
      _(response[:data][1][:name]).must_equal 'Personal'
    end

    it 'each board reports task_count of 7' do
      response = BoardApi.render.list
      response[:data].each do |board|
        _(board[:task_count]).must_equal 7
      end
    end

    it 'shows a single board by id' do
      response = BoardApi.render.show(1)
      _(response[:success]).must_equal true
      _(response[:data][:name]).must_equal 'Work'
      _(response[:data][:task_count]).must_equal 7
    end

    it 'returns error for unknown board' do
      response = BoardApi.render.show(999)
      _(response[:success]).must_equal false
    end
  end

  describe 'tasks' do
    it 'lists all tasks for board 1' do
      response = BoardApi.render.tasks(1)
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 7
    end

    it 'lists all tasks for board 2' do
      response = BoardApi.render.tasks(2)
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 7
    end

    it 'filters active tasks only' do
      response = BoardApi.render.tasks(1, { active: 'true' })
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 4
      response[:data].each do |task|
        _(task[:active]).must_equal true
      end
    end

    it 'filters inactive tasks only' do
      response = BoardApi.render.tasks(1, { active: 'false' })
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 3
      response[:data].each do |task|
        _(task[:active]).must_equal false
      end
    end

    it 'filters active tasks for board 2' do
      response = BoardApi.render.tasks(2, { active: 'true' })
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 4
    end

    it 'filters inactive tasks for board 2' do
      response = BoardApi.render.tasks(2, { active: 'false' })
      _(response[:success]).must_equal true
      _(response[:data].size).must_equal 3
    end

    it 'each task has expected fields' do
      response = BoardApi.render.tasks(1)
      response[:data].each do |task|
        _(task.keys).must_include :id
        _(task.keys).must_include :board_id
        _(task.keys).must_include :title
        _(task.keys).must_include :active
      end
    end
  end
end
