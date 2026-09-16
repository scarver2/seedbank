# test/lib/seedbank/database_banks_test.rb
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require 'test_helper'

describe Seedbank::DatabaseBanks do
  it 'routes cross-bank dependencies across distinct SQLite databases and restores the caller connection' do
    with_databases do |directory, configurations|
      create_entries_table(configurations, 'primary')
      create_entries_table(configurations, 'warehouse')
      create_entries_table(configurations, 'archive')

      seeds_root = Pathname.new(directory).join('db/seeds')
      warehouse_file = write_seed(
        seeds_root,
        'warehouse',
        'dimensions',
        "after 'databases:archive:retention' do\n  SeedbankBankEntry.create!(name: 'warehouse')\nend\n"
      )
      archive_file = write_seed(
        seeds_root,
        'archive',
        'retention',
        "SeedbankBankEntry.create!(name: 'archive')\n"
      )
      banks = Seedbank::DatabaseBanks.new(
        seeds_root: seeds_root,
        environment: -> { 'test' },
        connection_class: ActiveRecord::Base
      )
      runner = Seedbank::Runner.new(database_banks: banks)
      define_seed_task(runner, 'db:seed:databases:archive:retention', archive_file)
      define_seed_task(runner, 'db:seed:databases:warehouse:dimensions', warehouse_file)

      Rake::Task['db:seed:databases:warehouse:dimensions'].invoke

      _(ActiveRecord::Base.connection_db_config.name).must_equal 'primary'
      _(entries(configurations, 'primary')).must_be_empty
      _(entries(configurations, 'warehouse')).must_equal %w[warehouse]
      _(entries(configurations, 'archive')).must_equal %w[archive]

      ActiveRecord::Base.establish_connection(configurations.configs_for(env_name: 'test', name: 'primary'))
      assert_raises(RuntimeError) { banks.with('archive') { raise 'failed seed' } }
      _(ActiveRecord::Base.connection_db_config.name).must_equal 'primary'
    end
  end

  it 'rejects missing and Rails-hidden database configurations' do
    with_databases(database_tasks: false) do |directory, _configurations|
      seeds_root = Pathname.new(directory).join('db/seeds')
      write_seed(seeds_root, 'warehouse', 'dimensions', '')
      banks = Seedbank::DatabaseBanks.new(
        seeds_root: seeds_root,
        environment: -> { 'test' },
        connection_class: ActiveRecord::Base
      )

      error = assert_raises(Seedbank::ConfigurationError) { banks.validate! }

      _(error.message).must_include('warehouse')
      _(error.message).must_include('test')
    end
  end

  def with_databases(database_tasks: true)
    previous_configurations = ActiveRecord::Base.configurations
    previous_connection = current_connection

    Dir.mktmpdir do |directory|
      configurations = database_configurations(directory, database_tasks: database_tasks)
      ActiveRecord::Base.configurations = configurations
      ActiveRecord::Base.establish_connection(configurations.configs_for(env_name: 'test', name: 'primary'))
      Object.const_set(:SeedbankBankEntry, Class.new(ActiveRecord::Base))
      SeedbankBankEntry.table_name = 'entries'

      yield directory, configurations
    ensure
      Object.send(:remove_const, :SeedbankBankEntry) if Object.const_defined?(:SeedbankBankEntry)
    end
  ensure
    ActiveRecord::Base.configurations = previous_configurations
    if previous_connection
      ActiveRecord::Base.establish_connection(previous_connection)
    else
      ActiveRecord::Base.remove_connection
    end
  end

  def database_configurations(directory, database_tasks:)
    ActiveRecord::DatabaseConfigurations.new(
      'test' => {
        'primary' => { 'adapter' => 'sqlite3', 'database' => File.join(directory, 'primary.sqlite3') },
        'warehouse' => {
          'adapter' => 'sqlite3',
          'database' => File.join(directory, 'warehouse.sqlite3'),
          'database_tasks' => database_tasks
        },
        'archive' => { 'adapter' => 'sqlite3', 'database' => File.join(directory, 'archive.sqlite3') }
      }
    )
  end

  def current_connection
    ActiveRecord::Base.connection_db_config
  rescue ActiveRecord::ConnectionNotDefined
    nil
  end

  def create_entries_table(configurations, name)
    ActiveRecord::Base.establish_connection(configurations.configs_for(env_name: 'test', name: name, include_hidden: true))
    ActiveRecord::Base.connection.create_table(:entries) { |table| table.string :name }
    ActiveRecord::Base.establish_connection(configurations.configs_for(env_name: 'test', name: 'primary'))
  end

  def write_seed(seeds_root, database, name, contents)
    directory = seeds_root.join('databases', database)
    FileUtils.mkdir_p(directory)
    directory.join("#{name}.seeds.rb").tap { |file| file.write(contents) }.to_s
  end

  def define_seed_task(runner, name, file)
    Rake::Task.define_task(name) { |task| runner.evaluate(task, file) }
  end

  def entries(configurations, name)
    ActiveRecord::Base.establish_connection(configurations.configs_for(env_name: 'test', name: name))
    SeedbankBankEntry.order(:id).pluck(:name)
  end
end
