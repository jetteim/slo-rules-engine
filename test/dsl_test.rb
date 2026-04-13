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
end
