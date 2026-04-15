# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class DSLTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
  end

  def test_parses_service_level_definition
    load File.expand_path('../examples/services/checkout.rb', __dir__)

    definition = SloRulesEngine.definitions.fetch(0)
    assert_equal 'checkout-api', definition.service
    assert_equal 'payments-platform', definition.owner
    assert_equal ['production'], definition.environments
    assert_equal 'http-requests', definition.slis.fetch(0).uid
    assert_equal 'public-api', definition.slis.fetch(0).instances.fetch(0).uid
    assert_equal 'successful-requests', definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).uid
  end

  def test_parses_reliability_intent_fields
    load File.expand_path('../examples/services/checkout.rb', __dir__)

    definition = SloRulesEngine.definitions.fetch(0)
    sli = definition.slis.fetch(0)
    slo = sli.instances.fetch(0).slos.fetch(0)

    assert_equal 'server-side request boundary', sli.measurement_details.measurement_point
    assert_equal 'error budget exhausted', slo.miss_policy.trigger
    assert_equal ['bind provider queries', 'generate decision dashboard'], slo.observability_handoff.requests
  end
end
