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

  module Builder
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

        cmd += ["--no-default-features", "--features", features] if features

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

  # Ship the existing `libdd-shared-runtime-ffi` FFI crate as an additional
  # library + header, WITHOUT modifying the libdatadog source.
  #
  # Interim approach (source builds only); see the commit message and the
  # cross-library caveat before relying on it under fork.
  #
  # The aggregate `libdatadog_profiling.so` is built solely from `libdd-profiling-ffi`,
  # which does not depend on `libdd-shared-runtime-ffi`, so the `ddog_shared_runtime_*`
  # fork-lifecycle symbols never land in it. Instead we build that crate's own cdylib
  # (it already declares `crate-type = ["lib", "staticlib", "cdylib"]`) and drop it,
  # plus its cbindgen-generated `shared-runtime.h`, into the vendored tree.
  module SharedRuntimeFFI
    CRATE = "libdd-shared-runtime-ffi"
    # cargo emits lib<crate-with-underscores>.so for the cdylib
    CARGO_CDYLIB = "liblibdd_shared_runtime_ffi.so"
    # Clean, stable name we ship + bake into the cdylib's soname
    SHIPPED_LIB = "libdatadog_shared_runtime.so"
    HEADER = "shared-runtime.h"

    class << self
      # Build the cdylib + header from a local libdatadog checkout and install
      # them into the vendored platform tree. Requires LIBDATADOG_SOURCE; for
      # tag-based builds (no source checkout) this is skipped.
      def build_and_install(source:, host_triple:, target_dir:)
        unless source
          puts "[shared-runtime-ffi] LIBDATADOG_SOURCE not set; skipping (prototype only supports source builds)"
          return
        end

        source_root = Pathname.new(source).expand_path
        puts "[shared-runtime-ffi] Building #{CRATE} cdylib from #{source_root}"

        cargo_cmd = %W[
          cargo rustc
          -p #{CRATE}
          --release
          --target #{host_triple}
          --features cbindgen,catch_panic
          --crate-type cdylib
          --
          -C relocation-model=pic
          -C link-arg=-Wl,-soname,#{SHIPPED_LIB}
        ]

        env = {"CARGO_TARGET_DIR" => Paths.cargo_target.to_s}
        Dir.chdir(source_root) do
          system(env, *cargo_cmd) || raise("Failed to build #{CRATE}")
        end

        # Install the cdylib (renamed to its soname) into lib/
        cdylib_src = Paths.cargo_target / host_triple / "release" / CARGO_CDYLIB
        raise "Expected cdylib not found: #{cdylib_src}" unless cdylib_src.exist?
        lib_dst = target_dir / "lib" / SHIPPED_LIB
        lib_dst.dirname.mkpath
        FileUtils.cp(cdylib_src, lib_dst)
        puts "[shared-runtime-ffi] Installed #{lib_dst}"

        # Install the cbindgen-generated header into include/datadog/
        header_src = Paths.cargo_target / "include" / "datadog" / HEADER
        raise "Expected header not found: #{header_src}" unless header_src.exist?
        header_dst = target_dir / "include" / "datadog" / HEADER
        header_dst.dirname.mkpath
        FileUtils.cp(header_src, header_dst)
        puts "[shared-runtime-ffi] Installed #{header_dst}"
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

    # Additionally build + install the shared-runtime FFI lib/header.
    BuildFromSource::SharedRuntimeFFI.build_and_install(
      source: source,
      host_triple: host_triple,
      target_dir: target_dir
    )

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
