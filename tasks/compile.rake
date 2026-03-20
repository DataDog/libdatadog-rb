# frozen_string_literal: true

require_relative 'helpers'

desc 'Build libdatadog from Rust source and populate the vendor tree for the current platform'
task compile: ['libdatadog:install'] do
  puts
  puts '=' * 72
  puts 'Done!'
  puts
  puts 'To use in dd-trace-rb, add to its Gemfile:'
  puts "  gem 'libdatadog', path: '#{Libdatadog::Gem.root}'"
  puts 'Then:  cd <dd-trace-rb> && bundle exec rake compile'
  puts '=' * 72
end

namespace :compile do
  desc 'Remove intermediate build artifacts (source cache, cargo target); keep vendor tree'
  task clean: ['libdatadog:clean']

  desc 'Remove all generated files: source cache, cargo build artifacts, and vendor tree'
  task clobber: ['compile:clean', 'vendor:clean']
end
