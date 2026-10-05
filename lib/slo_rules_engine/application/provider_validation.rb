# frozen_string_literal: true

require_relative '../validation'

module SloRulesEngine
  module Application
    module ProviderValidation
      module_function

      def validate(definitions, provider)
        core_validator = SloRulesEngine::CoreValidator.new
        errors = []
        warnings = []
        definitions.each do |definition|
          core_result = core_validator.validate(definition)
          provider_result = provider.validate(definition)
          errors.concat(core_result.errors.map(&:to_h))
          errors.concat(provider_result.errors.map(&:to_h))
          warnings.concat(core_result.warnings.map(&:to_h))
          warnings.concat(provider_result.warnings.map(&:to_h))
        end
        { valid: errors.empty?, errors: errors, warnings: warnings }
      end
    end
  end
end
