# frozen_string_literal: true

require "rspec/core/rake_task"
require "standard/rake" unless RUBY_VERSION < "2.6"

RSpec::Core::RakeTask.new(:spec)

task default: [
  :spec,
  (:standard unless RUBY_VERSION < "2.6")
].compact
