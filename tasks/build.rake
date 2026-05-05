# frozen_string_literal: true

require "etc"
require "pathname"

module BuildFromSource
  module Target
    # Mapping from Rust target triples to Ruby gem platform names.
    # x86_64-apple-darwin is deliberately not supported.
    RUST_TO_RUBY = {
      "x86_64-unknown-linux-gnu" => "x86_64-linux",
      "x86_64-unknown-linux-musl" => "x86_64-linux-musl",
      "aarch64-unknown-linux-gnu" => "aarch64-linux",
      "aarch64-unknown-linux-musl" => "aarch64-linux-musl",
      "aarch64-apple-darwin" => "arm64-darwin"
    }.freeze

    class << self
      def host_triple
        @host_triple ||= begin
          output = `rustc -vV`
          raise "rustc not found or failed" unless $?.success?

          match = output.match(/^host:\s*(.+)$/)
          triple = match && match[1].strip
          raise "Could not determine host triple from rustc output" unless triple

          triple
        end
      end

      def ruby_platform(rust_triple = host_triple)
        RUST_TO_RUBY.fetch(rust_triple) do
          raise "Unsupported Rust target: #{rust_triple}. Supported: #{RUST_TO_RUBY.keys.join(", ")}"
        end
      end
    end
  end

  module Paths
    class << self
      def root
        @root ||= (Pathname.new(__dir__) / "..").expand_path
      end

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

      def vendor
        root / "vendor" / "libdatadog-#{Libdatadog::LIB_VERSION}"
      end

      def vendor_target(ruby_platform = Target.ruby_platform)
        vendor / ruby_platform
      end
    end
  end

  module Builder
    class << self
      def cargo_install_cmd(source: nil, features: nil)
        cmd = %W[cargo install --bin release --root #{Paths.builder_root} --force]

        cmd += if source
          ["--path", (Pathname.new(source).expand_path / "builder").to_s]
        else
          [
            "--git", "https://github.com/DataDog/libdatadog",
            "--rev", Libdatadog::LIB_COMMIT_SHA,
            "--locked",
            "builder"
          ]
        end

        cmd += ["--no-default-features", "--features", features] if features

        cmd
      end

      def env(host_triple)
        num_jobs = begin
          Etc.nprocessors.to_s
        rescue
          "1"
        end
        {
          "PROFILE" => "release",
          "OPT_LEVEL" => "3",
          "DEBUG" => "false",
          "TARGET" => host_triple,
          "HOST" => host_triple,
          "CARGO_PKG_VERSION" => Libdatadog::LIB_VERSION,
          "CARGO_TARGET_DIR" => Paths.cargo_target.to_s,
          "OUT_DIR" => Paths.cmake_out.to_s,
          "NUM_JOBS" => num_jobs
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

    source = ENV["LIBDATADOG_SOURCE"]
    features = ENV["LIBDATADOG_FEATURES"]
    install_cmd = BuildFromSource::Builder.cargo_install_cmd(source: source, features: features)

    info = source ? "local: #{source}" : "v#{Libdatadog::LIB_VERSION} from GitHub"
    info += " with features=#{features}" if features
    puts "Installing libdatadog builder (#{info})..."
    system(*install_cmd) || raise("cargo install failed")

    target_dir = paths.vendor_target(ruby_platform)
    [target_dir, paths.cargo_target, paths.cmake_out].each(&:mkpath)

    env = BuildFromSource::Builder.env(host_triple)

    puts "Building libdatadog for #{ruby_platform} (#{host_triple})"
    puts "Output: #{target_dir}"
    system(env, paths.builder_bin.to_s, "--out", target_dir.to_s) || raise("Builder failed")

    Helpers.fix_file_permissions(target_dir.to_s)

    puts "Done! Artifacts in #{target_dir}"
  end

  desc "Remove build intermediates (tmp/) and vendor output"
  task :clean do
    [BuildFromSource::Paths.tmp, BuildFromSource::Paths.vendor].each do |dir|
      if dir.exist?
        puts "Removing #{dir}"
        dir.rmtree
      end
    end
  end
end
