# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative '../../lib/slo_rules_engine'
require_relative 'onboarding_fixtures'

module ReleaseBundleFixtures
  include OnboardingFixtures

  def write_release_bundle_fixture(dir, include_plan: false, provider: 'prometheus_stack', providers: nil)
    providers = Array(providers || [provider]).map(&:to_s)
    provider = providers.fetch(0)
    discovery_dir = File.join(dir, 'discovery')
    handoff_dir = File.join(dir, 'handoff')
    draft_dir = File.join(dir, 'drafts')
    manifest_dir = File.join(dir, 'generated')
    FileUtils.mkdir_p([discovery_dir, handoff_dir, draft_dir])

    discovery_index_path = write_discovery_fixture(discovery_dir)
    rewrite_json(discovery_index_path) { |payload| payload['provider'] = provider }
    rewrite_json(File.join(discovery_dir, 'checkout-prod.json')) do |payload|
      payload['provider'] = provider
      payload.fetch('signals').fetch(0)['source'] = provider
    end

    handoff = reviewed_handoff_packet
    handoff[:provider] = provider
    handoff_path = File.join(handoff_dir, 'checkout-prod.handoff.json')
    File.write(handoff_path, JSON.pretty_generate(handoff))

    draft_path = File.join(draft_dir, 'checkout-prod.rb')
    File.write(draft_path, "# reviewed public-safe definition\n")

    manifests = {}
    reports = {}
    providers.each do |provider_key|
      manifest = reviewed_provider_manifest(provider_key)
      manifest_path = File.join(manifest_dir, 'checkout-api', provider_key, 'manifest.json')
      FileUtils.mkdir_p(File.dirname(manifest_path))
      File.write(manifest_path, JSON.pretty_generate(manifest))
      manifests[provider_key] = manifest_path

      report = SloRulesEngine::ManifestReviewQueue::ReportBuilder.new.build(
        [manifest],
        provider: provider_key,
        handoff_dir: handoff_dir
      )
      report_path = File.join(manifest_dir, 'manifest-review', "#{provider_key}.json")
      FileUtils.mkdir_p(File.dirname(report_path))
      File.write(report_path, JSON.pretty_generate(report))
      reports[provider_key] = report_path
    end

    artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
      discovery_index_path,
      handoff_dir: handoff_dir,
      draft_dir: draft_dir,
      manifest_dir: manifest_dir,
      providers: providers
    )
    artifact_index_path = File.join(dir, 'artifact-index.json')
    File.write(artifact_index_path, JSON.pretty_generate(artifact_index))

    plans = {}
    if include_plan
      providers.each do |provider_key|
        manifest = JSON.parse(File.read(manifests.fetch(provider_key)), symbolize_names: true)
        plan = SloRulesEngine::Appliers::ManifestBundle.new(output_dir: File.join(dir, 'managed')).plan(manifest)
        plan_path = File.join(dir, "#{provider_key}-plan.json")
        File.write(plan_path, JSON.pretty_generate(plan.to_h))
        plans["checkout-api/#{provider_key}"] = plan_path
      end
    end

    {
      artifact_index: artifact_index_path,
      discovery: File.join(discovery_dir, 'checkout-prod.json'),
      handoff: handoff_path,
      draft: draft_path,
      manifest: manifests.fetch(provider),
      manifests: manifests,
      report: reports.fetch(provider),
      reports: reports,
      plan: plans["checkout-api/#{provider}"],
      plans: plans,
      target: "checkout-api/#{provider}",
      targets: providers.map { |provider_key| "checkout-api/#{provider_key}" }
    }.compact
  end

  private

  def reviewed_provider_manifest(provider)
    SloRulesEngine.clear_definitions
    load File.expand_path('../../examples/services/checkout.rb', __dir__)
    definition = SloRulesEngine.definitions.fetch(0)
    definition.review_provenance = SloRulesEngine::ReviewProvenance.new(
      label: 'checkout-prod',
      provider: provider,
      accepted_candidate_uids: ['request-latency'],
      rejected_candidate_uids: ['request-traffic'],
      notes: ['Latency is accepted for the first onboarding draft.']
    )
    SloRulesEngine.default_provider_registry.fetch(provider).generate(definition).to_h.merge(
      service: definition.service
    )
  end

  def rewrite_json(path)
    payload = JSON.parse(File.read(path))
    yield payload
    File.write(path, JSON.pretty_generate(payload))
  end
end
