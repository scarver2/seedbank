# frozen_string_literal: true
module Seedbank
  class Railtie < Rails::Railtie
    initializer 'seedbank.configure_seed_loader', after: 'active_record.initialize_database' do
      ActiveRecord::Tasks::DatabaseTasks.seed_loader = Seedbank::SeedLoader.new
    end

    rake_tasks do
      Seedbank.load_tasks
    end
  end
end
