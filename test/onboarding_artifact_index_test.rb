# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/slo_rules_engine'

class OnboardingArtifactIndexTest < Minitest::Test
  def test_build_ties_saved_onboarding_artifacts_into_one_index
    Dir.mktmpdir do |dir|
      discovery_dir = File.join(dir, 'discovery')
      handoff_dir = File.join(dir, 'handoff')
      draft_dir = File.join(dir, 'drafts')
      manifest_dir = File.join(dir, 'generated')
      [discovery_dir, handoff_dir, draft_dir, manifest_dir].each { |path| FileUtils.mkdir_p(path) }

      discovery_result = File.join(discovery_dir, 'checkout-prod.json')
      write_json(
        discovery_result,
        provider: 'datadog',
        scope: { label: 'checkout-prod', service: 'checkout-api' },
        signals: [{ kind: 'latency', metric: 'http.server.request.duration', user_visible: true }],
        findings: []
      )
      index_path = File.join(discovery_dir, 'index.json')
      write_json(
        index_path,
        provider: 'datadog',
        generated_at: '2026-05-13T09:00:00Z',
        total_scopes: 1,
        scopes: [
          {
            label: 'checkout-prod',
            scope: { label: 'checkout-prod', service: 'checkout-api' },
            status: 'ok',
            result_file: 'checkout-prod.json',
            signal_count: 1,
            finding_count: 0
          }
        ]
      )

      handoff_path = File.join(handoff_dir, 'checkout-prod.handoff.json')
      write_json(
        handoff_path,
        label: 'checkout-prod',
        provider: 'datadog',
        review: {
          status: 'reviewed',
          accepted_candidate_uids: ['request-latency'],
          rejected_candidate_uids: [],
          notes: ['Latency accepted.']
        }
      )
      draft_path = File.join(draft_dir, 'checkout-prod.rb')
      File.write(draft_path, "# reviewed draft\n")
      manifest_path = File.join(manifest_dir, 'checkout-api', 'datadog', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      write_json(manifest_path, service: 'checkout-api', provider: 'datadog', artifacts: {})
      report_path = File.join(manifest_dir, 'manifest-review', 'datadog.json')
      FileUtils.mkdir_p(File.dirname(report_path))
      write_json(report_path, valid: true)

      artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
        index_path,
        handoff_dir: handoff_dir,
        draft_dir: draft_dir,
        manifest_dir: manifest_dir,
        providers: ['datadog']
      )

      assert_equal 'datadog', artifact_index.fetch(:provider)
      assert_equal index_path, artifact_index.fetch(:artifact_index).fetch(:discovery_index)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:complete_scopes)
      assert_equal 0, artifact_index.fetch(:summary).fetch(:missing_artifact_count)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:reviewed_handoffs)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:draft_files)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:provider_manifest_files)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:manifest_review_reports)

      scope = artifact_index.fetch(:scopes).fetch(0)
      assert_equal 'complete', scope.fetch(:status)
      assert_equal 'checkout-prod', scope.fetch(:label)
      assert_equal discovery_result, scope.fetch(:discovery).fetch(:path)
      assert_equal true, scope.fetch(:discovery).fetch(:exists)
      assert_equal 'reviewed', scope.fetch(:handoff).fetch(:review_status)
      assert_equal 1, scope.fetch(:handoff).fetch(:accepted_candidate_count)
      assert_equal draft_path, scope.fetch(:draft).fetch(:path)
      assert_equal true, scope.fetch(:draft).fetch(:exists)

      provider = scope.fetch(:providers).fetch(0)
      assert_equal 'datadog', provider.fetch(:provider)
      assert_equal manifest_path, provider.fetch(:manifest).fetch(:path)
      assert_equal true, provider.fetch(:manifest).fetch(:exists)
      assert_equal report_path, provider.fetch(:manifest_review_report).fetch(:path)
      assert_equal true, provider.fetch(:manifest_review_report).fetch(:exists)
      assert_equal(
        "rules-ctl manifest-review --provider=datadog --manifest=#{manifest_path} --handoff-dir=#{handoff_dir} --report=#{report_path}",
        provider.fetch(:manifest_review_command)
      )
      assert_empty scope.fetch(:missing_artifacts)
    end
  end

  private

  def write_json(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end
end
