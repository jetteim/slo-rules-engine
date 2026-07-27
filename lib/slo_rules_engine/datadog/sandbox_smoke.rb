# frozen_string_literal: true

require 'securerandom'

module SloRulesEngine
  module Datadog
    class SandboxSmoke
      SCHEMA_VERSION = 'slo-rules-engine/datadog-sandbox-smoke/v1'
      DEFAULT_SERVICE = 'slo-rules-engine-sandbox'
      DASHBOARD_PAGE_SIZE = StateReader::DASHBOARD_PAGE_SIZE

      class ContractError < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      def initialize(
        client:,
        site:,
        service: DEFAULT_SERVICE,
        token: SecureRandom.hex(8),
        attempts: 10,
        sleep_fn: ->(seconds) { sleep(seconds) }
      )
        @client = client
        @site = site
        @service = service
        @token = token
        @attempts = attempts
        @sleep_fn = sleep_fn
      end

      def run(allow_mutation: false)
        checks = read_checks
        {
          schema_version: SCHEMA_VERSION,
          status: 'passed',
          mode: allow_mutation ? 'temporary_dashboard_mutation' : 'read_only',
          site: @site,
          checks: checks,
          mutation: allow_mutation ? run_dashboard_mutation : { status: 'not_requested' }
        }
      end

      private

      def read_checks
        @client.validate_credentials!
        checks = [passed_check('credentials_present')]

        validation = @client.request('GET', '/api/v1/validate')
        raise ContractError, 'api_key_invalid' unless fetch_value(validation, :valid) == true

        checks << passed_check('api_key_validation')
        catalog = @client.request(
          'GET',
          "/api/v1/dashboard?count=#{DASHBOARD_PAGE_SIZE}&start=0"
        )
        dashboards = Array(fetch_value(catalog, :dashboards, []))
        checks << passed_check('dashboard_catalog', first_page_count: dashboards.length)

        summary = dashboards.find { |entry| fetch_value(entry, :id) }
        if summary
          id = fetch_value(summary, :id)
          detail = @client.request('GET', "/api/v1/dashboard/#{id}")
          raise ContractError, 'dashboard_detail_identity_mismatch' unless fetch_value(detail, :id).to_s == id.to_s

          checks << passed_check('dashboard_detail')
        else
          checks << {
            name: 'dashboard_detail',
            status: 'skipped',
            reason: 'empty_catalog'
          }
        end
        checks
      end

      def run_dashboard_mutation
        source_ref = "sandbox_smoke.#{@token}"
        title = "slo-rules-engine sandbox smoke #{@token}"
        payload = {
          title: title,
          description: 'Temporary dashboard created by the slo-rules-engine sandbox contract smoke test.',
          layout_type: 'ordered',
          tags: [
            'managed_by:slo-rules-engine',
            "service:#{@service}",
            "source_ref:#{source_ref}"
          ],
          template_variables: [],
          widgets: []
        }
        created_id = nil
        cleanup_complete = false

        response = @client.request('POST', '/api/v1/dashboard', payload: payload)
        created_id = fetch_value(response, :id)
        raise ContractError, 'dashboard_create_missing_id' if created_id.to_s.empty?

        desired = {
          dashboards: [
            {
              title: title,
              source: source_ref
            }
          ]
        }
        found = wait_for_dashboard(desired, title)
        raise ContractError, 'dashboard_not_found_after_create' unless trusted_match?(found, created_id)

        @client.delete_dashboard(created_id)
        raise ContractError, 'dashboard_present_after_delete' unless wait_for_dashboard_absence(desired, title)

        cleanup_complete = true
        {
          status: 'passed',
          provider_resource_id: created_id,
          source_ref: source_ref,
          checks: %w[
            dashboard_created
            dashboard_found_by_source_ref
            dashboard_deleted
            dashboard_absent_after_delete
          ]
        }
      ensure
        cleanup_dashboard(created_id) if created_id && !cleanup_complete
      end

      def wait_for_dashboard(desired, title)
        wait_for_state do
          state = @client.existing_state(desired: desired)
          fetch_value(fetch_value(state, :dashboards, {}), title)
        end
      end

      def wait_for_dashboard_absence(desired, title)
        wait_for_state do
          state = @client.existing_state(desired: desired)
          dashboards = fetch_value(state, :dashboards, {})
          true unless dashboards.key?(title) || dashboards.key?(title.to_sym)
        end
      end

      def wait_for_state
        @attempts.times do |index|
          result = yield
          return result if result

          @sleep_fn.call([0.5 * (index + 1), 2].min) if index + 1 < @attempts
        end
        nil
      end

      def trusted_match?(entry, created_id)
        return false unless entry

        identity = fetch_value(entry, :match_identity, {})
        fetch_value(entry, :id).to_s == created_id.to_s &&
          fetch_value(identity, :strategy) == 'source_ref' &&
          fetch_value(identity, :confidence) == 'high'
      end

      def cleanup_dashboard(id)
        @client.delete_dashboard(id)
      rescue StandardError
        nil
      end

      def passed_check(name, attributes = {})
        { name: name, status: 'passed' }.merge(attributes)
      end

      def fetch_value(hash, key, default = nil)
        return default unless hash.respond_to?(:fetch)

        hash.fetch(key) { hash.fetch(key.to_s, default) }
      end
    end
  end
end
