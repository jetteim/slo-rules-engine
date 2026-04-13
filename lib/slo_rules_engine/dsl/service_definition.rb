# frozen_string_literal: true

module SloRulesEngine
  module DSL
    class ServiceDefinition
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize
        @environments = ['production']
        @slis = []
        @notification_routes = []
        @line_references = {}
      end

      def service(value = nil)
        return @service if value.nil?

        record_line(:service)
        @service = value.to_s
      end

      def owner(value = nil)
        return @owner if value.nil?

        record_line(:owner)
        @owner = value.to_s
      end

      def description(value = nil)
        return @description if value.nil?

        record_line(:description)
        @description = value.to_s
      end

      def environments(*values)
        return @environments if values.empty?

        record_line(:environments)
        @environments = values.flatten.map(&:to_s)
      end

      def environment(value = nil)
        return @environments.first if value.nil?

        record_line(:environments)
        @environments = [value.to_s]
      end

      def notification_route(key:, source:, provider:, target:)
        line_reference = line_reference_from_caller
        @notification_routes << NotificationRoute.new(
          key: key.to_s,
          source: source.to_s,
          provider: provider.to_s,
          target: target.to_s,
          line_references: {
            key: line_reference,
            source: line_reference,
            provider: line_reference,
            target: line_reference
          }
        )
      end

      def sli(&block)
        @slis << SLIBuilder.evaluate(&block)
      end

      def to_model
        ServiceLevelDefinition.new(
          service: @service,
          owner: @owner,
          description: @description,
          environments: @environments,
          slis: @slis,
          notification_routes: @notification_routes,
          line_references: @line_references
        )
      end

      private

      def record_line(field)
        @line_references[field] = line_reference_from_caller
      end

      def line_reference_from_caller
        location = caller_locations.find { |caller_location| caller_location.path != __FILE__ }
        { file: location.path, line: location.lineno }
      end
    end

    class SLIBuilder
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize
        @instances = []
        @line_references = {}
      end

      def uid(value = nil)
        return @uid if value.nil?

        record_line(:uid)
        @uid = value.to_s
      end

      def title(value = nil)
        return @title if value.nil?

        record_line(:title)
        @title = value.to_s
      end

      def metric(value = nil, &block)
        if block
          @metric = MetricBuilder.evaluate(value, &block)
        elsif value
          @metric = MetricBinding.new(name: value.to_s)
        else
          @metric
        end
      end

      def instance(&block)
        @instances << SLIInstanceBuilder.evaluate(&block)
      end

      def to_model
        SLI.new(uid: @uid, title: @title, metric: @metric, instances: @instances, line_references: @line_references)
      end

      private

      def record_line(field)
        @line_references[field] = line_reference_from_caller
      end

      def line_reference_from_caller
        location = caller_locations.find { |caller_location| caller_location.path != __FILE__ }
        { file: location.path, line: location.lineno }
      end
    end

    class MetricBuilder
      def self.evaluate(name, &block)
        new(name).tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize(name)
        @name = name.to_s
        @selector = {}
        @provider_bindings = {}
        @line_references = {}
      end

      def data_source(value = nil)
        return @data_source if value.nil?

        record_line(:data_source)
        @data_source = value.to_s
      end

      def type(value = nil)
        return @type if value.nil?

        record_line(:type)
        @type = value.to_s
      end

      def range(value = nil)
        return @range if value.nil?

        record_line(:range)
        @range = value.to_s
      end

      def selector(value = nil)
        return @selector if value.nil?

        record_line(:selector)
        @selector = stringify_hash(value)
      end

      def query(value = nil)
        return @query if value.nil?

        record_line(:query)
        @query = value.to_s
      end

      def provider_binding(provider, &block)
        record_line(:provider_bindings)
        @provider_bindings[provider.to_s] = ProviderQueryBindingBuilder.evaluate(provider.to_s, &block)
      end

      def to_model
        MetricBinding.new(
          name: @name,
          data_source: @data_source,
          type: @type,
          range: @range,
          selector: @selector,
          query: @query,
          provider_bindings: @provider_bindings,
          line_references: @line_references
        )
      end

      private

      def record_line(field)
        @line_references[field] = line_reference_from_caller
      end

      def line_reference_from_caller
        location = caller_locations.find { |caller_location| caller_location.path != __FILE__ }
        { file: location.path, line: location.lineno }
      end

      def stringify_hash(value)
        value.each_with_object({}) { |(key, val), hash| hash[key.to_s] = val.to_s }
      end
    end

    class ProviderQueryBindingBuilder
      def self.evaluate(provider, &block)
        new(provider).tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize(provider)
        @provider = provider
        @selector = {}
        @line_references = {}
      end

      def metric(value = nil)
        return @metric if value.nil?

        record_line(:metric)
        @metric = value.to_s
      end

      def data_source(value = nil)
        return @data_source if value.nil?

        record_line(:data_source)
        @data_source = value.to_s
      end

      def type(value = nil)
        return @type if value.nil?

        record_line(:type)
        @type = value.to_s
      end

      def range(value = nil)
        return @range if value.nil?

        record_line(:range)
        @range = value.to_s
      end

      def selector(value = nil)
        return @selector if value.nil?

        record_line(:selector)
        @selector = stringify_hash(value)
      end

      def query(value = nil)
        return @query if value.nil?

        record_line(:query)
        @query = value.to_s
      end

      def to_model
        ProviderQueryBinding.new(
          provider: @provider,
          metric: @metric,
          data_source: @data_source,
          type: @type,
          range: @range,
          selector: @selector,
          query: @query,
          line_references: @line_references
        )
      end

      private

      def record_line(field)
        @line_references[field] = line_reference_from_caller
      end

      def line_reference_from_caller
        location = caller_locations.find { |caller_location| caller_location.path != __FILE__ }
        { file: location.path, line: location.lineno }
      end

      def stringify_hash(value)
        value.each_with_object({}) { |(key, val), hash| hash[key.to_s] = val.to_s }
      end
    end

    class SLIInstanceBuilder
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize
        @selector = {}
        @slos = []
        @dashboard_variables = {}
        @line_references = {}
      end

      def uid(value = nil)
        return @uid if value.nil?

        record_line(:uid)
        @uid = value.to_s
      end

      def selector(value = nil)
        return @selector if value.nil?

        record_line(:selector)
        @selector = stringify_hash(value)
      end

      def playbook_url(value = nil)
        return @playbook_url if value.nil?

        record_line(:playbook_url)
        @playbook_url = value.to_s
      end

      def dashboard_variables(value = nil)
        return @dashboard_variables if value.nil?

        record_line(:dashboard_variables)
        @dashboard_variables = stringify_hash(value)
      end

      def slo(&block)
        @slos << SLOBuilder.evaluate(&block)
      end

      def to_model
        SLIInstance.new(
          uid: @uid,
          selector: @selector,
          slos: @slos,
          playbook_url: @playbook_url,
          dashboard_variables: @dashboard_variables,
          line_references: @line_references
        )
      end

      private

      def record_line(field)
        @line_references[field] = line_reference_from_caller
      end

      def line_reference_from_caller
        location = caller_locations.find { |caller_location| caller_location.path != __FILE__ }
        { file: location.path, line: location.lineno }
      end

      def stringify_hash(value)
        value.each_with_object({}) { |(key, val), hash| hash[key.to_s] = val.to_s }
      end
    end

    class SLOBuilder
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize
        @calculation_basis = 'observations'
        @line_references = {}
      end

      def uid(value = nil)
        return @uid if value.nil?

        record_line(:uid)
        @uid = value.to_s
      end

      def objective(value = nil)
        return @objective if value.nil?

        record_line(:objective)
        @objective = value.to_f
      end

      def success_selector(value = nil)
        return @success_selector if value.nil?

        record_line(:success_selector)
        @success_selector = stringify_hash(value)
      end

      def success_threshold(operator, value)
        record_line(:success_threshold)
        @success_threshold = { operator: operator.to_s, value: value.to_s }
      end

      def calculation_basis(value = nil)
        return @calculation_basis if value.nil?

        record_line(:calculation_basis)
        @calculation_basis = value.to_s
      end

      def documentation(value = nil)
        return @documentation if value.nil?

        record_line(:documentation)
        @documentation = value.to_s
      end

      def alert_route_key(value = nil)
        return @alert_route_key if value.nil?

        record_line(:alert_route_key)
        @alert_route_key = value.to_s
      end

      def dashboard_path(value = nil)
        return @dashboard_path if value.nil?

        record_line(:dashboard_path)
        @dashboard_path = value.to_s
      end

      def to_model
        SLO.new(
          uid: @uid,
          objective: @objective,
          success_selector: @success_selector,
          success_threshold: @success_threshold,
          calculation_basis: @calculation_basis,
          documentation: @documentation,
          alert_route_key: @alert_route_key,
          dashboard_path: @dashboard_path,
          line_references: @line_references
        )
      end

      private

      def record_line(field)
        @line_references[field] = line_reference_from_caller
      end

      def line_reference_from_caller
        location = caller_locations.find { |caller_location| caller_location.path != __FILE__ }
        { file: location.path, line: location.lineno }
      end

      def stringify_hash(value)
        value.each_with_object({}) { |(key, val), hash| hash[key.to_s] = val.to_s }
      end
    end
  end
end
