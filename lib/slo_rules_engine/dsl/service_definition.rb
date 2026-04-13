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
      end

      def service(value = nil)
        return @service if value.nil?

        @service = value.to_s
      end

      def owner(value = nil)
        return @owner if value.nil?

        @owner = value.to_s
      end

      def description(value = nil)
        return @description if value.nil?

        @description = value.to_s
      end

      def environments(*values)
        return @environments if values.empty?

        @environments = values.flatten.map(&:to_s)
      end

      def environment(value = nil)
        return @environments.first if value.nil?

        @environments = [value.to_s]
      end

      def notification_route(key:, source:, provider:, target:)
        @notification_routes << NotificationRoute.new(
          key: key.to_s,
          source: source.to_s,
          provider: provider.to_s,
          target: target.to_s
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
          notification_routes: @notification_routes
        )
      end
    end

    class SLIBuilder
      def self.evaluate(&block)
        new.tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize
        @instances = []
      end

      def uid(value = nil)
        return @uid if value.nil?

        @uid = value.to_s
      end

      def title(value = nil)
        return @title if value.nil?

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
        SLI.new(uid: @uid, title: @title, metric: @metric, instances: @instances)
      end
    end

    class MetricBuilder
      def self.evaluate(name, &block)
        new(name).tap { |builder| builder.instance_eval(&block) }.to_model
      end

      def initialize(name)
        @name = name.to_s
        @selector = {}
      end

      def data_source(value = nil)
        return @data_source if value.nil?

        @data_source = value.to_s
      end

      def type(value = nil)
        return @type if value.nil?

        @type = value.to_s
      end

      def range(value = nil)
        return @range if value.nil?

        @range = value.to_s
      end

      def selector(value = nil)
        return @selector if value.nil?

        @selector = stringify_hash(value)
      end

      def query(value = nil)
        return @query if value.nil?

        @query = value.to_s
      end

      def to_model
        MetricBinding.new(
          name: @name,
          data_source: @data_source,
          type: @type,
          range: @range,
          selector: @selector,
          query: @query
        )
      end

      private

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
      end

      def uid(value = nil)
        return @uid if value.nil?

        @uid = value.to_s
      end

      def selector(value = nil)
        return @selector if value.nil?

        @selector = stringify_hash(value)
      end

      def playbook_url(value = nil)
        return @playbook_url if value.nil?

        @playbook_url = value.to_s
      end

      def dashboard_variables(value = nil)
        return @dashboard_variables if value.nil?

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
          dashboard_variables: @dashboard_variables
        )
      end

      private

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
      end

      def uid(value = nil)
        return @uid if value.nil?

        @uid = value.to_s
      end

      def objective(value = nil)
        return @objective if value.nil?

        @objective = value.to_f
      end

      def success_selector(value = nil)
        return @success_selector if value.nil?

        @success_selector = stringify_hash(value)
      end

      def success_threshold(operator, value)
        @success_threshold = { operator: operator.to_s, value: value.to_s }
      end

      def calculation_basis(value = nil)
        return @calculation_basis if value.nil?

        @calculation_basis = value.to_s
      end

      def documentation(value = nil)
        return @documentation if value.nil?

        @documentation = value.to_s
      end

      def alert_route_key(value = nil)
        return @alert_route_key if value.nil?

        @alert_route_key = value.to_s
      end

      def dashboard_path(value = nil)
        return @dashboard_path if value.nil?

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
          dashboard_path: @dashboard_path
        )
      end

      private

      def stringify_hash(value)
        value.each_with_object({}) { |(key, val), hash| hash[key.to_s] = val.to_s }
      end
    end
  end
end
