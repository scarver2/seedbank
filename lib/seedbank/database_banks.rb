# lib/seedbank/database_banks.rb
# frozen_string_literal: true

require 'pathname'

module Seedbank
  # Discovers declared database banks and routes their execution through Rails.
  class DatabaseBanks
    def initialize(
      seeds_root: Seedbank.seeds_root,
      environment: -> { Rails.env.to_s },
      connection_class: ActiveRecord::Base
    )
      @connection_class = connection_class
      @environment = environment
      @seeds_root = Pathname.new(seeds_root)
    end

    def names
      @names ||= Pathname.glob(@seeds_root.join('databases/*/').to_s).sort.map { |path| path.basename.to_s }
    end

    def validate!
      names.each { |name| configuration(name) }
    end

    def with(name)
      target = configuration(name)
      previous = @connection_class.connection_db_config
      return yield if previous == target

      @connection_class.establish_connection(target)
      yield
    ensure
      @connection_class.establish_connection(previous) if previous && previous != target
    end

    private

    def configuration(name)
      environment = @environment.call
      config = @connection_class.configurations.configs_for(env_name: environment, name: name)
      return config if config

      raise ConfigurationError,
            "Seed bank #{name.inspect} does not name an available Rails database configuration for #{environment}"
    end
  end
end
