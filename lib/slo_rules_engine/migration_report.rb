# frozen_string_literal: true

module SloRulesEngine
  MigrationReportResult = Struct.new(
    :findings,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.findings ||= []
    end

    def valid?
      findings.empty?
    end

    def to_h
      {
        valid: valid?,
        findings: findings
      }
    end
  end

  module MigrationReport
    DEFAULT_PATTERNS = [
      {
        code: 'external_metadata_dependency',
        pattern: /project_metadata|metadata_app_name|metadata_portfolio_name/
      },
      {
        code: 'provider_specific_dsl',
        pattern: /datadog_|thanos_|grafana_|alertmanager_/
      },
      {
        code: 'direct_delivery_config',
        pattern: /pagerduty|opsgenie|msteams_webhook|email\s+/
      }
    ].freeze

    module_function

    def scan_files(paths, extra_patterns: [])
      patterns = DEFAULT_PATTERNS + Array(extra_patterns)
      findings = paths.flat_map { |path| scan_file(path, patterns) }
      MigrationReportResult.new(findings: findings)
    end

    def scan_file(path, patterns)
      lines = File.readlines(path)
      patterns.each_with_object([]) do |rule, findings|
        lines.each_with_index do |line, index|
          next unless line.match?(rule.fetch(:pattern))

          findings << {
            code: rule.fetch(:code),
            file: path,
            line: index + 1,
            message: migration_message(rule.fetch(:code))
          }
          break
        end
      end
    end

    def migration_message(code)
      case code
      when 'external_metadata_dependency'
        'Move ownership and routing metadata into neutral service intent or generated integration configuration.'
      when 'provider_specific_dsl'
        'Move backend-specific query details into provider bindings while keeping SLI intent neutral.'
      when 'direct_delivery_config'
        'Move direct alert delivery configuration into notification route intent.'
      else
        'Review caller-supplied migration coupling.'
      end
    end
  end
end
