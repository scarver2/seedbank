# test/lib/seedbank/inspector_test.rb
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

require 'test_helper'

describe Seedbank::Inspector do
  let(:inspector) { Seedbank::Inspector.new }

  it 'lists common and environment seeds in deterministic order' do
    output = inspector.list

    _(output).must_include "Common seeds\n  db:seed:original  db/seeds.rb"
    _(output).must_include "Environment: development\n  db:seed:development:users"
    _(output.index('db:seed:dependency ')).must_be :<, output.index('db:seed:dependency2 ')
  end

  it 'reports literal dependencies using execution task names' do
    output = inspector.graph

    _(output).must_include(
      'db:seed:dependent_on_several -> db:seed:dependency, db:seed:dependency2'
    )
    _(output).must_include('db:seed:development:users -> (none)')
  end

  it 'does not execute seed bodies while inspecting them' do
    FakeModel.expect :seed, true, ['never called']

    inspector.list
    inspector.graph

    assert_raises(MockExpectationError) { FakeModel.verify }
  end

  it 'exposes read-only inspection tasks outside the generated seed namespace' do
    _(Rake::Task.task_defined?('db:seedbank:list')).must_equal true
    _(Rake::Task.task_defined?('db:seedbank:graph')).must_equal true
  end

  it 'marks dependencies that require arbitrary Ruby evaluation as dynamic' do
    with_seed('dynamic.seeds.rb', "dependency = :users\nafter dependency\n") do |custom_inspector|
      _(custom_inspector.graph).must_include(
        'db:seed:dynamic -> <dynamic dependency at 2:7>'
      )
    end
  end

  it 'reports seed syntax errors without evaluating the file' do
    with_seed('broken.seeds.rb', "after(\n") do |custom_inspector|
      error = assert_raises(Seedbank::ConfigurationError) { custom_inspector.graph }

      _(error.message).must_include('Cannot inspect db/seeds/broken.seeds.rb')
    end
  end

  it 'lists database banks separately from environment seeds' do
    with_seed('databases/warehouse/dimensions.seeds.rb', "raise 'not executed'\n") do |custom_inspector|
      output = custom_inspector.list

      _(output).must_include "Database: warehouse\n  db:seed:databases:warehouse:dimensions"
      _(output).wont_include 'Environment: databases'
    end
  end

  def with_seed(filename, contents)
    Dir.mktmpdir do |directory|
      application_root = Pathname.new(directory)
      seeds_root = application_root.join('db/seeds')
      seed_file = seeds_root.join(filename)
      FileUtils.mkdir_p(seed_file.dirname)
      seed_file.write(contents)

      yield Seedbank::Inspector.new(seeds_root: seeds_root, application_root: application_root)
    end
  end
end
