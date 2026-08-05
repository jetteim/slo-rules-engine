# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/sre'
require_relative 'support/release_bundle_fixtures'

class LiveStatusAggregateTest < Minitest::Test
  include ReleaseBundleFixtures

  NOW = Time.utc(2026, 7, 27, 13, 0, 0)
  REVIEWED_AT = '2026-07-27T12:00:00Z'

  class FakeClient
    attr_reader :queries

    def initialize(now:, fail_queries: false)
      @now = now
      @fail_queries = fail_queries
      @queries = []
    end

    def query(expression)
      queries << expression
      raise 'private backend failure' if @fail_queries

      value =
        if expression.start_with?('timestamp(')
          (@now - 10).to_f
        elsif expression.include?('period_error_budget_remaining') || expression.end_with?(':error_budget_remaining_ratio')
          0.8
        elsif expression.include?('error_budget:ratio') || expression.end_with?(':error_budget_ratio')
          0.001
        elsif expression.include?('objective:ratio') || expression.end_with?(':objective_ratio')
          0.999
        elsif expression.start_with?('1 - (') || expression.end_with?(':success_ratio')
          0.9998
        elsif expression.include?('_count') || expression.end_with?(':observations')
          42
        elsif expression.include?(':burn_rate:') || expression.include?('current_burn_rate') ||
              expression.include?('period_burn_rate')
          0.2
        else
          raise "unexpected query #{expression.inspect}"
        end
      {
        'resultType' => 'vector',
        'result' => [
          {
            'metric' => {},
            'value' => [@now.to_f, value.to_s]
          }
        ]
      }
    end
  end

  def test_aggregates_packaged_sloth_evidence_from_a_current_release_bundle
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(
        dir,
        providers: %w[prometheus_stack sloth]
      )
      sloth_evidence = write_sloth_downstream_evidence_fixture(
        dir,
        fixture.fetch(:manifests).fetch('sloth')
      )
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: 'team/payments-sre',
        reviewed_at: REVIEWED_AT,
        sloth_evidence: {
          'checkout-api/sloth' => sloth_evidence.fetch(:evidence)
        }
      )
      bundle_path = File.join(dir, 'release-bundle.json')
      File.write(bundle_path, JSON.pretty_generate(bundle))
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_bundle(bundle_path)
      clients = []

      report = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: lambda do |base_url|
          clients << base_url
          FakeClient.new(now: NOW)
        end,
        clock: -> { NOW }
      ).read(
        input,
        target_base_urls: {
          'checkout-api/prometheus_stack' => 'https://prometheus.example.test',
          'checkout-api/sloth' => 'https://sloth-prometheus.example.test'
        },
        max_age_seconds: 300
      ).to_h

      sloth_target = bundle.fetch(:targets).find { |target| target.fetch(:provider) == 'sloth' }
      evidence_artifact = bundle.fetch(:artifacts).find do |artifact|
        artifact.fetch(:uid) == sloth_target.fetch(:downstream_evidence_artifact_uid)
      end
      assert_equal 'sloth_downstream_evidence', evidence_artifact.fetch(:kind)
      assert_equal sloth_evidence.fetch(:evidence), evidence_artifact.dig(:source, :path)
      assert_equal 2, report.fetch(:summary).fetch(:reported_targets)
      assert_equal 0, report.fetch(:summary).fetch(:unsupported_targets)
      assert_equal true, report.fetch(:summary).fetch(:coverage_complete)
      assert_equal %w[prometheus_stack sloth], report.fetch(:targets).map { |target| target.fetch(:provider) }
      assert report.fetch(:targets).all? { |target| target.fetch(:outcome) == 'reported' }
      assert_equal 'healthy', report.fetch(:targets).last.dig(:report, :statuses, 0, :state)
      assert_equal 2, clients.length
      refute_includes JSON.generate(report), 'example.test'
    end
  end

  def test_aggregates_a_portfolio_sloth_target_with_exact_evidence
    Dir.mktmpdir do |dir|
      manifest_path = File.join(dir, 'checkout-api.sloth.json')
      File.write(manifest_path, JSON.pretty_generate(reviewed_provider_manifest('sloth')))
      evidence = write_sloth_downstream_evidence_fixture(dir, manifest_path)
      portfolio_path = File.join(dir, 'portfolio.json')
      File.write(
        portfolio_path,
        JSON.pretty_generate(
          schema_version: 'slo-rules-engine/live-status-portfolio/v1',
          kind: 'LiveStatusPortfolio',
          targets: [
            {
              uid: 'checkout-api/sloth',
              manifest: File.basename(manifest_path),
              evidence: Pathname.new(evidence.fetch(:evidence)).relative_path_from(Pathname.new(dir)).to_s
            }
          ]
        )
      )
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)

      report = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: ->(_base_url) { FakeClient.new(now: NOW) },
        clock: -> { NOW }
      ).read(
        input,
        target_base_urls: {
          'checkout-api/sloth' => 'https://sloth-prometheus.example.test'
        }
      ).to_h

      assert_equal true, report.fetch(:summary).fetch(:coverage_complete)
      assert_equal 'reported', report.fetch(:targets).fetch(0).fetch(:outcome)
      assert_equal 'sloth', report.fetch(:targets).fetch(0).dig(:report, :provider)
      assert_equal evidence.fetch(:evidence), input.targets.fetch(0).fetch(:evidence_path)
      assert_equal evidence.fetch(:evidence), input.source.fetch(:evidence).fetch(0).fetch(:path)
    end
  end

  def test_rejects_stale_sloth_evidence_across_targets_before_creating_any_client
    Dir.mktmpdir do |dir|
      prometheus_path = File.join(dir, 'checkout.prometheus.json')
      sloth_path = File.join(dir, 'checkout.sloth.json')
      File.write(prometheus_path, JSON.pretty_generate(reviewed_provider_manifest('prometheus_stack')))
      File.write(sloth_path, JSON.pretty_generate(reviewed_provider_manifest('sloth')))
      evidence = write_sloth_downstream_evidence_fixture(dir, sloth_path)
      portfolio_path = File.join(dir, 'portfolio.json')
      File.write(
        portfolio_path,
        JSON.pretty_generate(
          schema_version: 'slo-rules-engine/live-status-portfolio/v1',
          kind: 'LiveStatusPortfolio',
          targets: [
            { uid: 'checkout-api/prometheus_stack', manifest: File.basename(prometheus_path) },
            {
              uid: 'checkout-api/sloth',
              manifest: File.basename(sloth_path),
              evidence: evidence.fetch(:evidence)
            }
          ]
        )
      )
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
      generated = YAML.safe_load(File.read(evidence.fetch(:generated)), aliases: false)
      generated.fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'vector(0)'
      File.write(evidence.fetch(:generated), YAML.dump(generated))
      client_count = 0

      error = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        SloRulesEngine::LiveStatus::AggregateReader.new(
          client_factory: lambda do |_base_url|
            client_count += 1
            FakeClient.new(now: NOW)
          end
        ).read(
          input,
          target_base_urls: {
            'checkout-api/prometheus_stack' => 'https://prometheus.example.test',
            'checkout-api/sloth' => 'https://sloth-prometheus.example.test'
          }
        )
      end

      assert_equal 'invalid_sloth_live_status_evidence', error.code
      assert_includes error.findings.map { |finding| finding.fetch(:code) }, 'stale_generated_rules'
      assert_equal 0, client_count
    end
  end

  def test_aggregates_supported_and_unsupported_bundle_targets_without_persisting_runtime_urls
    Dir.mktmpdir do |dir|
      fixture = write_release_bundle_fixture(
        dir,
        providers: %w[prometheus_stack sloth]
      )
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: 'team/payments-sre',
        reviewed_at: REVIEWED_AT
      )
      bundle_path = File.join(dir, 'release-bundle.json')
      File.write(bundle_path, JSON.pretty_generate(bundle))
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_bundle(bundle_path)
      clients = []

      report = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: lambda do |base_url|
          clients << base_url
          FakeClient.new(now: NOW)
        end,
        clock: -> { NOW }
      ).read(
        input,
        target_base_urls: {
          'checkout-api/prometheus_stack' => 'https://prometheus.example.test'
        },
        max_age_seconds: 300
      )
      payload = report.to_h

      assert_equal 'slo-rules-engine/live-slo-status-aggregate/v1', payload.fetch(:schema_version)
      assert_equal 'LiveSLOStatusAggregateReport', payload.fetch(:kind)
      assert_equal 'release_bundle', payload.fetch(:scope)
      assert_equal bundle.fetch(:bundle_id), payload.fetch(:source).fetch(:bundle_id)
      assert_equal(
        {
          target_count: 2,
          reported_targets: 1,
          unsupported_targets: 1,
          slo_count: 1,
          healthy: 1,
          at_risk: 0,
          exhausted: 0,
          missing_telemetry: 0,
          unverifiable: 0,
          coverage_complete: false,
          evidence_complete: false
        },
        payload.fetch(:summary)
      )
      assert_equal %w[checkout-api/prometheus_stack checkout-api/sloth],
                   payload.fetch(:targets).map { |target| target.fetch(:uid) }
      assert_equal 'reported', payload.fetch(:targets).fetch(0).fetch(:outcome)
      assert_equal 'healthy', payload.fetch(:targets).fetch(0).fetch(:report).fetch(:statuses).fetch(0).fetch(:state)
      assert_equal 'unsupported', payload.fetch(:targets).fetch(1).fetch(:outcome)
      assert_equal ['missing_sloth_live_status_evidence'],
                   payload.fetch(:targets).fetch(1).fetch(:findings).map { |finding| finding.fetch(:code) }
      assert_equal ['https://prometheus.example.test'], clients
      refute_includes JSON.generate(payload), 'prometheus.example.test'
    end
  end

  def test_preserves_failed_target_queries_as_unverifiable_while_other_targets_report
    Dir.mktmpdir do |dir|
      manifests = write_portfolio_manifests(dir)
      portfolio_path = write_portfolio(dir, manifests)
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)

      report = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: lambda do |base_url|
          FakeClient.new(now: NOW, fail_queries: base_url.include?('search'))
        end,
        clock: -> { NOW }
      ).read(
        input,
        target_base_urls: {
          'checkout-api/prometheus_stack' => 'https://checkout-prometheus.example.test',
          'search-api/prometheus_stack' => 'https://search-prometheus.example.test'
        },
        max_age_seconds: 300
      ).to_h

      assert_equal 2, report.fetch(:summary).fetch(:reported_targets)
      assert_equal 1, report.fetch(:summary).fetch(:healthy)
      assert_equal 1, report.fetch(:summary).fetch(:unverifiable)
      assert_equal true, report.fetch(:summary).fetch(:coverage_complete)
      assert_equal false, report.fetch(:summary).fetch(:evidence_complete)
      search = report.fetch(:targets).find { |target| target.fetch(:uid) == 'search-api/prometheus_stack' }
      assert_equal 'reported', search.fetch(:outcome)
      assert_equal 'unverifiable', search.fetch(:report).fetch(:statuses).fetch(0).fetch(:state)
      assert search.fetch(:report).fetch(:statuses).fetch(0).fetch(:findings).all? do |finding|
        refute_includes finding.fetch(:message), 'private backend failure'
      end
    end
  end

  def test_rejects_incomplete_runtime_and_stale_bundle_before_creating_clients
    Dir.mktmpdir do |dir|
      manifests = write_portfolio_manifests(dir)
      portfolio_path = write_portfolio(dir, manifests)
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
      client_count = 0
      reader = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: lambda do |_base_url|
          client_count += 1
          FakeClient.new(now: NOW)
        end,
        clock: -> { NOW }
      )

      error = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        reader.read(
          input,
          target_base_urls: {
            'checkout-api/prometheus_stack' => 'https://checkout-prometheus.example.test'
          },
          max_age_seconds: 300
        )
      end
      assert_equal 'missing_live_status_runtime', error.code
      assert_equal 0, client_count

      fixture = write_release_bundle_fixture(File.join(dir, 'bundle'))
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: 'team/payments-sre',
        reviewed_at: REVIEWED_AT
      )
      bundle_path = File.join(dir, 'bundle.json')
      File.write(bundle_path, JSON.pretty_generate(bundle))
      File.write(fixture.fetch(:manifest), "{}\n")

      stale = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        SloRulesEngine::LiveStatus::InputResolver.new.from_bundle(bundle_path)
      end
      assert_equal 'stale_live_status_bundle', stale.code
      assert_equal 0, client_count
    end
  end

  def test_rejects_credential_bearing_runtime_url_before_backend_access
    Dir.mktmpdir do |dir|
      manifests = write_portfolio_manifests(dir).first(1)
      portfolio_path = write_portfolio(dir, manifests)
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
      client_count = 0
      reader = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: lambda do |_base_url|
          client_count += 1
          FakeClient.new(now: NOW)
        end
      )

      error = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        reader.read(
          input,
          target_base_urls: {
            'checkout-api/prometheus_stack' => 'https://user:secret@prometheus.example.test'
          },
          max_age_seconds: 300
        )
      end

      assert_equal 'invalid_live_status_runtime', error.code
      assert_equal 0, client_count
    end
  end

  def test_rejects_unknown_runtime_and_an_input_with_no_supported_targets_before_backend_access
    Dir.mktmpdir do |dir|
      manifests = write_portfolio_manifests(dir).first(1)
      portfolio_path = write_portfolio(dir, manifests)
      input = SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
      client_count = 0
      reader = SloRulesEngine::LiveStatus::AggregateReader.new(
        client_factory: lambda do |_base_url|
          client_count += 1
          FakeClient.new(now: NOW)
        end
      )

      unknown = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        reader.read(
          input,
          target_base_urls: {
            'checkout-api/prometheus_stack' => 'https://prometheus.example.test',
            'unknown/prometheus_stack' => 'https://unknown.example.test'
          }
        )
      end
      assert_equal 'unknown_live_status_runtime', unknown.code

      fixture = write_release_bundle_fixture(File.join(dir, 'sloth'), provider: 'sloth')
      bundle = SloRulesEngine::ReleaseBundle::Builder.new.build(
        fixture.fetch(:artifact_index),
        reviewer: 'team/payments-sre',
        reviewed_at: REVIEWED_AT
      )
      bundle_path = File.join(dir, 'sloth-bundle.json')
      File.write(bundle_path, JSON.pretty_generate(bundle))
      unsupported_input = SloRulesEngine::LiveStatus::InputResolver.new.from_bundle(bundle_path)
      unsupported = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        reader.read(unsupported_input, target_base_urls: {})
      end

      assert_equal 'no_supported_live_status_targets', unsupported.code
      assert_equal 0, client_count
    end
  end

  def test_rejects_duplicate_portfolio_targets_and_missing_review_evidence
    Dir.mktmpdir do |dir|
      manifests = write_portfolio_manifests(dir).first(1)
      portfolio_path = write_portfolio(dir, manifests + manifests)

      duplicate = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
      end
      assert_equal 'duplicate_live_status_target', duplicate.code

      manifest_path = manifests.fetch(0).fetch(1)
      manifest = JSON.parse(File.read(manifest_path))
      manifest.delete('review_provenance')
      File.write(manifest_path, JSON.pretty_generate(manifest))
      portfolio_path = write_portfolio(dir, manifests)
      unreviewed = assert_raises(SloRulesEngine::LiveStatus::AggregateError) do
        SloRulesEngine::LiveStatus::InputResolver.new.from_portfolio(portfolio_path)
      end

      assert_equal 'missing_review_evidence', unreviewed.code
    end
  end

  private

  def write_portfolio_manifests(dir)
    %w[checkout-api search-api].map do |service|
      manifest = reviewed_manifest_for(service)
      path = File.join(dir, "#{service}.manifest.json")
      File.write(path, JSON.pretty_generate(manifest))
      [service, path]
    end
  end

  def write_portfolio(dir, manifests)
    path = File.join(dir, 'portfolio.json')
    payload = {
      schema_version: 'slo-rules-engine/live-status-portfolio/v1',
      kind: 'LiveStatusPortfolio',
      targets: manifests.map do |service, manifest_path|
        {
          uid: "#{service}/prometheus_stack",
          manifest: File.basename(manifest_path)
        }
      end
    }
    File.write(path, JSON.pretty_generate(payload))
    path
  end

  def reviewed_manifest_for(service)
    reviewed_provider_manifest('prometheus_stack', service: service)
  end
end
