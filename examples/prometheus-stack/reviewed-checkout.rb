# frozen_string_literal: true

load File.expand_path('../services/checkout.rb', __dir__)

definition = SloRulesEngine.definitions.fetch(-1)
definition.review_provenance = SloRulesEngine::ReviewProvenance.new(
  label: 'checkout-prometheus-prod',
  provider: 'prometheus_stack',
  accepted_candidate_uids: ['http-requests'],
  rejected_candidate_uids: [],
  notes: ['Public-safe reviewed Prometheus Stack walkthrough fixture.']
)
