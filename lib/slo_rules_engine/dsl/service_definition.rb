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

      def user_visible_rationale(value = nil)
        return @user_visible_rationale if value.nil?

        record_line(:user_visible_rationale)
        @user_visible_rationale = value.to_s
      end

      def measurement_details(&block)
        record_line(:measurement_details)
        @measurement_details = MeasurementDetailsBuilder.evaluate(&block)
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
        SLI.new(
          uid: @uid,
          title: @title,
          metric: @metric,
          instances: @instances,
          user_visible_rationale: @user_visible_rationale,
          measurement_details: @measurement_details,
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

      def miss_policy(&block)
        record_line(:miss_policy)
        @miss_policy = MissPolicyBuilder.evaluate(&block)
      end

      def reality_check_notes(*values)
        record_line(:reality_check_notes)
        @reality_check_notes = values.flatten.map(&:to_s)
      end

      def observability_handoff(*requests)
        record_line(:observability_handoff)
        @observability_handoff = ObservabilityHandoff.new(requests: requests.flatten.map(&:to_s))
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
          miss_policy: @miss_policy,
          reality_check_notes: @reality_check_notes,
          observability_handoff: @observability_handoff,
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

    class MeasurementDetailsBuilder
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def source(value = nil)
        return @source if value.nil?

        @source = value.to_s
      end

      def measurement_point(value = nil)
        return @measurement_point if value.nil?

        @measurement_point = value.to_s
      end

      def probe_interval(value = nil)
        return @probe_interval if value.nil?

        @probe_interval = value.to_s
      end

      def probe_timeout(value = nil)
        return @probe_timeout if value.nil?

        @probe_timeout = value.to_s
      end

      def threshold_requirements(*values)
        @threshold_requirements = values.flatten.map(&:to_s)
      end

      def excluded_traffic(*values)
        @excluded_traffic = values.flatten.map(&:to_s)
      end

      def caveats(*values)
        @caveats = values.flatten.map(&:to_s)
      end

      def to_model
        MeasurementDetails.new(
          source: @source,
          measurement_point: @measurement_point,
          probe_interval: @probe_interval,
          probe_timeout: @probe_timeout,
          threshold_requirements: @threshold_requirements,
          excluded_traffic: @excluded_traffic,
          caveats: @caveats
        )
      end
    end

    class MissPolicyBuilder
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def trigger(value = nil)
        return @trigger if value.nil?

        @trigger = value.to_s
      end

      def response(value = nil)
        return @response if value.nil?

        @response = value.to_s
      end

      def authority(value = nil)
        return @authority if value.nil?

        @authority = value.to_s
      end

      def exit_condition(value = nil)
        return @exit_condition if value.nil?

        @exit_condition = value.to_s
      end

      def review_cadence(value = nil)
        return @review_cadence if value.nil?

        @review_cadence = value.to_s
      end

      def to_model
        MissPolicy.new(
          trigger: @trigger,
          response: @response,
          authority: @authority,
          exit_condition: @exit_condition,
          review_cadence: @review_cadence
        )
      end
    end
  end
end
