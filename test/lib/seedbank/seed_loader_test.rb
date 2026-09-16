# test/lib/seedbank/seed_loader_test.rb
# frozen_string_literal: true

require 'test_helper'

describe Seedbank::SeedLoader do
  it 'loads common seeds before the current environment seeds' do
    events = []
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common') { events << :common }
    Rake::Task.define_task('db:seed:development') { events << :development }

    Seedbank::SeedLoader.new(environment: -> { 'development' }).load_seed

    _(events).must_equal %i[common development]
  end

  it 'loads only common seeds when the environment has no seed task' do
    events = []
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common') { events << :common }

    Seedbank::SeedLoader.new(environment: -> { 'production' }).load_seed

    _(events).must_equal %i[common]
  end

  it 'uses the current Rails environment by default' do
    events = []
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common') { events << :common }
    Rake::Task.define_task('db:seed:development') { events << :development }

    Rails.stub(:env, 'development') { Seedbank::SeedLoader.new.load_seed }

    _(events).must_equal %i[common development]
  end

  it 'runs the global seed graph on the Rails primary database' do
    with_database_configurations(
      'test' => {
        'primary' => { 'adapter' => 'sqlite3', 'database' => ':memory:' },
        'animals' => { 'adapter' => 'sqlite3', 'database' => ':memory:' }
      }
    ) do
      ActiveRecord::Base.establish_connection(:animals)
      connections = []
      Rake.application = Rake::Application.new
      Rake::Task.define_task('db:seed:common') do
        connections << ActiveRecord::Base.connection_db_config.name
      end

      Seedbank::SeedLoader.new(environment: -> { 'test' }).load_seed

      _(connections).must_equal %w[primary]
      _(ActiveRecord::Base.connection_db_config.name).must_equal 'primary'
    end
  end

  it 'does not reconnect single-database applications' do
    with_database_configurations(
      'test' => { 'adapter' => 'sqlite3', 'database' => ':memory:' }
    ) do
      ActiveRecord::Base.establish_connection(:test)
      original_pool = ActiveRecord::Base.connection_pool
      Rake.application = Rake::Application.new
      Rake::Task.define_task('db:seed:common')

      Seedbank::SeedLoader.new(environment: -> { 'test' }).load_seed

      _(ActiveRecord::Base.connection_pool).must_be_same_as original_pool
    end
  end

  it 'rejects ambiguous multiple-database configurations without a primary' do
    with_database_configurations(
      'test' => {
        'animals' => { 'adapter' => 'sqlite3', 'database' => ':memory:' },
        'queue' => { 'adapter' => 'sqlite3', 'database' => ':memory:' }
      }
    ) do
      error = assert_raises(Seedbank::ConfigurationError) do
        Seedbank::SeedLoader.new(environment: -> { 'test' }).load_seed
      end

      _(error.message).must_include('no primary database exists')
    end
  end

  def with_database_configurations(configurations)
    original_configurations = ActiveRecord::Base.configurations
    original_connection = ActiveRecord::Base.connection_db_config
    ActiveRecord::Base.configurations = configurations

    yield
  ensure
    ActiveRecord::Base.configurations = original_configurations
    ActiveRecord::Base.establish_connection(original_connection)
  end
end
