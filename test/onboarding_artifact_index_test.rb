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
      manifest = {
        service: 'checkout-api',
        provider: 'datadog',
        review_provenance: {
          label: 'checkout-prod',
          provider: 'datadog',
          accepted_candidate_uids: ['request-latency'],
          rejected_candidate_uids: [],
          notes: ['Latency accepted.']
        },
        artifacts: {}
      }
      write_json(manifest_path, manifest)
      report_path = File.join(manifest_dir, 'manifest-review', 'datadog.json')
      FileUtils.mkdir_p(File.dirname(report_path))
      write_json(
        report_path,
        SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
          [manifest],
          provider: 'datadog',
          handoff_dir: handoff_dir
        )
      )

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
      assert_equal true, provider.fetch(:manifest_review_report).fetch(:fresh)
      assert_equal(
        "rules-ctl manifest-review --provider=datadog --manifest=#{manifest_path} --handoff-dir=#{handoff_dir} --report=#{report_path}",
        provider.fetch(:manifest_review_command)
      )
      assert_empty scope.fetch(:missing_artifacts)
    end
  end

  def test_build_reports_next_actions_for_incomplete_handoff_bundle
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
          status: 'unreviewed',
          accepted_candidate_uids: [],
          rejected_candidate_uids: [],
          notes: []
        }
      )

      artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
        index_path,
        handoff_dir: handoff_dir,
        draft_dir: draft_dir,
        manifest_dir: manifest_dir,
        providers: ['datadog']
      )

      assert_equal(
        {
          review_handoff: 1,
          generate_reviewed_draft: 1,
          generate_provider_manifest: 1,
          write_manifest_review_report: 1
        },
        artifact_index.fetch(:summary).fetch(:next_action_counts)
      )

      scope = artifact_index.fetch(:scopes).fetch(0)
      assert_equal(
        [
          :review_handoff,
          :generate_reviewed_draft,
          :generate_provider_manifest,
          :write_manifest_review_report
        ],
        scope.fetch(:next_actions).map { |action| action.fetch(:code) }
      )
      assert_equal(
        %w[
          review_handoff
          generate_reviewed_draft
          generate_provider_manifest
          write_manifest_review_report
        ],
        JSON.parse(JSON.generate(scope)).fetch('next_actions').map { |action| action.fetch('code') }
      )
      assert_equal(
        "rules-ctl review-handoff --accept=<candidate_uid> #{handoff_path}",
        scope.fetch(:next_actions).fetch(0).fetch(:command)
      )
      assert_equal handoff_path, scope.fetch(:next_actions).fetch(0).fetch(:path)
      assert_equal 'datadog', scope.fetch(:next_actions).fetch(2).fetch(:provider)
    end
  end

  def test_build_reports_invalid_manifest_review_report_as_blocking_next_action
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
      write_json(
        File.join(handoff_dir, 'checkout-prod.handoff.json'),
        label: 'checkout-prod',
        provider: 'datadog',
        review: {
          status: 'reviewed',
          accepted_candidate_uids: ['request-latency'],
          rejected_candidate_uids: [],
          notes: []
        }
      )
      File.write(File.join(draft_dir, 'checkout-prod.rb'), "# reviewed draft\n")
      manifest_path = File.join(manifest_dir, 'checkout-api', 'datadog', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      manifest = { service: 'checkout-api', provider: 'datadog', artifacts: {} }
      write_json(manifest_path, manifest)
      report_path = File.join(manifest_dir, 'manifest-review', 'datadog.json')
      FileUtils.mkdir_p(File.dirname(report_path))
      write_json(
        report_path,
        SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
          [manifest],
          provider: 'datadog',
          handoff_dir: handoff_dir
        )
      )

      artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
        index_path,
        handoff_dir: handoff_dir,
        draft_dir: draft_dir,
        manifest_dir: manifest_dir,
        providers: ['datadog']
      )

      assert_equal 0, artifact_index.fetch(:summary).fetch(:valid_manifest_review_reports)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:invalid_manifest_review_reports)
      assert_equal({ resolve_manifest_review_findings: 1 }, artifact_index.fetch(:summary).fetch(:next_action_counts))

      scope = artifact_index.fetch(:scopes).fetch(0)
      assert_equal 'partial', scope.fetch(:status)
      provider = scope.fetch(:providers).fetch(0)
      report = provider.fetch(:manifest_review_report)
      assert_equal true, report.fetch(:exists)
      assert_equal false, report.fetch(:valid)
      assert_equal true, report.fetch(:fresh)
      assert_equal ['missing_review_provenance'], report.fetch(:finding_codes)
      assert_equal 0, report.fetch(:ready_for_apply_manifests)

      action = scope.fetch(:next_actions).fetch(0)
      assert_equal :resolve_manifest_review_findings, action.fetch(:code)
      assert_equal 'datadog', action.fetch(:provider)
      assert_equal report_path, action.fetch(:path)
      assert_equal(
        "rules-ctl manifest-review --provider=datadog --manifest=#{manifest_path} --handoff-dir=#{handoff_dir} --report=#{report_path}",
        action.fetch(:command)
      )
    end
  end

  def test_build_reports_stale_manifest_review_report_as_blocking_next_action
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
          notes: []
        }
      )
      File.write(File.join(draft_dir, 'checkout-prod.rb'), "# reviewed draft\n")
      manifest_path = File.join(manifest_dir, 'checkout-api', 'datadog', 'manifest.json')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      manifest = {
        service: 'checkout-api',
        provider: 'datadog',
        review_provenance: {
          label: 'checkout-prod',
          provider: 'datadog',
          accepted_candidate_uids: ['request-latency'],
          rejected_candidate_uids: [],
          notes: []
        }
      }
      write_json(manifest_path, manifest)
      report_path = File.join(manifest_dir, 'manifest-review', 'datadog.json')
      FileUtils.mkdir_p(File.dirname(report_path))
      report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
        [manifest],
        provider: 'datadog',
        handoff_dir: handoff_dir
      )
      write_json(report_path, report)
      write_json(manifest_path, manifest.merge(metadata: { refreshed_after_report: true }))

      artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
        index_path,
        handoff_dir: handoff_dir,
        draft_dir: draft_dir,
        manifest_dir: manifest_dir,
        providers: ['datadog']
      )

      assert_equal 0, artifact_index.fetch(:summary).fetch(:fresh_manifest_review_reports)
      assert_equal 1, artifact_index.fetch(:summary).fetch(:stale_manifest_review_reports)
      assert_equal({ refresh_manifest_review_report: 1 }, artifact_index.fetch(:summary).fetch(:next_action_counts))

      scope = artifact_index.fetch(:scopes).fetch(0)
      assert_equal 'partial', scope.fetch(:status)
      report = scope.fetch(:providers).fetch(0).fetch(:manifest_review_report)
      assert_equal true, report.fetch(:exists)
      assert_equal true, report.fetch(:valid)
      assert_equal false, report.fetch(:fresh)
      assert_equal ['stale_manifest_review_report'], report.fetch(:freshness_finding_codes)

      action = scope.fetch(:next_actions).fetch(0)
      assert_equal :refresh_manifest_review_report, action.fetch(:code)
      assert_equal 'datadog', action.fetch(:provider)
      assert_equal report_path, action.fetch(:path)
      assert_equal(
        "rules-ctl manifest-review --provider=datadog --manifest=#{manifest_path} --handoff-dir=#{handoff_dir} --output=#{report_path}",
        action.fetch(:command)
      )
    end
  end

  def test_build_checks_provider_level_report_freshness_against_all_provider_manifests
    Dir.mktmpdir do |dir|
      discovery_dir = File.join(dir, 'discovery')
      handoff_dir = File.join(dir, 'handoff')
      draft_dir = File.join(dir, 'drafts')
      manifest_dir = File.join(dir, 'generated')
      [discovery_dir, handoff_dir, draft_dir, manifest_dir].each { |path| FileUtils.mkdir_p(path) }

      scopes = [
        { label: 'checkout-prod', service: 'checkout-api', accepted: 'checkout-latency' },
        { label: 'payments-prod', service: 'payments-api', accepted: 'payments-errors' }
      ]
      scopes.each do |scope|
        write_json(
          File.join(discovery_dir, "#{scope.fetch(:label)}.json"),
          provider: 'datadog',
          scope: { label: scope.fetch(:label), service: scope.fetch(:service) },
          signals: [{ kind: 'latency', metric: 'http.server.request.duration', user_visible: true }],
          findings: []
        )
        write_json(
          File.join(handoff_dir, "#{scope.fetch(:label)}.handoff.json"),
          label: scope.fetch(:label),
          provider: 'datadog',
          review: {
            status: 'reviewed',
            accepted_candidate_uids: [scope.fetch(:accepted)],
            rejected_candidate_uids: [],
            notes: []
          }
        )
        File.write(File.join(draft_dir, "#{scope.fetch(:label)}.rb"), "# reviewed draft\n")
      end
      index_path = File.join(discovery_dir, 'index.json')
      write_json(
        index_path,
        provider: 'datadog',
        generated_at: '2026-05-13T09:00:00Z',
        total_scopes: scopes.length,
        scopes: scopes.map do |scope|
          {
            label: scope.fetch(:label),
            scope: { label: scope.fetch(:label), service: scope.fetch(:service) },
            status: 'ok',
            result_file: "#{scope.fetch(:label)}.json",
            signal_count: 1,
            finding_count: 0
          }
        end
      )

      manifests = scopes.map do |scope|
        manifest = {
          service: scope.fetch(:service),
          provider: 'datadog',
          review_provenance: {
            label: scope.fetch(:label),
            provider: 'datadog',
            accepted_candidate_uids: [scope.fetch(:accepted)],
            rejected_candidate_uids: [],
            notes: []
          }
        }
        manifest_path = File.join(manifest_dir, scope.fetch(:service), 'datadog', 'manifest.json')
        FileUtils.mkdir_p(File.dirname(manifest_path))
        write_json(manifest_path, manifest)
        manifest
      end
      report_path = File.join(manifest_dir, 'manifest-review', 'datadog.json')
      FileUtils.mkdir_p(File.dirname(report_path))
      write_json(
        report_path,
        SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
          manifests,
          provider: 'datadog',
          handoff_dir: handoff_dir
        )
      )

      artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
        index_path,
        handoff_dir: handoff_dir,
        draft_dir: draft_dir,
        manifest_dir: manifest_dir,
        providers: ['datadog']
      )

      assert_equal 2, artifact_index.fetch(:summary).fetch(:complete_scopes)
      assert_equal 2, artifact_index.fetch(:summary).fetch(:fresh_manifest_review_reports)
      assert_equal 0, artifact_index.fetch(:summary).fetch(:stale_manifest_review_reports)
      assert_equal({}, artifact_index.fetch(:summary).fetch(:next_action_counts))
      artifact_index.fetch(:scopes).each do |scope|
        assert_equal 'complete', scope.fetch(:status)
        assert_equal true, scope.fetch(:providers).fetch(0).fetch(:manifest_review_report).fetch(:fresh)
      end
    end
  end

  private

  def write_json(path, payload)
    File.write(path, JSON.pretty_generate(payload))
  end
end
