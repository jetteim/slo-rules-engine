# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/sre'

class ValidationTest < Minitest::Test
  def setup
    SloRulesEngine.clear_definitions
    load File.expand_path('../examples/services/checkout.rb', __dir__)
  end

  def test_validates_sample_definition
    result = SloRulesEngine::CoreValidator.new.validate(SloRulesEngine.definitions.fetch(0))

    assert result.valid?, result.to_h.inspect
  end

  def test_rejects_invalid_objective
    definition = SloRulesEngine.definitions.fetch(0)
    definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).objective = 1.0

    result = SloRulesEngine::CoreValidator.new.validate(definition)

    refute result.valid?
    assert result.errors.any? { |error| error.path.end_with?('.objective') }
  end
end
