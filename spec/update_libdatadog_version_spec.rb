# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "upstream version updates" do
  let(:repository) { File.expand_path("..", __dir__) }
  let(:script) { File.join(@directory, ".github/scripts/update-libdatadog-version") }
  let(:version_file) { File.join(@directory, "lib/libdatadog/version.rb") }
  let(:output_file) { File.join(@directory, "output") }
  let(:original) do
    File.read(File.join(repository, "lib/libdatadog/version.rb"))
      .sub(/^  LIB_VERSION = ".*"/, '  LIB_VERSION = "46.0.0"')
      .sub(/^  GEM_MAJOR_VERSION = ".*"/, '  GEM_MAJOR_VERSION = "2"')
      .sub(/^  GEM_MINOR_VERSION = ".*"/, '  GEM_MINOR_VERSION = "3"')
      .sub(/^  GEM_PRERELEASE_VERSION = ".*"/, '  GEM_PRERELEASE_VERSION = ""')
  end

  around do |example|
    Dir.mktmpdir("libdatadog-version") do |directory|
      @directory = directory
      example.run
    end
  end

  before do
    FileUtils.mkdir_p(File.dirname(script))
    FileUtils.mkdir_p(File.dirname(version_file))
    FileUtils.cp(File.join(repository, ".github/scripts/update-libdatadog-version"), script)
    File.write(version_file, original)
    File.write(output_file, "")
  end

  def update(version)
    Open3.capture2e(
      {"GITHUB_OUTPUT" => output_file, "RUBYOPT" => nil, "RUBYGEMS_GEMDEPS" => nil},
      "bash", script, version
    )
  end

  ["46.0.1", "46.1.0", "47.0.0"].each do |version|
    it "starts at #{version}.0.0 when advancing from 46.0.0.2.3" do
      output, status = update(version)

      expect(status.success?).to be(true), output
      namespace = Module.new
      namespace.module_eval(File.read(version_file), version_file)
      expect(namespace.const_get(:Libdatadog)::VERSION).to eq("#{version}.0.0")
      expect(File.read(output_file)).to be_empty
    end
  end

  ["46.0.0", "45.0.1"].each do |version|
    it "preserves the gem revisions for a replayed or older #{version} event" do
      output, status = update(version)

      expect(status.success?).to be(true), output
      expect(File.read(version_file)).to eq(original)
      expect(File.read(output_file)).to eq("skip=true\n")
    end
  end

  it "rejects an invalid version without resetting the gem revisions" do
    _, status = update("invalid")

    expect(status.success?).to be(false)
    expect(File.read(version_file)).to eq(original)
  end
end
