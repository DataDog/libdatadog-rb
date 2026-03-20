# frozen_string_literal: true

require_relative 'helpers'

namespace :vendor do
  desc 'Install artifacts into the vendor tree'
  task install: ['libdatadog:install']

  desc 'Remove the vendor tree for the current platform'
  task :clean do
    Libdatadog::Vendor.target.rmtree
  end

  namespace :clean do
    desc 'Remove the vendor tree for all platforms'
    task :all do
      Libdatadog::Vendor.libdatadog.rmtree
    end
  end
end
