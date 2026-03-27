# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake" unless RUBY_VERSION < "2.6"

require "etc"
require "fileutils"
require "pry"
require "rubygems/package"

RSpec::Core::RakeTask.new(:spec)

# Note: When packaging rc releases and the like, you may need to set this differently from LIB_VERSION
LIB_VERSION_TO_PACKAGE = Libdatadog::LIB_VERSION

unless LIB_VERSION_TO_PACKAGE.start_with?(Libdatadog::LIB_VERSION)
  raise "`LIB_VERSION_TO_PACKAGE` setting in <Rakefile> (#{LIB_VERSION_TO_PACKAGE}) does not match " \
    "`LIB_VERSION` setting in <lib/libdatadog/version.rb> (#{Libdatadog::LIB_VERSION})"
end

RUST_TRIPLE_TO_RUBY_PLATFORM = {
  "x86_64-unknown-linux-gnu" => "x86_64-linux",
  "x86_64-unknown-linux-musl" => "x86_64-linux-musl",
  "aarch64-unknown-linux-gnu" => "aarch64-linux",
  "aarch64-unknown-linux-musl" => "aarch64-linux-musl",
  "aarch64-apple-darwin" => "arm64-darwin",
  "x86_64-apple-darwin" => "arm64-darwin"
}.freeze

task default: [
  :spec,
  (:standard unless RUBY_VERSION < "2.6")
].compact

desc "Build libdatadog FFI library from source using the builder crate"
task :build_ffi do
  rustc_output = `rustc -vV`
  raise "rustc not found or failed" unless $?.success?

  host_triple = rustc_output.match(/^host:\s*(.+)$/)[1].strip
  ruby_platform = RUST_TRIPLE_TO_RUBY_PLATFORM.fetch(host_triple) do
    raise "Unsupported host triple: #{host_triple}"
  end

  target_directory = File.expand_path("vendor/libdatadog-#{Libdatadog::LIB_VERSION}/#{ruby_platform}")
  FileUtils.mkdir_p(target_directory)

  install_root = File.expand_path("ext/release-bin")
  features = ENV["LIBDATADOG_FEATURES"]
  source_path = ENV["LIBDATADOG_SOURCE_PATH"]

  install_cmd = if source_path
    [
      "cargo", "install",
      "--path", File.join(source_path, "builder"),
      "--bin", "release",
      "--root", install_root,
      "--force"
    ]
  else
    [
      "cargo", "install",
      "--git", "https://github.com/DataDog/libdatadog",
      "--tag", "v#{Libdatadog::LIB_VERSION}",
      "--bin", "release",
      "--root", install_root,
      "--force",
      "builder"
    ]
  end

  if features
    install_cmd += ["--no-default-features", "--features", features]
  end

  feature_info = features ? " with features=#{features}" : ""
  puts "Installing libdatadog builder (#{source_path ? "from #{source_path}" : "v#{Libdatadog::LIB_VERSION} from GitHub"}#{feature_info})..."
  system(*install_cmd) || raise("cargo install failed")

  # Build env vars required by the cmake crate and cargo sub-invocations inside the builder
  cargo_target_dir = File.expand_path("ext/cargo-target")
  out_dir = File.expand_path("ext/cmake-out")
  FileUtils.mkdir_p(cargo_target_dir)
  FileUtils.mkdir_p(out_dir)
  num_jobs = begin
    Etc.nprocessors.to_s
  rescue
    "1"
  end

  env = {
    "PROFILE" => "release",
    "OPT_LEVEL" => "3",
    "DEBUG" => "false",
    "HOST" => host_triple,
    "TARGET" => host_triple,
    "NUM_JOBS" => num_jobs,
    "OUT_DIR" => out_dir,
    "CARGO_PKG_VERSION" => Libdatadog::LIB_VERSION,
    "CARGO_TARGET_DIR" => cargo_target_dir
  }

  binary = File.join(install_root, "bin", "release")
  puts "Building libdatadog for #{ruby_platform} (#{host_triple})"
  puts "Output: #{target_directory}"

  system(env, binary, "--out", target_directory) || raise("Builder failed")

  Helpers.fix_file_permissions(target_directory)
end

desc "Package lib built releases as gems"
task package: [
  :spec,
  (:"standard:fix" unless RUBY_VERSION < "2.6"),
  :build_ffi
] do
  gemspec = eval(File.read("libdatadog.gemspec"), nil, "libdatadog.gemspec") # standard:disable Security/Eval
  FileUtils.mkdir_p("pkg")

  built_platforms = Dir.glob("vendor/libdatadog-#{Libdatadog::LIB_VERSION}/*/").map { |d| File.basename(d) }
  raise "No built platforms found in vendor/" if built_platforms.empty?

  Helpers.fix_file_permissions_for_gem(gemspec.files)

  # Fallback package with all built binaries
  Helpers.package_for(gemspec, ruby_platform: nil, files: Helpers.files_for(*built_platforms))

  # Platform-specific gem for each built platform
  built_platforms.each do |platform|
    Helpers.package_for(gemspec, ruby_platform: platform, files: Helpers.files_for(platform))
  end
end

Rake::Task["package"].enhance { Rake::Task["spec_validate_permissions"].execute }

task :spec_validate_permissions do
  require "rspec"
  RSpec.world.reset # If any other tests ran before, flushes them
  ret = RSpec::Core::Runner.run(["spec/gem_packaging.rb"])
  raise "Release tests failed! See error output above." if ret != 0
end

desc "Release all packaged gems"
task push_to_rubygems: [
  :package,
  :"release:guard_clean"
] do
  Dir.glob("pkg/libdatadog-#{Libdatadog::VERSION}*.gem").each do |gem_file|
    command = "gem push #{gem_file}"
    puts "Running: #{command}"
    abort unless system(command)
  end
end

module Helpers
  # Files that should have executable permissions (755) in the gem
  # Note: .so for Linux, .dylib for macOS
  EXECUTABLE_FILES = ["libdatadog-crashtracking-receiver", "libdatadog_profiling.so", "libdatadog_profiling.dylib"].freeze

  def self.package_for(gemspec, ruby_platform:, files:)
    target_gemspec = gemspec.dup
    target_gemspec.files += files
    target_gemspec.platform = ruby_platform if ruby_platform

    puts "Building with ruby_platform=#{ruby_platform.inspect} including: (this can take a while)"
    pp target_gemspec.files

    package = Gem::Package.build(target_gemspec)
    FileUtils.mv(package, "pkg")
    puts("-" * 80)
  end

  def self.fix_file_permissions_for_gem(files)
    files.each do |path|
      next unless File.file?(path)

      filename = File.basename(path)
      current_permissions = File.stat(path).mode & 0o777
      expected = EXECUTABLE_FILES.include?(filename) ? 0o755 : 0o644

      if current_permissions != expected
        puts "Fixing permissions for #{path}: #{current_permissions.to_s(8)} -> #{expected.to_s(8)}"
        FileUtils.chmod(expected, path)
      end
    end
  end

  def self.fix_file_permissions(directory)
    Dir.glob("#{directory}/**/*").each do |path|
      next unless File.file?(path)

      filename = File.basename(path)
      current_permissions = File.stat(path).mode & 0o777

      if EXECUTABLE_FILES.include?(filename)
        # Should be executable (755), fix if not
        if current_permissions != 0o755
          puts "Fixing permissions for #{filename}: #{current_permissions.to_s(8)} -> 755"
          FileUtils.chmod(0o755, path)
        end
      elsif current_permissions != 0o644
        # Should be non-executable (644), fix if not
        puts "Fixing permissions for #{filename}: #{current_permissions.to_s(8)} -> 644"
        FileUtils.chmod(0o644, path)
      end
    end
  end

  def self.files_for(
    *included_platforms,
    excluded_files: [
      "datadog_profiling.pc", # we use the datadog_profiling_with_rpath.pc variant
      "libdatadog_profiling.a", "datadog_profiling-static.pc", # We don't use the static library
      "libdatadog_profiling.debug", # We don't include debug info
      "DatadogConfig.cmake" # We don't compile using cmake
    ]
  )
    files = []

    included_platforms.each do |platform|
      dir = "vendor/libdatadog-#{Libdatadog::LIB_VERSION}/#{platform}"
      next unless Dir.exist?(dir)

      files +=
        Dir.glob("#{dir}/**/*")
          .select { |path| File.file?(path) }
          .reject { |path| excluded_files.include?(File.basename(path)) }
    end

    files
  end
end

Rake::Task["build"].clear
task(:build) { raise "Build task is disabled, use package instead" }

Rake::Task["release"].clear
task(:release) { Rake::Task["push_to_rubygems"].invoke }
