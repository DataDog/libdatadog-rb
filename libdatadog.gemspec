# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "libdatadog/version"

# All Ruby platform strings for which this gem ships pre-built binaries.
# Used by the Rakefile package task to validate and collect vendor artifacts.
unless defined?(SUPPORTED_RUBY_PLATFORMS)
  SUPPORTED_RUBY_PLATFORMS = %w[
    x86_64-linux
    x86_64-linux-musl
    aarch64-linux
    aarch64-linux-musl
    arm64-darwin
  ].freeze
end

Gem::Specification.new do |spec|
  spec.name = "libdatadog"
  spec.version = Libdatadog::VERSION
  spec.authors = ["Datadog, Inc."]
  spec.email = ["dev@datadoghq.com"]

  spec.summary = "Library of common code used by Datadog Continuous Profiler for Ruby"
  spec.description =
    "libdatadog is a Rust-based utility library for Datadog's ddtrace gem."
  spec.homepage = "https://docs.datadoghq.com/tracing/"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 2.5.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/datadog/libdatadog-rb"

  # Require releases on rubygems.org to be coming from multi-factor-auth-authenticated accounts
  spec.metadata["rubygems_mfa_required"] = "true"

  vendor_excluded_files = %w[
    datadog_profiling.pc
    libdatadog_profiling.a
    datadog_profiling-static.pc
    libdatadog_profiling.debug
    DatadogConfig.cmake
  ].freeze

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`
      .split("\x0")
      .reject do |f|
        (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features|publish)/|\.(?:git|travis|circleci)|appveyor)})
      end
      .reject do |f|
        [".rspec", ".standard.yml", "Rakefile", "docker-compose.yml", "Gemfile", "README.md", "CONTRIBUTING.md", "LICENSE-3rdparty.yml"].include?(f)
      end
      .reject { |f| f.end_with?(".tar.gz") }
      .reject { |f| f.end_with?(".nix") || f.start_with?("flake.") }
  end

  # Include pre-built binaries for all supported platforms (populated by CI before packaging).
  gem_root = File.expand_path(__dir__)
  SUPPORTED_RUBY_PLATFORMS.each do |platform|
    vendor_dir = "#{gem_root}/vendor/libdatadog-#{Libdatadog::LIB_VERSION}/#{platform}"
    next unless Dir.exist?(vendor_dir)

    Dir.glob("#{vendor_dir}/**/*").each do |file|
      next unless File.file?(file)
      next if vendor_excluded_files.include?(File.basename(file))

      spec.files << file.sub("#{gem_root}/", "")
    end
  end

  spec.require_paths = ["lib"]
end
