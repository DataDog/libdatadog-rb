# frozen_string_literal: true

require "pathname"
require "rubygems/package"
require "rubygems/package/tar_reader"
require "zlib"
require "stringio"

# Builds .gem packages from vendored libdatadog artifacts.
module GemPackaging
  module Platform
    # Mapping from gem platform names to the vendor platform directories
    # included in that gem.  We bundle glibc and musl variants together
    # for Linux to work around https://github.com/rubygems/rubygems/issues/3174
    GEM_TO_VENDOR = {
      "x86_64-linux" => ["x86_64-linux", "x86_64-linux-musl"],
      "aarch64-linux" => ["aarch64-linux", "aarch64-linux-musl"],
      "arm64-darwin" => ["arm64-darwin"]
    }.freeze

    ALL_VENDOR = GEM_TO_VENDOR.values.flatten.freeze

    class << self
      # Resolve a RUBY_PLATFORM string (or gem platform name) to a known
      # gem platform key.
      #
      #   resolve("x86_64-linux")      #=> "x86_64-linux"
      #   resolve("x86_64-linux-musl") #=> "x86_64-linux"
      #   resolve("arm64-darwin24")    #=> "arm64-darwin"
      def resolve(platform_string)
        return platform_string if GEM_TO_VENDOR.key?(platform_string)

        # musl suffix (x86_64-linux-musl -> x86_64-linux)
        without_musl = platform_string.sub(/-musl\z/, "")
        return without_musl if GEM_TO_VENDOR.key?(without_musl)

        # macOS Darwin version suffix (arm64-darwin24 -> arm64-darwin)
        GEM_TO_VENDOR.each_key do |gp|
          return gp if platform_string.start_with?(gp)
        end

        raise "Could not resolve platform '#{platform_string}' to a supported gem platform. " \
              "Supported: #{GEM_TO_VENDOR.keys.join(", ")}, ruby"
      end

      # Vendor platform directories needed for a given gem platform.
      def vendor_platforms(gem_platform)
        if gem_platform == "ruby"
          ALL_VENDOR
        else
          GEM_TO_VENDOR.fetch(gem_platform) do
            raise "Unknown gem platform: #{gem_platform}. " \
                  "Supported: #{GEM_TO_VENDOR.keys.join(", ")}, ruby"
          end
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

      # Vendor tree for the current library version
      def vendor
        root / "vendor" / "libdatadog-#{Libdatadog::LIB_VERSION}"
      end

      # Vendor directory for a specific platform
      def vendor_platform(name)
        vendor / name
      end

      # Output directory for built gems
      def pkg
        root / "pkg"
      end

      # The gemspec file
      def gemspec
        root / "libdatadog.gemspec"
      end

      # Expected .gem filename for a given gem platform
      def gem_file_name(gem_platform)
        spec = Gem::Specification.new do |s|
          s.name = "libdatadog"
          s.version = Libdatadog::VERSION
          s.platform = gem_platform unless gem_platform == "ruby"
        end
        spec.file_name
      end

      # Full path to the .gem for a given gem platform
      def gem(gem_platform)
        pkg / gem_file_name(gem_platform)
      end
    end
  end

  module Packager
    # Files that must have executable permissions (0755); everything else gets 0644.
    EXECUTABLE_FILES = %w[
      libdatadog-crashtracking-receiver
      libdatadog_profiling.so
      libdatadog_profiling.dylib
    ].freeze

    # Vendored files excluded from gems (not needed at runtime).
    EXCLUDED_FILES = %w[
      datadog_profiling.pc
      libdatadog_profiling.a
      datadog_profiling-static.pc
      libdatadog_profiling.debug
      DatadogConfig.cmake
    ].freeze

    class << self
      # Collect vendored files for one or more vendor platform directories,
      # filtering out tarballs and files not needed at runtime.
      # Returns paths relative to the project root (what gemspec.files expects).
      def vendor_files(*vendor_platforms)
        vendor_platforms.flat_map { |vp|
          Paths.vendor_platform(vp).glob("**/*")
            .select(&:file?)
            .map { |p| p.relative_path_from(Paths.root).to_s }
            .reject { |p| p.end_with?(".tar.gz") }
            .reject { |p| EXCLUDED_FILES.include?(File.basename(p)) }
        }
      end

      # Verify that required vendor directories exist and contain files.
      def check_vendor!(*vendor_platforms)
        missing = vendor_platforms.reject { |vp|
          dir = Paths.vendor_platform(vp)
          dir.exist? && dir.glob("**/*").any?(&:file?)
        }

        return if missing.empty?

        raise "Missing vendor artifacts for: #{missing.join(", ")}. " \
              "Expected under #{Paths.vendor}/. " \
              "Run `rake libdatadog:build` or download vendor artifacts first."
      end

      # Build a single .gem into pkg/.
      def build_gem(gem_platform:, vendor_platforms:)
        check_vendor!(*vendor_platforms)

        spec = eval(Paths.gemspec.read, nil, Paths.gemspec.to_s) # standard:disable Security/Eval
        spec.files += vendor_files(*vendor_platforms)
        spec.platform = gem_platform unless gem_platform == "ruby"

        Paths.pkg.mkpath

        puts "Building gem for platform=#{gem_platform} including: (this can take a while)"
        pp spec.files.select { |f| f.start_with?("vendor/") }

        Gem::Package.build(spec)
        # build creates the .gem in cwd; move it into pkg/
        gem_path = Paths.gem(gem_platform)
        Pathname.new(spec.file_name).rename(gem_path)
        puts("-" * 80)

        gem_path
      end

      # Inspect the built .gem and raise on unexpected file permissions.
      def validate_permissions!(gem_path)
        puts "Validating permissions in #{gem_path}..."

        Gem::Package::TarReader.new(gem_path.open("rb")) do |tar|
          data_entry = tar.find { |entry| entry.header.name == "data.tar.gz" }
          next unless data_entry

          Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(data_entry.read))) do |data_tar|
            data_tar.each do |entry|
              next if entry.directory?

              filename = File.basename(entry.header.name)
              actual = entry.header.mode.to_s(8)[-3..-1]
              expected = EXECUTABLE_FILES.include?(filename) ? "755" : "644"

              next if actual == expected

              raise "Bad permissions for #{filename} in #{gem_path}: " \
                    "got #{actual}, expected #{expected}"
            end
          end
        end

        puts "Permissions OK."
      end

      # Package a single gem platform (a GEM_TO_VENDOR key, or "ruby").
      def package(platform)
        if Platform::GEM_TO_VENDOR.key?(platform) || platform == "ruby"
          build_gem(
            gem_platform: platform,
            vendor_platforms: Platform.vendor_platforms(platform)
          )
        else
          resolved = Platform.resolve(platform)
          puts "Resolved '#{platform}' -> gem platform '#{resolved}'"
          package(resolved)
        end
      end

      # Package every supported binary gem platform plus the ruby fallback gem.
      def package_all
        Platform::GEM_TO_VENDOR.each_key { |gp| package(gp) }
        package("ruby")
      end
    end
  end
end

namespace :gem do
  desc "Package gem(s). No argument: all platforms + ruby. " \
       "With argument: a specific gem platform, 'ruby', or a RUBY_PLATFORM value.\n" \
       "  Examples: rake gem:package                    # all\n" \
       "            rake gem:package[x86_64-linux]      # one binary platform\n" \
       "            rake gem:package[ruby]              # ruby platform gem\n" \
       "            rake gem:package[arm64-darwin24]    # resolved to arm64-darwin"
  task :package, [:platform] do |_t, args|
    platform = args[:platform]

    if platform.nil? || platform.strip.empty?
      GemPackaging::Packager.package_all
    else
      GemPackaging::Packager.package(platform)
    end
  end

  desc "Validate file permissions in all gems under pkg/"
  task :validate do
    gems = GemPackaging::Paths.pkg.glob("*.gem")
    raise "No .gem files found in #{GemPackaging::Paths.pkg}" if gems.empty?

    gems.each { |gem_path| GemPackaging::Packager.validate_permissions!(gem_path) }
  end
end
