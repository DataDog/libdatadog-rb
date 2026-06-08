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

  module Builder
    LIBDATADOG_GIT_URL = "https://github.com/DataDog/libdatadog"

    class << self
      # Build the cargo install command for the builder crate's `release` binary.
      #
      # The libdatadog code to build is selected from exactly one of the following,
      # which are mutually exclusive (passing more than one raises):
      #   source: path to a local libdatadog checkout. Built via --path, WITHOUT
      #           --locked, since the checkout may be modified locally.
      #   tag:    a git tag.    Built via --git --tag <tag> --locked.
      #   ref:    a git commit. Built via --git --rev <ref> --locked.
      # When none are given, defaults to the pinned --tag v<LIB_VERSION> --locked.
      #
      # Git builds pass --locked so they reproducibly use libdatadog's Cargo.lock.
      # features: optional comma-separated cargo feature override, appended in all cases.
      def cargo_install_cmd(source: nil, tag: nil, ref: nil, features: nil)
        source = presence(source)
        tag = presence(tag)
        ref = presence(ref)
        features = presence(features)

        selected = {source: source, tag: tag, ref: ref}.select { |_, value| value }
        if selected.size > 1
          raise "Only one of source, tag, ref may be set at a time (got: #{selected.keys.join(", ")})"
        end

        cmd = %W[cargo install --bin release --root #{Paths.builder_root} --force]

        cmd += if source
          ["--path", (Pathname.new(source).expand_path / "builder").to_s]
        else
          flag, value =
            if tag
              ["--tag", tag]
            elsif ref
              ["--rev", ref]
            else
              ["--tag", "v#{Libdatadog::LIB_VERSION}"]
            end
          ["--git", LIBDATADOG_GIT_URL, flag, value, "--locked", "builder"]
        end

        cmd += ["--no-default-features", "--features", features] if features

        cmd
      end

      # Normalize a value to nil when it is nil or blank, otherwise return it unchanged.
      def presence(value)
        value if value && !value.to_s.strip.empty?
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

    # Install builder binary. source / tag / ref are mutually exclusive; precedence
    # and validation are handled by cargo_install_cmd.
    source = ENV["LIBDATADOG_SOURCE"]
    tag = ENV["LIBDATADOG_TAG"]
    ref = ENV["LIBDATADOG_COMMIT"]
    features = ENV["LIBDATADOG_FEATURES"]

    install_cmd = BuildFromSource::Builder.cargo_install_cmd(source: source, tag: tag, ref: ref, features: features)

    info =
      if source
        "local: #{source}"
      elsif tag
        "tag #{tag}"
      elsif ref
        "commit #{ref}"
      else
        "v#{Libdatadog::LIB_VERSION}"
      end
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
    Helpers.fix_file_permissions(target_dir.to_s)

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
