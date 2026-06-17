# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake" unless RUBY_VERSION < "2.6"

require "fileutils"
require "pry"

RSpec::Core::RakeTask.new(:spec)

task default: [
  :spec,
  (:standard unless RUBY_VERSION < "2.6")
].compact

desc "Release all packaged gems"
task push_to_rubygems: [
  :"release:guard_clean"
] do
  [
    "gem push pkg/libdatadog-#{Libdatadog::VERSION}.gem",
    "gem push pkg/libdatadog-#{Libdatadog::VERSION}-x86_64-linux.gem",
    "gem push pkg/libdatadog-#{Libdatadog::VERSION}-aarch64-linux.gem",
    "gem push pkg/libdatadog-#{Libdatadog::VERSION}-arm64-darwin.gem"
  ].each do |command|
    puts "Running: #{command}"
    abort unless system(command)
  end
end

module Helpers
  # Files that should have executable permissions (755) in the gem
  # Note: .so for Linux, .dylib for macOS
  EXECUTABLE_FILES = ["libdatadog-crashtracking-receiver", "libdatadog_profiling.so", "libdatadog_profiling.dylib"].freeze

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
end

Rake::Task["build"].clear
task(:build) { raise "Build task is disabled, use gem:package instead" }

Rake::Task["release"].clear
task(:release) { Rake::Task["push_to_rubygems"].invoke }

# Load additional tasks
Dir.glob("tasks/**/*.rake").each { |r| import r }
