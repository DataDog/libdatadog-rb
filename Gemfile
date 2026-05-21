# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake", ">= 12.0", "< 14"
gem "rspec", "~> 3.10"
gem "standard", "~> 1.7", ">= 1.7.2" unless RUBY_VERSION < "2.6"
gem "http", "~> 5.0"
# Force source build on old-glibc environments. The precompiled
# ffi-1.17.3-x86_64-linux-gnu gem requires GLIBC_2.27, but the CentOS 7
# build image intentionally provides GLIBC_2.17.
gem "ffi", force_ruby_platform: true
gem "pry"
gem "pry-byebug" unless RUBY_VERSION > "3.1"
gem "rubygems-await" unless RUBY_VERSION < "3.1"
gem "irb"
