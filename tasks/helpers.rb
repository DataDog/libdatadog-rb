# frozen_string_literal: true

# TODO: only needed for `Fileutils.cp`
require 'fileutils'

require 'open-uri'
require 'rubygems/package'

module Libdatadog
  module Gem
    class << self
      # This gem's libdatadog version
      def version
        Libdatadog::LIB_VERSION
      end

      # This gem's root path
      def root
        (Pathname.new(__dir__) / '..').expand_path
      end
    end
  end

  module Cache
    class << self
      # Cached tarball path
      def tarball
        source / Source::Tarball.filename
      end

      # Where to cache source code
      def source
        Gem.root / 'tmp' / 'source'
      end

      # Build cache paths
      def make!
        source.mkpath
      end
    end
  end

  module Target
    # TODO: not super happy about that one, it ocud use some cleanup

    # Ruby gem platform => Rust target triple
    RUST = {
      'arm64-darwin'       => 'aarch64-apple-darwin',
      'x86_64-darwin'      => 'x86_64-apple-darwin',
      'x86_64-linux'       => 'x86_64-unknown-linux-gnu',
      'x86_64-linux-musl'  => 'x86_64-unknown-linux-musl',
      'aarch64-linux'      => 'aarch64-unknown-linux-gnu',
      'aarch64-linux-musl' => 'aarch64-unknown-linux-musl',
    }.freeze

    # Rust target => LLVM target
    #
    # LLVM target is used in the release tarball directory name.
    #
    # These match the names that appear in the pre-built GitHub release tarballs
    # e.g. `libdatadog-x86_64-unknown-linux-gnu.tar.gz` extracts to
    # `libdatadog-x86_64-unknown-linux-gnu/`.
    LLVM = {
      'aarch64-apple-darwin'       => 'aarch64-apple-darwin',
      'x86_64-apple-darwin'        => 'x86_64-apple-darwin',
      'x86_64-unknown-linux-gnu'   => 'x86_64-unknown-linux-gnu',
      'x86_64-unknown-linux-musl'  => 'x86_64-alpine-linux-musl',
      'aarch64-unknown-linux-gnu'  => 'aarch64-unknown-linux-gnu',
      'aarch64-unknown-linux-musl' => 'aarch64-alpine-linux-musl',
    }.freeze

    # {os, libc} => system libraries to link
    #
    # Think LDFLAGS, substituted into `DatadogConfig.cmake` (`@Datadog_LIBRARIES@`).
    LIBS = {
      'linux-gnu'    => '-ldl -lrt -lpthread -lc -lm -lrt -lpthread -lutil -ldl -lutil',
      'linux-musl'   => '-lssp_nonshared -lc',
      'apple-darwin' => '-framework Security -framework CoreFoundation -liconv -lSystem -lresolv -lc -lm -liconv',
    }.freeze

    class << self
      # Current ruby platform
      def ruby_platform
        platform = ::Gem::Platform.local.to_s

        # strip -gnu suffix off off linux
        # TODO: questionable, the proper ruby platform should have -gnu if it doesn't run on musl
        platform = platform[0..-5] if platform.end_with?('-gnu')

        # strip version-specific scope off of darwin platform
        platform = platform.gsub(/-darwin-?\d*$/, '-darwin') if platform.include?('darwin')

        # handle misreported musl
        platform = RbConfig::CONFIG['arch'] if RbConfig::CONFIG['arch'].include?('-musl') && !platform.include?('-musl')

        platform
      end

      # Local Rust target triple
      def rust_target
        platform = ruby_platform
        RUST.fetch(platform) do
          raise "No Rust target mapping for Ruby platform #{platform.inspect}. " \
            "Known platforms: #{RUST.keys.inspect}"
        end
      end

      # Local LLVM target triple
      def llvm_target
        LLVM.fetch(rust_target) do
          raise "No LLVM target mapping for Rust target #{rust_target.inspect}."
        end
      end

      # Shared library extension for the platform
      def shared_ext
        ruby_platform.include?('darwin') ? 'dylib' : 'so'
      end

      # Libraries to link for the local platform
      def liblink
        case rust_target
        when /-darwin$/
          LIBS.fetch('apple-darwin')
        when /-musl$/
          LIBS.fetch('linux-musl')
        when /-gnu$/
          LIBS.fetch('linux-gnu')
        else
          raise "No LIB mapping for Rust target #{rust_target.inspect}."
        end
      end
    end
  end

  module Vendor
    class << self
      # toplevel vendoring folder
      def root
        Gem.root / 'vendor'
      end

      # platform-agnostic level for libdatadog vendoring
      def libdatadog
        root / "libdatadog-#{Gem.version}"
      end

      # platform-specific level for libdatadog vendoring
      def target
        libdatadog / Target.ruby_platform / "libdatadog-#{Target.llvm_target}"
      end
    end
  end

  module Source
    class << self
      # Are we using a local source (e.g a live repository checkout)?
      def local?
        !!ENV['LIBDATADOG_SRC']
      end

      # Location of libdatadog source code
      def root
        local? ? Pathname.new(ENV['LIBDATADOG_SRC']).expand_path : (Cache.source / Tarball.basename)
      end

      # Version of libdatadog source code
      def version
        return unless cargo_toml.file?

        cargo_toml.each_line do |line|
          if (m = line.match(/^\s*version\s*=\s*"([^"]+)"/))
            return m[1]
          end
        end

        nil
      end

      # Location of main project build file
      def cargo_toml
        root / 'Cargo.toml'
      end

      # Valididity checks
      #
      # TODO: Should probably return which checks failed for granular cause reporting
      def valid?
        File.exist?(cargo_toml) && Gem.version == version
      end
    end

    module Tarball
      class << self
        # Remote location of the tarball
        def url
          "https://github.com/DataDog/libdatadog/archive/refs/tags/v#{Gem.version}#{ext}"
        end

        # Local basename
        def basename
          "libdatadog-#{Gem.version}"
        end

        # Archive format
        def ext
          '.tar.gz'
        end

        # Full filename (without path)
        def filename
          "#{basename}#{ext}"
        end

        # Download and store locally (unconditionally, no checks)
        def fetch!
          URI.open(url, 'rb') do |remote| # standard:disable Security/Open
            Cache.tarball.open('wb') do |local|
              IO.copy_stream(remote, local)
            end
          end
        end

        # `fetch!` but safe and lazy
        def fetch
          return if Cache.tarball.file?

          Cache.make!

          fetch!
        end

        # EXtract source locally (unconditionally, no checks)
        def extract!
          system('tar', 'xzf', Cache.tarball.to_path, '-C', Cache.source.to_path) || raise('tar extraction failed')
        end

        # `extract!` but safe and lazy
        def extract
          return if Source.root.directory?

          Source.root.rmtree

          extract!
        end
      end
    end
  end

  module Cargo
    class << self
      # main crate to build
      #
      # TODO: not sure this value is correct
      def crate
        'libdd-profiling-ffi'
      end

      # crate features to build
      def features
        %w[
          data-pipeline-ffi
          cbindgen
          ddtelemetry-ffi
          crashtracker-ffi
          crashtracker-collector
          crashtracker-receiver
          demangler
          ddsketch-ffi
          datadog-library-config-ffi
          datadog-log-ffi
          datadog-ffe-ffi
        ]
      end

      # perform build
      def build
        build! *%W[
          -p #{crate}
          --features #{features.join(',')}
          --release
          --target #{Target.rust_target}
        ]

        # TODO: this is only a build dependency, and should be hoisted out
        build! *%w[-p tools --bin dedup_headers --release]
      end

      # remove all build artifacts
      def clean!
        out.rmtree
      end

      # build output directory
      def out
        Source.root / 'target'
      end

      # execute cargo build
      def build!(*args)
        cmd = %w[cargo build] + args

        Dir.chdir(Source.root) do
          system(*cmd) or raise "failed (exit #{$?.exitstatus}): #{cmd.inspect}"
        end
      end

      # local platform artifact build target
      def target
        out / Target.rust_target / 'release'
      end
    end

    # TODO: this section is very crude and could use some cleanup for readability and ease of maintenance
    module Install
      module Headers
        def self.install
          src_include = Source.root / 'target' / 'include' / 'datadog'
          dst_include = Vendor.target / 'include' / 'datadog'

          dst_include.mkpath

          headers = src_include.glob('*.h')
          raise "No headers found in #{src_include} — did cbindgen run?" if headers.empty?

          headers.each do |h|
            FileUtils.cp(h.to_path, dst_include.to_path)
            puts "  Copied #{h.basename}"
          end

          dedup_bin = Source.root / 'target' / 'release' / 'dedup_headers'
          base_header = dst_include / 'common.h'
          child_headers = dst_include.glob('*.h').reject { |h| h == base_header }

          unless child_headers.empty?
            puts "  Running dedup_headers on #{child_headers.length} child headers..."
            cmd = [dedup_bin.to_path, base_header.to_path, *child_headers.map(&:to_path)]
            system(*cmd) or raise "failed (exit #{$?.exitstatus}): #{cmd.inspect}"
          end

          # After the existing dedup_headers call, clean up intra-file duplicate
          # typedefs in common.h.  cbindgen can emit the same typedef from
          # multiple crate boundaries; the dedup_headers tool only strips
          # child-vs-base duplicates, not intra-file ones.
          content = base_header.read

          # Remove multiline typedef redefinitions: a "typedef struct X X;"
          # forward decl where the full "} X;" body already exists.
          multiline_dupes = 0
          content.gsub!(/^typedef struct (\w+) \1;\n/) do |match|
            if content.include?("} #{$1};")
              multiline_dupes += 1
              ""
            else
              match
            end
          end

          # Remove identical single-line typedef duplicates (e.g. pointer
          # typedefs like "typedef struct X *Y;" emitted by two crates).
          seen = Set.new
          lines = content.lines
          before = lines.size
          lines.reject! do |line|
            line.start_with?('typedef ') && line.rstrip.end_with?(';') && !seen.add?(line)
          end
          singleline_dupes = before - lines.size

          if multiline_dupes > 0 || singleline_dupes > 0
            puts "  Removed #{multiline_dupes} multiline and #{singleline_dupes} single-line duplicate typedef(s) from common.h"
            base_header.write(lines.join)
          end
        end
      end

      module Lib
        def self.install
          dst_lib = Vendor.target / 'lib'
          dst_lib.mkpath

          ext = Target.shared_ext

          src_dylib  = Cargo.target / "libdatadog_profiling_ffi.#{ext}"
          src_static = Cargo.target / 'libdatadog_profiling_ffi.a'

          dst_dylib  = dst_lib / "libdatadog_profiling.#{ext}"
          dst_static = dst_lib / 'libdatadog_profiling.a'

          raise "Shared library not found at #{src_dylib}" unless src_dylib.exist?

          FileUtils.cp(src_dylib, dst_dylib)
          dst_dylib.chmod(0o755)
          puts "  Installed #{dst_dylib.basename}"

          if File.exist?(src_static)
            FileUtils.cp(src_static, dst_static)
            dst_static.chmod(0o644)
            puts "  Installed #{dst_static.basename}"
          end

          if Target.ruby_platform.include?('darwin')
            puts '  Fixing dylib install name with install_name_tool...'
            cmd = %W[install_name_tool -id @rpath/#{dst_dylib.basename} #{dst_dylib}]
            system(*cmd) or raise "failed (exit #{$?.exitstatus}): #{cmd.inspect}"
          end
        end
      end

      module PkgConfig
        def self.install
          dst_pkgconfig = Vendor.target / 'lib' / 'pkgconfig'
          dst_pkgconfig.mkpath

          template_dir = Source.root / Cargo.crate

          %w[datadog_profiling_with_rpath.pc datadog_profiling.pc].each do |pc_name|
            template = template_dir / "#{pc_name}.in"
            raise "pkgconfig template not found: #{template}" unless template.file?

            content = template.read.gsub('@Datadog_VERSION@', Libdatadog::LIB_VERSION)
            (dst_pkgconfig / pc_name).write(content)
            puts "  Generated #{pc_name}"
          end
        end
      end

      module CMakeModule
        def self.install
          cmake_template = Source.root / 'cmake' / 'DatadogConfig.cmake.in'
          return unless cmake_template.exist?

          dst_cmake = Vendor.target / 'cmake'
          dst_cmake.mkpath

          content = cmake_template.read
            .gsub('@Datadog_VERSION@', Libdatadog::LIB_VERSION)
            .gsub('@Datadog_LIBRARIES@', Target.liblink)
          (dst_cmake / 'DatadogConfig.cmake').write(content)
          puts '  Generated DatadogConfig.cmake'
        end
      end

      module CrashTrackingReceiver
        def self.install
          cmake_src = Source.root / 'libdd-crashtracker'

          unless (cmake_src / 'CMakeLists.txt').exist?
            puts '  WARNING: libdd-crashtracker/CMakeLists.txt not found, skipping crashtracking receiver'
            return
          end

          puts '  Building crashtracking receiver via CMake...'

          build_dir = Source.root / 'target' / 'cmake-build-crashtracker'
          build_dir.mkpath

          # Point CMake at the vendor dir so it finds DatadogConfig.cmake, headers, and libraries
          datadog_root = Vendor.target

          cmake_configure = %W[
            cmake
            -S #{cmake_src}
            -B #{build_dir}
            -DCMAKE_BUILD_TYPE=Release
            -DDatadog_ROOT=#{datadog_root}
            -DCMAKE_INSTALL_PREFIX=#{Vendor.target}
          ]

          if Target.ruby_platform.include?('darwin') && Target.rust_target == 'x86_64-apple-darwin'
            cmake_configure += %w[-DCMAKE_OSX_ARCHITECTURES=x86_64]
          end

          system(*cmake_configure) or raise "failed (exit #{$?.exitstatus}): #{cmake_configure.inspect}"

          cmake_build = %W[cmake --build #{build_dir}]
          system(*cmake_build) or raise "failed (exit #{$?.exitstatus}): #{cmake_build.inspect}"

          cmake_install = %W[cmake --install #{build_dir}]
          system(*cmake_install) or raise "failed (exit #{$?.exitstatus}): #{cmake_install.inspect}"

          receiver_bin = Vendor.target / 'bin' / 'libdatadog-crashtracking-receiver'
          if receiver_bin.exist?
            receiver_bin.chmod(0o755)
            puts '  Installed libdatadog-crashtracking-receiver'
          else
            puts "  WARNING: crashtracking receiver binary not found at #{receiver_bin}"
          end
        end
      end

      module Licenses
        def self.install
          %w[
            LICENSE
            LICENSE-3rdparty.yml
            NOTICE
          ].each do |name|
            src_file = Source.root / name

            next unless src_file.exist?

            FileUtils.cp(src_file, Vendor.target / name)

            puts "  Copied #{name}"
          end
        end
      end
    end
  end
end
