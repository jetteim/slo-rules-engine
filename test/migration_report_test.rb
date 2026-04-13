# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../lib/slo_rules_engine'

class MigrationReportTest < Minitest::Test
  def test_reports_legacy_coupling_without_private_rule_names
    Tempfile.create(['legacy-sld', '.rb']) do |file|
      file.write(<<~RUBY)
        SRE.define do
          project_metadata_app_name 'checkout'
          datadog_trace_slo
          pagerduty service: 'checkout'
        end
      RUBY
      file.flush

      report = SloRulesEngine::MigrationReport.scan_files([file.path])

      refute report.valid?
      assert_equal %w[external_metadata_dependency provider_specific_dsl direct_delivery_config], report.findings.map { |finding| finding[:code] }
    end
  end

  def test_accepts_extra_patterns_from_caller
    Tempfile.create(['legacy-sld', '.rb']) do |file|
      file.write("custom_internal_call 'checkout'\n")
      file.flush

      report = SloRulesEngine::MigrationReport.scan_files(
        [file.path],
        extra_patterns: [{ code: 'caller_supplied_coupling', pattern: /custom_internal_call/ }]
      )

      refute report.valid?
      assert_equal 'caller_supplied_coupling', report.findings.fetch(0)[:code]
    end
  end
end
