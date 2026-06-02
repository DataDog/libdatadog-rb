# frozen_string_literal: true

require "libdatadog"

pkgconfig_folder = Libdatadog.pkgconfig_folder
abort "FAIL: Libdatadog.pkgconfig_folder returned nil (no binaries for #{RUBY_PLATFORM}?)" unless pkgconfig_folder

libdir = File.expand_path("../../lib", pkgconfig_folder)
includedir = File.expand_path("../../include", pkgconfig_folder)

src = File.expand_path("smoke_test.c", __dir__)
out = File.expand_path("smoke_test", __dir__)

# Compile
cc = ENV.fetch("CC", "cc")
compile_cmd = [cc, "-o", out, src, "-I#{includedir}", "-L#{libdir}", "-ldatadog_profiling", "-Wl,-rpath,#{libdir}"]
puts "Compiling: #{compile_cmd.join(" ")}"
unless system(*compile_cmd)
  abort "FAIL: compilation failed"
end

# Run
puts "Running: #{out}"
unless system(out)
  abort "FAIL: smoke test binary exited with non-zero status"
end

puts "PASS"
