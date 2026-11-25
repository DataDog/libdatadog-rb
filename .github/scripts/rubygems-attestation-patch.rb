# frozen_string_literal: true

# Attach a Sigstore attestation to `gem push` uploads to rubygems.org.
#
# Vendored from rubygems/release-gem@6317d8d1f7e28c24d28f6eff169ea854948bd9f7
# (rubygems-attestation-patch.rb, MIT). Intentional differences from upstream:
#   * invoke the explicitly-installed `sigstore-cli` binary instead of
#     `gem exec sigstore-cli:<version>`, so the signing tool is a declared,
#     pinned dependency rather than an implicit install at push time;
#   * no silent "retry without attestation" fallback -- a signing failure must
#     fail the push loudly.

return if RUBY_ENGINE == "jruby"
return unless defined?(Gem)

require "rubygems/commands/push_command"

push_command_with_attestation = Module.new do
  def send_push_request(name, args)
    return super if Array(options[:attestations]).any? || @host != "https://rubygems.org"

    attestation = attest!(name)
    rubygems_api_request(*args, scope: get_push_scope) do |request|
      request.set_form(
        [
          ["gem", Gem.read_binary(name), {filename: name, content_type: "application/octet-stream"}],
          ["attestations", "[#{Gem.read_binary(attestation)}]", {content_type: "application/json"}]
        ],
        "multipart/form-data"
      )
      request.add_field "Authorization", api_key
    end
  end

  def attest!(name)
    require "open3"
    bundle = "#{name}.sigstore.json"
    output, status = Open3.capture2e("sigstore-cli", "sign", name, "--bundle", bundle)
    raise Gem::Exception, "Failed to sign #{name} with sigstore-cli:\n\n#{output}" unless status.success?

    bundle
  end
end

Gem::Commands::PushCommand.prepend(push_command_with_attestation)
