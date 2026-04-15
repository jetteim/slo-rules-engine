# frozen_string_literal: true

module SloRulesEngine
  ServiceLevelDefinition = Struct.new(
    :service,
    :owner,
    :description,
    :environments,
    :slis,
    :notification_routes,
    :line_references,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.environments ||= ['production']
      self.slis ||= []
      self.notification_routes ||= []
      self.line_references ||= {}
    end
  end

  SLI = Struct.new(
    :uid,
    :title,
    :metric,
    :instances,
    :line_references,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.instances ||= []
      self.line_references ||= {}
    end
  end

  MetricBinding = Struct.new(
    :name,
    :data_source,
    :type,
    :range,
    :selector,
    :query,
    :provider_bindings,
    :line_references,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.selector ||= {}
      self.provider_bindings ||= {}
      self.line_references ||= {}
    end

    def binding_for(provider)
      provider_bindings.fetch(provider.to_s)
    end
  end

  ProviderQueryBinding = Struct.new(
    :provider,
    :metric,
    :data_source,
    :type,
    :range,
    :selector,
    :query,
    :line_references,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.selector ||= {}
      self.line_references ||= {}
    end
  end

  SLIInstance = Struct.new(
    :uid,
    :selector,
    :slos,
    :playbook_url,
    :dashboard_variables,
    :line_references,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.selector ||= {}
      self.slos ||= []
      self.dashboard_variables ||= {}
      self.line_references ||= {}
    end
  end

  SLO = Struct.new(
    :uid,
    :objective,
    :success_selector,
    :success_threshold,
    :calculation_basis,
    :documentation,
    :alert_route_key,
    :dashboard_path,
    :line_references,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.calculation_basis ||= 'observations'
      self.line_references ||= {}
    end
  end

  MeasurementDetails = Struct.new(
    :source,
    :measurement_point,
    :probe_interval,
    :probe_timeout,
    :threshold_requirements,
    :excluded_traffic,
    :caveats,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.threshold_requirements ||= []
      self.excluded_traffic ||= []
      self.caveats ||= []
    end

    def to_h
      {
        source: source,
        measurement_point: measurement_point,
        probe_interval: probe_interval,
        probe_timeout: probe_timeout,
        threshold_requirements: threshold_requirements,
        excluded_traffic: excluded_traffic,
        caveats: caveats
      }
    end
  end

  MissPolicy = Struct.new(
    :trigger,
    :response,
    :authority,
    :exit_condition,
    :review_cadence,
    keyword_init: true
  ) do
    def to_h
      {
        trigger: trigger,
        response: response,
        authority: authority,
        exit_condition: exit_condition,
        review_cadence: review_cadence
      }
    end
  end

  NotificationRoute = Struct.new(
    :key,
    :source,
    :provider,
    :target,
    :line_references,
    keyword_init: true
  )

  GeneratedManifest = Struct.new(
    :provider,
    :capabilities,
    :artifacts,
    keyword_init: true
  ) do
    def to_h
      {
        provider: provider,
        capabilities: capabilities,
        artifacts: artifacts
      }
    end
  end
end
