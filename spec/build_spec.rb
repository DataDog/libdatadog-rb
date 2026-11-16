# frozen_string_literal: true

require "rake"
load File.expand_path("../tasks/build.rake", __dir__)

RSpec.describe BuildFromSource::Builder do
  describe ".cargo_install_cmd" do
    it "builds the pinned native revision with locked dependencies" do
      revision = "a" * 40
      stub_const("Libdatadog::LIB_REVISION", revision)

      command = described_class.cargo_install_cmd
      expect(command).to include("--locked", "--rev", revision)
      expect(command).not_to include("--tag", "--path")
    end

    it "uses the release tag after the revision pin is cleared" do
      stub_const("Libdatadog::LIB_REVISION", nil)
      stub_const("Libdatadog::LIB_VERSION", "1.2.3")

      command = described_class.cargo_install_cmd
      expect(command).to include("--tag", "v1.2.3")
      expect(command).not_to include("--rev")
    end

    it "preserves the explicit local source override" do
      command = described_class.cargo_install_cmd(source: ".", features: "ffe")

      expect(command).to include("--path", File.expand_path("../builder", __dir__))
      expect(command).to include("--no-default-features", "--features", "ffe")
      expect(command).not_to include("--git", "--rev", "--tag")
    end
  end
end
