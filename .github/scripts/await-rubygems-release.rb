# frozen_string_literal: true

require "net/http"
require "rubygems/package"

abort "Usage: #{$PROGRAM_NAME} GEM_FILE..." if ARGV.empty?

# Check the public endpoints used by Bundler and RubyGems without loading
# Bundler or relying on either client's internal index API.
def checks_for(spec)
  version = spec.platform == Gem::Platform::RUBY ? spec.version.to_s : "#{spec.version}-#{spec.platform}"
  {
    "https://index.rubygems.org/info/#{spec.name}" => version,
    "https://rubygems.org/quick/Marshal.4.8/#{spec.full_name}.gemspec.rz" => nil,
    "https://rubygems.org/gems/#{spec.full_name}.gem" => nil
  }
end

def fetch(url, method)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10, max_retries: 0) do |http|
    http.public_send(method, uri.request_uri)
  end
rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
  warn "#{url}: #{e.class}: #{e.message}"
  nil
end

pending = ARGV.flat_map { |path| checks_for(Gem::Package.new(path).spec).to_a }.uniq

$stdout.sync = true
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 300
loop do
  responses = {}
  pending.reject! do |url, version|
    next false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    response = responses.fetch(url) { responses[url] = fetch(url, version ? :get : :head) }
    next false unless response.is_a?(Net::HTTPSuccess)
    next false if version && !response.body.each_line.any? { |line| line.start_with?("#{version} ") }

    puts "Found #{[url, version].compact.join(" ")}"
    true
  end
  break if pending.empty?

  remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  if remaining <= 0
    pending.each { |url, version| warn "Missing #{[url, version].compact.join(" ")}" }
    abort "Timed out waiting for the RubyGems release to propagate"
  end
  sleep [5, remaining].min
end
