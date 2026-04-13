# frozen_string_literal: true

require_relative 'slo_rules_engine'

module SRE
  def self.define(&block)
    SloRulesEngine.register_definition(SloRulesEngine::DSL::ServiceDefinition.evaluate(&block))
  end
end
