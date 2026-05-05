# Note: This file does not end with _spec on purpose, it should only be run after packaging, e.g. with `rake spec_validate_permissions`

require "rubygems"
require "rubygems/package"
require "rubygems/package/tar_reader"
require "libdatadog"
require "zlib"

SUPPORTED_RUBY_PLATFORMS = %w[
  x86_64-linux
  x86_64-linux-musl
  aarch64-linux
  aarch64-linux-musl
  arm64-darwin
].freeze

RSpec.describe "gem release process (after packaging)" do
  let(:gem_version) { Libdatadog::VERSION }
  let(:packaged_gem_file) { "pkg/libdatadog-#{gem_version}.gem" }

  it "sets the right permissions on the .gem files" do
    gem_files = Dir.glob("pkg/*.gem")
    expect(gem_files).to include(packaged_gem_file)

    gem_files.each do |gem_file|
      Gem::Package::TarReader.new(File.open(gem_file)) do |tar|
        data = tar.find { |entry| entry.header.name == "data.tar.gz" }

        Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(data.read))) do |data_tar|
          data_tar.each do |entry|
            filename = entry.header.name.split("/").last
            octal_permissions = entry.header.mode.to_s(8)[-3..-1]

            expected_permissions = Helpers::EXECUTABLE_FILES.include?(filename) ? "755" : "644"

            expect(octal_permissions).to eq(expected_permissions),
              "Unexpected permissions for #{filename} inside #{gem_file} (got #{octal_permissions}, " \
              "expected #{expected_permissions})"
          end
        end
      end
    end
  end

  context "when running in CI" do
    before { skip "Only validated in CI where all platforms are built" unless ENV["CI"] }

    it "packages gems for all supported platforms" do
      SUPPORTED_RUBY_PLATFORMS.each do |platform|
        gem_file = "pkg/libdatadog-#{gem_version}-#{platform}.gem"
        expect(File).to exist(gem_file), "Missing platform gem: #{gem_file}"
      end
    end
  end

  it "prefixes all public symbols in shared library files" do
    shared_lib_files = Dir.glob("vendor/libdatadog-#{Libdatadog::LIB_VERSION}/**/*.{so,dylib}")
    expect(shared_lib_files.size).to eq(SUPPORTED_RUBY_PLATFORMS.size)

    # llvm-nm understands both ELF and Mach-O, so use it when available to inspect all
    # platform binaries. Fall back to native nm, which can only inspect .so on Linux.
    llvm_nm = system("which", "llvm-nm", out: File::NULL, err: File::NULL)

    shared_lib_files.each do |shared_lib_file|
      is_dylib = shared_lib_file.end_with?(".dylib")
      next if is_dylib && !llvm_nm

      nm_tool = llvm_nm ? "llvm-nm" : "nm"
      nm_flags = is_dylib ? "-g --defined-only" : "-D --defined-only"
      raw_symbols = `#{nm_tool} #{nm_flags} #{shared_lib_file}`

      symbols = raw_symbols.split("\n")
        .map { |symbol| symbol.split(" ").last.downcase.sub(/\A_/, "") }
        .reject { |sym| sym.start_with?("_") }
        .sort
      expect(symbols.size).to be > 20 # Quick sanity check
      expect(symbols).to all(
        start_with("ddog_").or(start_with("blaze_"))
      )
    end
  end
end
