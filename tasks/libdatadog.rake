# frozen_string_literal: true

require_relative 'helpers'

namespace :libdatadog do
  namespace :src do
    desc 'Download the libdatadog source archive tarball'
    task :fetch do
      Libdatadog::Source::Tarball.fetch unless Libdatadog::Source.local?
    end

    namespace :fetch do
      desc 'Remove the downloaded source archive tarball'
      task :clean do
        Libdatadog::Cache.tarball.delete if Libdatadog::Cache.tarball.exist?
      end
    end

    desc 'Extract the libdatadog source archive'
    task extract: ['libdatadog:src:fetch'] do
      Libdatadog::Source::Tarball.extract unless Libdatadog::Source.local?
    end

    namespace :extract do
      desc 'Remove the extracted source tree'
      task :clean do
        Libdatadog::Source.root.rmtree unless Libdatadog::Source.local?
      end
    end

    desc 'Remove downloaded source archive and extracted tree'
    task clean: ['libdatadog:src:fetch:clean', 'libdatadog:src:extract:clean']

    desc 'Validate the libdatadog source tree'
    task :check do
      raise 'invalid source tree' unless Libdatadog::Source.valid?
    end
  end

  desc 'Cargo-build the FFI shared library and dedup_headers tool'
  task compile: ['libdatadog:src:extract', 'libdatadog:src:check'] do
    src = Libdatadog::Source.root

    puts
    puts '=' * 72
    puts 'Compiling libdatadog from source'
    puts "  Source dir    : #{src}"
    puts "  Ruby platform : #{Libdatadog::Target.ruby_platform}"
    puts "  Rust target   : #{Libdatadog::Target.rust_target}"
    puts "  LLVM target   : #{Libdatadog::Target.llvm_target}"
    puts '=' * 72
    puts

    # TODO: cbindgen header generation is driven by each FFI crate's build.rs,
    # but cargo only reruns build.rs when build.rs itself or cbindgen.toml
    # changes — not when the Rust source files change.  This means incremental
    # builds can leave stale generated headers in target/include/datadog/.
    # A workaround is to delete the cached headers before building, but a
    # proper fix would be to add appropriate `cargo:rerun-if-changed` directives
    # in libdatadog's build-common/src/cbindgen.rs.
    Libdatadog::Cargo.build
  end

  namespace :compile do
    desc 'Remove cargo target directory inside the source tree'
    task :clean do
      Libdatadog::Cargo.clean!
    end
  end

  desc 'Install compiled libdatadog artifacts into the vendor tree'
  task install: ['libdatadog:compile'] do
    puts
    puts "Installing into #{Libdatadog::Vendor.target}..."
    Libdatadog::Vendor.target.rmtree
    Libdatadog::Vendor.target.mkpath

    Libdatadog::Cargo::Install::Headers.install
    Libdatadog::Cargo::Install::Lib.install
    Libdatadog::Cargo::Install::PkgConfig.install
    Libdatadog::Cargo::Install::CMakeModule.install
    Libdatadog::Cargo::Install::Licenses.install
    Libdatadog::Cargo::Install::CrashTrackingReceiver.install

    puts
    puts 'Vendor tree ready at:'
    puts "  #{Libdatadog::Vendor.target}"
  end

  desc 'Remove source cache and cargo build artifacts (but not vendor tree)'
  task clean: ['libdatadog:src:clean', 'libdatadog:compile:clean']
end
