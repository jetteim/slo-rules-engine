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

  def test_validation_errors_include_line_reference
    definition = SloRulesEngine.definitions.fetch(0)
    definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).objective = 1.0

    result = SloRulesEngine::CoreValidator.new.validate(definition)
    objective_error = result.errors.find { |error| error.path.end_with?('.objective') }

    refute_nil objective_error.line_reference
    assert_includes objective_error.line_reference[:file], 'examples/services/checkout.rb'
    assert_kind_of Integer, objective_error.line_reference[:line]
  end

  def test_rejects_unknown_alert_route_key
    definition = SloRulesEngine.definitions.fetch(0)
    definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).alert_route_key = 'missing-route'

    result = SloRulesEngine::CoreValidator.new.validate(definition)

    refute result.valid?
    assert result.errors.any? { |error| error.path.end_with?('.alert_route_key') && error.message.include?('unknown') }
  end

  def test_warns_when_sli_lacks_user_visible_rationale
    definition = SloRulesEngine.definitions.fetch(0)
    definition.slis.fetch(0).user_visible_rationale = nil

    result = SloRulesEngine::CoreValidator.new.validate(definition)

    assert result.warnings.any? { |warning| warning.path.end_with?('.user_visible_rationale') }
  end

  def test_errors_when_slo_lacks_miss_policy
    definition = SloRulesEngine.definitions.fetch(0)
    definition.slis.fetch(0).instances.fetch(0).slos.fetch(0).miss_policy = nil

    result = SloRulesEngine::CoreValidator.new.validate(definition)

    refute result.valid?
    assert result.errors.any? { |error| error.path.end_with?('.miss_policy') }
  end
end
