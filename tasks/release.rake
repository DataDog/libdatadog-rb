# frozen_string_literal: true

# `rake build` (from bundler/gem_tasks) would build a binary-less gem straight
# from the gemspec. Real gems bundle the platform-specific libdatadog artifacts
# and are built via `rake gem:package`, so disable the default to avoid mistakes.
Rake::Task["build"].clear
task(:build) { raise "Build task is disabled, use gem:package instead" }

# `rake release` (from bundler/gem_tasks) tags and pushes; here releasing just
# pushes the already-built platform gems from pkg/ (the version tag lives in the
# libdatadog-rb repo, the binaries are built and packaged by CI).
Rake::Task["release"].clear
task(:release) { Rake::Task["push_to_rubygems"].invoke }

desc "Push all built gems in pkg/ to RubyGems.org"
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
