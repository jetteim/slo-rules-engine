# frozen_string_literal: true

module SloRulesEngine
  ServiceLevelDefinition = Struct.new(
    :service,
    :owner,
    :description,
    :environments,
    :slis,
    :notification_routes,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.environments ||= ['production']
      self.slis ||= []
      self.notification_routes ||= []
    end
  end

  SLI = Struct.new(
    :uid,
    :title,
    :metric,
    :instances,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.instances ||= []
    end
  end

  MetricBinding = Struct.new(
    :name,
    :data_source,
    :type,
    :range,
    :selector,
    :query,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.selector ||= {}
    end
  end

  SLIInstance = Struct.new(
    :uid,
    :selector,
    :slos,
    :playbook_url,
    :dashboard_variables,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.selector ||= {}
      self.slos ||= []
      self.dashboard_variables ||= {}
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
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.calculation_basis ||= 'observations'
    end
  end

  NotificationRoute = Struct.new(
    :key,
    :source,
    :provider,
    :target,
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
