# .simplecov
# frozen_string_literal: true

SimpleCov.start do
  enable_coverage :branch
  add_filter '/test/'

  coverage_dir ENV.fetch('COVERAGE_DIR', 'coverage')
  minimum_coverage line: 90, branch: 75
end
