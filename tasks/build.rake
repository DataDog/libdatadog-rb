# frozen_string_literal: true

require "etc"
require "fileutils"
require "pathname"

module BuildFromSource
  module Target
    # Mapping from Rust target triples to Ruby gem platform names.
    # x86_64-apple-darwin is deliberately not supported.
    RUST_TO_RUBY = {
      "x86_64-unknown-linux-gnu" => "x86_64-linux",
      "x86_64-unknown-linux-musl" => "x86_64-linux-musl",
      "x86_64-alpine-linux-musl" => "x86_64-linux-musl",
      "aarch64-unknown-linux-gnu" => "aarch64-linux",
      "aarch64-unknown-linux-musl" => "aarch64-linux-musl",
      "aarch64-alpine-linux-musl" => "aarch64-linux-musl",
      "aarch64-apple-darwin" => "arm64-darwin"
    }.freeze

    class << self
      def host_triple
        @host_triple ||= begin
          output = `rustc -vV`
          raise "rustc not found or failed" unless $?.success?

          triple = output[/^host:\s*(.+)$/, 1]
          raise "Could not determine host triple from rustc output" unless triple

          triple = triple.strip

          triple
        end
      end

      def ruby_platform(rust_triple = host_triple)
        RUST_TO_RUBY.fetch(rust_triple) do
          raise "Unsupported Rust target: #{rust_triple}. " \
                "Supported: #{RUST_TO_RUBY.keys.join(", ")}"
        end
      end
    end
  end

  module Paths
    class << self
      # Project root
      def root
        @root ||= (Pathname.new(__dir__) / "..").expand_path
      end

      # Intermediate build artifacts
      def tmp
        root / "tmp"
      end

      def builder_root
        tmp / "builder"
      end

      def builder_bin
        builder_root / "bin" / "release"
      end

      def cargo_target
        tmp / "cargo-target"
      end

      def cmake_out
        tmp / "cmake-out"
      end

      # Vendor output tree
      def vendor
        root / "vendor" / "libdatadog-#{Libdatadog::LIB_VERSION}"
      end

      def vendor_target(ruby_platform = Target.ruby_platform)
        vendor / ruby_platform
      end
    end
  end

  module Permissions
    # Files that must be executable (0755) in the gem; everything else 0644.
    # Note: .so for Linux, .dylib for macOS.
    EXECUTABLE_FILES = %w[
      libdatadog-crashtracking-receiver
      libdatadog_profiling.so
      libdatadog_profiling.dylib
    ].freeze

    # Normalise file permissions of the built artifacts before packaging.
    def self.fix(directory)
      Dir.glob("#{directory}/**/*").each do |path|
        next unless File.file?(path)

        filename = File.basename(path)
        current = File.stat(path).mode & 0o777
        expected = EXECUTABLE_FILES.include?(filename) ? 0o755 : 0o644
        next if current == expected

        puts "Fixing permissions for #{filename}: #{current.to_s(8)} -> #{expected.to_s(8)}"
        FileUtils.chmod(expected, path)
      end
    end
  end

  module Builder
    REQUIRED_EXTRA_FEATURES = %w[otel-thread-ctx].freeze

    class << self
      # Build the cargo install command for the builder crate's `release` binary.
      #
      # source:   optional path to a local libdatadog checkout
      # features: optional comma-separated feature override
      def cargo_install_cmd(source: nil, features: nil)
        cmd = %W[cargo install --bin release --root #{Paths.builder_root} --force]

        cmd += if source
          ["--path", (Pathname.new(source).expand_path / "builder").to_s]
        else
          [
            "--git", "https://github.com/DataDog/libdatadog",
            "--tag", "v#{Libdatadog::LIB_VERSION}",
            "builder"
          ]
        end

        if features
          missing_extra_features = REQUIRED_EXTRA_FEATURES - features.split(",").map(&:strip)
          if missing_extra_features.any?
            warn "default feature set is replaced, missing required extra features: #{missing_extra_features.join(",")}"
          end

          cmd += ["--no-default-features", "--features", features]
        else
          cmd += ["--features", REQUIRED_EXTRA_FEATURES.join(",")]
        end

        cmd
      end

      # Environment variables required by the builder binary at runtime.
      #
      # The builder reads PROFILE, TARGET, and CARGO_PKG_VERSION via env::var()
      # (they are NOT baked in at compile time despite the build script's cargo:rustc-env).
      # CARGO_TARGET_DIR is needed because we are not inside a cargo workspace.
      # HOST, OUT_DIR, OPT_LEVEL, DEBUG, and NUM_JOBS are required by the cmake crate
      # used internally to build the crashtracker receiver.
      def env(host_triple)
        {
          "PROFILE" => "release",
          "OPT_LEVEL" => "3",
          "DEBUG" => "false",
          "TARGET" => host_triple,
          "HOST" => host_triple,
          "CARGO_PKG_VERSION" => Libdatadog::LIB_VERSION,
          "CARGO_TARGET_DIR" => Paths.cargo_target.to_s,
          "OUT_DIR" => Paths.cmake_out.to_s,
          "NUM_JOBS" => begin
            Etc.nprocessors
          rescue
            1
          end.to_s
        }
      end
    end
  end
end

namespace :libdatadog do
  desc "Build libdatadog from source for the current platform"
  task :build do
    host_triple = BuildFromSource::Target.host_triple
    ruby_platform = BuildFromSource::Target.ruby_platform(host_triple)
    paths = BuildFromSource::Paths

    # Install builder binary
    source = ENV["LIBDATADOG_SOURCE"]
    features = ENV["LIBDATADOG_FEATURES"]
    install_cmd = BuildFromSource::Builder.cargo_install_cmd(source: source, features: features)

    info = source ? "local: #{source}" : "v#{Libdatadog::LIB_VERSION}"
    puts "Installing builder (#{info})..."
    system(*install_cmd) || raise("Failed to install builder via cargo")

    # Prepare output directories
    target_dir = paths.vendor_target(ruby_platform)
    [target_dir, paths.cargo_target, paths.cmake_out].each(&:mkpath)

    # Invoke builder
    env = BuildFromSource::Builder.env(host_triple)

    puts "Building libdatadog for #{ruby_platform} (#{host_triple})"
    puts "Output: #{target_dir}"
    system(env, paths.builder_bin.to_s, "--out", target_dir.to_s) || raise("Builder failed")

    # Fix file permissions to match expected values for packaging
    BuildFromSource::Permissions.fix(target_dir)

    puts "Done! Artifacts in #{target_dir}"
  end

  desc "Remove build intermediates and vendor tree"
  task :clean do
    [BuildFromSource::Paths.tmp, BuildFromSource::Paths.vendor].each do |dir|
      if dir.exist?
        puts "Removing #{dir}"
        dir.rmtree
      end
    end
  end
end
