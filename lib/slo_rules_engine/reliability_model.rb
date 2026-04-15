# frozen_string_literal: true

module SloRulesEngine
  module ReliabilityModel
    class ReportBuilder
      def build(definitions)
        slis = definitions.flat_map(&:slis)
        instances = slis.flat_map(&:instances)
        slos = instances.flat_map(&:slos)

        {
          service_count: definitions.size,
          sli_count: slis.size,
          instance_count: instances.size,
          slo_count: slos.size,
          calculation_basis_distribution: distribution(slos.map(&:calculation_basis)),
          objectives: slos.map(&:objective).compact.sort,
          observability_handoff_requests: slos.flat_map { |slo| slo.observability_handoff&.requests || [] }.uniq.sort,
          private_identifiers: []
        }
      end

      private

      def distribution(values)
        values.each_with_object(Hash.new(0)) { |value, counts| counts[value] += 1 }
      end
    end
  end
end
