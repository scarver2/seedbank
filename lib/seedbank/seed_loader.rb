# lib/seedbank/seed_loader.rb
# frozen_string_literal: true

module Seedbank
  # Adapts Seedbank's generated tasks to Rails' native seed-loader contract.
  class SeedLoader
    def initialize(environment: -> { Rails.env.to_s }, connection_class: ActiveRecord::Base)
      @connection_class = connection_class
      @environment = environment
    end

    def load_seed
      environment = @environment.call
      connect_to_primary_database(environment)
      Rake::Task['db:seed:common'].invoke

      environment_task = "db:seed:#{environment}"
      Rake::Task[environment_task].invoke if Rake::Task.task_defined?(environment_task)
    end

    private

    def connect_to_primary_database(environment)
      configurations = @connection_class.configurations.configs_for(env_name: environment)
      return unless configurations.length > 1

      primary = configurations.find { |configuration| configuration.name == 'primary' }
      unless primary
        raise ConfigurationError,
              "Multiple databases are configured for #{environment}, but no primary database exists"
      end

      return if @connection_class.connection_db_config == primary

      @connection_class.establish_connection(primary)
    end
  end
end
