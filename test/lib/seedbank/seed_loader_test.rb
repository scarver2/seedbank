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

  it 'validates every declared database bank before running any seeds' do
    database_banks = Object.new
    database_banks.define_singleton_method(:validate!) do
      raise Seedbank::ConfigurationError, 'missing warehouse'
    end
    events = []
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common') { events << :common }

    error = assert_raises(Seedbank::ConfigurationError) do
      Seedbank::SeedLoader.new(database_banks: database_banks).load_seed
    end

    _(error.message).must_equal 'missing warehouse'
    _(events).must_be_empty
  end

  it 'loads declared database banks after common and environment seeds' do
    events = []
    database_banks = Object.new
    database_banks.define_singleton_method(:validate!) { events << :validated }
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common') { events << :common }
    Rake::Task.define_task('db:seed:test') { events << :environment }
    Rake::Task.define_task('db:seed:databases') { events << :databases }

    Seedbank::SeedLoader.new(
      environment: -> { 'test' },
      database_banks: database_banks
    ).load_seed

    _(events).must_equal %i[validated common environment databases]
  end

  it 'runs the global seed graph on the Rails primary database' do
    configurations = {
      'test' => {
        'primary' => { 'adapter' => 'sqlite3', 'database' => ':memory:' },
        'animals' => { 'adapter' => 'sqlite3', 'database' => ':memory:' }
      }
    }
    connection_class = connection_class_for(configurations, current: 'animals')
    connections = []
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common') do
      connections << connection_class.connection_db_config.name
    end

    Seedbank::SeedLoader.new(environment: -> { 'test' }, connection_class: connection_class).load_seed

    _(connections).must_equal %w[primary]
    _(connection_class.connection_db_config.name).must_equal 'primary'
  end

  it 'does not reconnect single-database applications' do
    connection_class = connection_class_for(
      { 'test' => { 'adapter' => 'sqlite3', 'database' => ':memory:' } },
      current: 'primary'
    )
    Rake.application = Rake::Application.new
    Rake::Task.define_task('db:seed:common')

    Seedbank::SeedLoader.new(environment: -> { 'test' }, connection_class: connection_class).load_seed

    _(connection_class.established_connections).must_be_empty
  end

  it 'rejects ambiguous multiple-database configurations without a primary' do
    configurations = {
      'test' => {
        'animals' => { 'adapter' => 'sqlite3', 'database' => ':memory:' },
        'queue' => { 'adapter' => 'sqlite3', 'database' => ':memory:' }
      }
    }
    connection_class = connection_class_for(configurations, current: 'animals')
    error = assert_raises(Seedbank::ConfigurationError) do
      Seedbank::SeedLoader.new(environment: -> { 'test' }, connection_class: connection_class).load_seed
    end

    _(error.message).must_include('no primary database exists')
  end

  def connection_class_for(configurations, current:)
    database_configurations = ActiveRecord::DatabaseConfigurations.new(configurations)
    current_configuration = database_configurations.configs_for(env_name: 'test', name: current)

    Class.new do
      attr_reader :configurations, :established_connections

      def initialize(configurations, current_configuration)
        @configurations = configurations
        @current_configuration = current_configuration
        @established_connections = []
      end

      def connection_db_config
        @current_configuration
      end

      def establish_connection(configuration)
        @current_configuration = configuration
        @established_connections << configuration
      end
    end.new(database_configurations, current_configuration)
  end
end
