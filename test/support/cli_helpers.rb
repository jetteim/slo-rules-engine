# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'

module CliHelpers
  ROOT = File.expand_path('../..', __dir__)

  def rules_ctl(*args, env: {})
    Open3.capture3(env, 'ruby', File.join(ROOT, 'bin', 'rules-ctl'), *args)
  end

  def generate_manifest(provider, definition: File.join(ROOT, 'examples/services/checkout.rb'))
    stdout, stderr, status = rules_ctl('generate', "--provider=#{provider}", definition)
    assert status.success?, stderr

    JSON.parse(stdout).fetch(0)
  end

  def reviewed_manifest(provider = 'datadog')
    with_review_provenance(generate_manifest(provider))
  end

  def with_review_provenance(manifest)
    manifest.merge(
      'review_provenance' => {
        'label' => 'checkout-prod',
        'provider' => 'datadog',
        'accepted_candidate_uids' => ['request-latency'],
        'notes' => ['Latency accepted.']
      }
    )
  end

  def with_temp_json(prefix, payload)
    Tempfile.create([prefix, '.json']) do |file|
      file.write(JSON.pretty_generate(payload))
      file.flush
      yield file
    end
  end
end
