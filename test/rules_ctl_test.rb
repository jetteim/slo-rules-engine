# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'tempfile'
load File.expand_path('../bin/rules-ctl', __dir__)

class RulesCtlTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def setup
    SloRulesEngine.clear_definitions
  end

  def test_apply_renders_invalid_provider_payload_error
    load "#{ROOT}/examples/services/checkout.rb"
    definition = SloRulesEngine.definitions.fetch(0)
    manifest = SloRulesEngine.default_provider_registry.fetch('datadog')
      .generate(definition)
      .to_h
      .merge(service: definition.service)
    result = SloRulesEngine::ValidationResult.new
    result.error('query', 'contains unresolved SLO reference')
    payload_error = SloRulesEngine::Datadog::PayloadError.new(
      target: 'datadog.monitor',
      payload: { query: '__SLO_REF__[missing]' },
      result: result
    )
    fake_applier = Object.new
    fake_applier.define_singleton_method(:apply) { |_reviewed_manifest| raise payload_error }

    Tempfile.create(['reviewed-manifest', '.json']) do |file|
      file.write(JSON.generate(manifest))
      file.flush

      stdout, _stderr = capture_io do
        exit_error = assert_raises(SystemExit) do
          SloRulesEngine::Appliers::Datadog.stub(:new, fake_applier) do
            RulesCtl.apply(['--provider=datadog', '--confirm', "--manifest=#{file.path}"])
          end
        end
        assert_equal 1, exit_error.status
      end

      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'datadog', payload.fetch('provider')
      assert_equal 'live', payload.fetch('mode')
      assert_equal 'invalid_provider_payload', payload.fetch('error').fetch('code')
      assert_equal 'query', payload.fetch('errors').fetch(0).fetch('path')
    end
  end
end
