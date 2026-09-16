# lib/seedbank/inspector.rb
# frozen_string_literal: true

require 'pathname'
require 'prism'

module Seedbank
  class Inspector
    Seed = Data.define(:task_name, :file, :scope, :dependencies)

    def initialize(seeds_root: Seedbank.seeds_root, application_root: Seedbank.application_root)
      @application_root = Pathname.new(application_root)
      @seeds_root = Pathname.new(seeds_root)
    end

    def list
      grouped_seeds.map do |scope, seeds|
        heading = case scope
                  when :common then 'Common seeds'
                  when Array then "Database: #{scope.last}"
                  else "Environment: #{scope}"
                  end
        ([heading] + seeds.map { |seed| "  #{seed.task_name}  #{relative_file(seed.file)}" }).join("\n")
      end.join("\n\n")
    end

    def graph
      seeds.map do |seed|
        dependencies = seed.dependencies.empty? ? '(none)' : seed.dependencies.join(', ')
        "#{seed.task_name} -> #{dependencies}"
      end.join("\n")
    end

    private

    def seeds
      @seeds ||= original_seed + common_seeds + environment_seeds + database_seeds
    end

    def original_seed
      file = @seeds_root.join('../seeds.rb').cleanpath
      return [] unless file.file?

      [build_seed(file, :common, 'db:seed:original')]
    end

    def common_seeds
      glob(@seeds_root.join(Seedbank.matcher)).map do |file|
        build_seed(file, :common, task_name(file))
      end
    end

    def environment_seeds
      glob(@seeds_root.join('*/')).flat_map do |directory|
        scope = directory.basename.to_s
        next [] if scope == 'databases'

        glob(directory.join(Seedbank.matcher)).map do |file|
          build_seed(file, scope, task_name(file))
        end
      end
    end

    def database_seeds
      glob(@seeds_root.join('databases/*/')).flat_map do |directory|
        database = directory.basename.to_s
        glob(directory.join(Seedbank.matcher)).map do |file|
          build_seed(file, [:database, database], task_name(file))
        end
      end
    end

    def grouped_seeds
      seeds.group_by(&:scope)
    end

    def build_seed(file, scope, name)
      Seed.new(task_name: name, file: file, scope: scope, dependencies: dependencies(file))
    end

    def dependencies(file)
      result = Prism.parse_file(file.to_s)
      unless result.success?
        message = result.errors.first&.message || 'unknown parse error'
        raise ConfigurationError, "Cannot inspect #{relative_file(file)}: #{message}"
      end

      DependencyVisitor.new.tap { |visitor| result.value.accept(visitor) }.dependencies
    end

    def task_name(file)
      relative = file.relative_path_from(@seeds_root).to_s.delete_suffix('.seeds.rb')
      "db:seed:#{relative.split(File::SEPARATOR).join(':')}"
    end

    def relative_file(file)
      file.relative_path_from(@application_root)
    end

    def glob(pattern)
      Pathname.glob(pattern.to_s).sort
    end

    class DependencyVisitor < Prism::Visitor
      attr_reader :dependencies

      def initialize
        @dependencies = []
        super
      end

      def visit_call_node(node)
        if node.receiver.nil? && node.name == :after
          node.arguments&.arguments&.each { |argument| dependencies << dependency_name(argument) }
        end

        super
      end

      private

      def dependency_name(argument)
        value = case argument
                when Prism::StringNode, Prism::SymbolNode then argument.unescaped
                end

        return "db:seed:#{value}" if value && !value.empty?

        location = argument.location
        "<dynamic dependency at #{location.start_line}:#{location.start_column + 1}>"
      end
    end

    private_constant :DependencyVisitor, :Seed
  end
end
