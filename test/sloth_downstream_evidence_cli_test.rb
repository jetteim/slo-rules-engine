# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative 'support/cli_helpers'

class SlothDownstreamEvidenceCliTest < Minitest::Test
  include CliHelpers

  GENERATED_FIXTURE = File.expand_path('fixtures/sloth/generated-rules.yaml', __dir__)
  REVIEWED_AT = '2026-08-04T12:00:00Z'

  def test_capture_writes_the_reviewed_evidence_printed_to_stdout
    with_sources do |sources|
      output_path = File.join(sources.fetch(:dir), 'sloth-evidence.json')
      stdout, stderr, status = rules_ctl(
        'sloth-evidence',
        'capture',
        "--manifest=#{sources.fetch(:manifest)}",
        "--input=#{sources.fetch(:input)}",
        "--generated-rules=#{sources.fetch(:generated)}",
        '--reviewer=platform-reviewer@example.test',
        "--reviewed-at=#{REVIEWED_AT}",
        "--output=#{output_path}"
      )

      assert status.success?, stderr
      assert_empty stderr
      payload = JSON.parse(stdout)
      assert_equal payload, JSON.parse(File.read(output_path))
      assert_equal 'slo-rules-engine/sloth-downstream-evidence/v1', payload.fetch('schema_version')
      assert_equal true, payload.dig('summary', 'complete')
      assert_equal 1, payload.fetch('slos').length
    end
  end

  def test_status_reports_fresh_then_returns_one_with_stale_source_evidence
    with_sources do |sources|
      evidence_path = capture_evidence(sources)
      stdout, stderr, status = rules_ctl('sloth-evidence', 'status', evidence_path)

      assert status.success?, stderr
      assert_empty stderr
      fresh = JSON.parse(stdout)
      assert_equal 'fresh', fresh.fetch('status')
      assert_equal true, fresh.fetch('fresh')
      assert fresh.fetch('source_checks').all? { |check| check.fetch('fresh') }

      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: false)
      generated.fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'vector(0)'
      File.write(sources.fetch(:generated), YAML.dump(generated))
      stdout, stderr, status = rules_ctl('sloth-evidence', 'status', evidence_path)

      refute status.success?
      assert_equal 1, status.exitstatus
      assert_empty stderr
      stale = JSON.parse(stdout)
      assert_equal 'stale', stale.fetch('status')
      assert_equal false, stale.fetch('fresh')
      assert_includes stale.fetch('findings').map { |finding| finding.fetch('code') },
                      'stale_generated_rules'
    end
  end

  def test_capture_refuses_incomplete_generated_rules_without_writing_output
    with_sources do |sources|
      generated = YAML.safe_load(File.read(sources.fetch(:generated)), aliases: false)
      generated.fetch('groups').fetch(1).fetch('rules').reject! do |rule|
        rule['record'] == 'slo:period_error_budget_remaining:ratio'
      end
      File.write(sources.fetch(:generated), YAML.dump(generated))
      output_path = File.join(sources.fetch(:dir), 'invalid-evidence.json')
      stdout, stderr, status = rules_ctl(
        'sloth-evidence',
        'capture',
        "--manifest=#{sources.fetch(:manifest)}",
        "--input=#{sources.fetch(:input)}",
        "--generated-rules=#{sources.fetch(:generated)}",
        '--reviewer=platform-reviewer@example.test',
        "--reviewed-at=#{REVIEWED_AT}",
        "--output=#{output_path}"
      )

      refute status.success?
      assert_equal 1, status.exitstatus
      assert_empty stderr
      refute File.exist?(output_path)
      payload = JSON.parse(stdout)
      assert_equal false, payload.fetch('valid')
      assert_equal 'invalid_sloth_downstream_evidence', payload.dig('error', 'code')
      assert_includes payload.fetch('findings').map { |finding| finding.fetch('code') },
                      'missing_generated_recording_rule'
    end
  end

  private

  def with_sources
    Dir.mktmpdir do |dir|
      manifest = reviewed_manifest('sloth')
      manifest_path = File.join(dir, 'manifest.json')
      input_path = File.join(dir, 'sloth.yaml')
      generated_path = File.join(dir, 'generated-rules.yaml')
      File.write(manifest_path, JSON.pretty_generate(manifest))
      File.write(input_path, YAML.dump(manifest.fetch('artifacts').fetch('sloth_specs').fetch(0)))
      FileUtils.cp(GENERATED_FIXTURE, generated_path)
      yield(dir: dir, manifest: manifest_path, input: input_path, generated: generated_path)
    end
  end

  def capture_evidence(sources)
    output_path = File.join(sources.fetch(:dir), 'sloth-evidence.json')
    _stdout, stderr, status = rules_ctl(
      'sloth-evidence',
      'capture',
      "--manifest=#{sources.fetch(:manifest)}",
      "--input=#{sources.fetch(:input)}",
      "--generated-rules=#{sources.fetch(:generated)}",
      '--reviewer=platform-reviewer@example.test',
      "--reviewed-at=#{REVIEWED_AT}",
      "--output=#{output_path}"
    )
    assert status.success?, stderr
    output_path
  end
end
