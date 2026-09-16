# test/lib/seedbank/public_entrypoint_test.rb
# frozen_string_literal: true

require 'open3'
require 'tmpdir'

require 'test_helper'

describe 'Seedbank public entrypoint' do
  it 'exposes a semantic version without requiring the internal version file' do
    library_path = File.expand_path('../../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(
      {
        'BUNDLE_BIN_PATH' => nil,
        'BUNDLE_GEMFILE' => nil,
        'RUBYLIB' => nil,
        'RUBYOPT' => nil
      },
      RbConfig.ruby,
      '-I', library_path,
      '-e', 'require "seedbank"; print Seedbank::VERSION',
      chdir: Dir.tmpdir
    )

    assert status.success?, stderr
    _(stdout).must_match(
      /\A\d+\.\d+\.\d+(?:[.-][0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z/
    )
    _(Gem::Version.correct?(stdout)).must_equal true
  end
end
