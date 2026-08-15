# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module TelemetryCommands
      def lookup_telemetry(argv)
        provider_key = nil
        metric = nil
        kind = 'unknown'
        query = nil
        user_visible = true
        base_url = nil
        from = nil
        to = nil
        parser = OptionParser.new do |opts|
          opts.on('--provider=PROVIDER', 'Provider key') { |value| provider_key = value }
          opts.on('--metric=METRIC', 'Metric name to look up') { |value| metric = value }
          opts.on('--kind=KIND', 'Signal kind for candidate generation') { |value| kind = value }
          opts.on('--query=QUERY', 'Backend query expression, defaults to metric') { |value| query = value }
          opts.on('--user-visible=VALUE', 'Whether the metric represents user-visible service quality') do |value|
            user_visible = SloRulesEngine::TelemetryLookup.truthy?(value)
          end
          opts.on('--base-url=URL', 'Prometheus-compatible base URL') { |value| base_url = value }
          opts.on('--from=TIMESTAMP', Integer, 'Lookup window start') { |value| from = value }
          opts.on('--to=TIMESTAMP', Integer, 'Lookup window end') { |value| to = value }
        end
        parser.parse!(argv)
        abort_usage('missing --provider') unless provider_key
        abort_usage('missing --metric') unless metric

        result = telemetry_lookup_adapter(provider_key, base_url: base_url, from: from, to: to).lookup(
          metric: metric,
          kind: kind,
          query: query,
          user_visible: user_visible
        )
        puts JSON.pretty_generate(result.to_h)
      rescue SloRulesEngine::Datadog::MissingCredentials => error
        puts JSON.pretty_generate(
          valid: false,
          provider: provider_key,
          error: {
            code: 'missing_credentials',
            message: error.message
          }
        )
        exit 1
      end

      def telemetry_lookup_adapter(provider_key, base_url:, from:, to:)
        case provider_key
        when 'datadog'
          SloRulesEngine::TelemetryLookup::Datadog.new(from: from, to: to)
        when 'prometheus_stack', 'sloth'
          client = if base_url
                     SloRulesEngine::TelemetryLookup::Prometheus::Client.new(base_url: base_url)
                   else
                     SloRulesEngine::TelemetryLookup::Prometheus::Client.new
                   end
          SloRulesEngine::TelemetryLookup::Prometheus.new(client: client, provider: provider_key)
        else
          abort_usage("unsupported telemetry lookup provider: #{provider_key}")
        end
      end

      def candidates(argv)
        abort_usage('missing telemetry JSON file') if argv.empty?

        signals = telemetry_signals_from_file(argv.fetch(0))
        puts JSON.pretty_generate(SloRulesEngine::Onboarding::CandidateGenerator.new.review(signals))
      end

      def draft_definition(argv)
        service = nil
        owner = nil
        environment = 'production'
        parser = OptionParser.new do |opts|
          opts.on('--service=SERVICE', 'Service name for the draft definition') { |value| service = value }
          opts.on('--owner=OWNER', 'Service owner for the draft definition') { |value| owner = value }
          opts.on('--environment=ENVIRONMENT', 'Environment for the draft definition') { |value| environment = value }
        end
        parser.parse!(argv)
        abort_usage('missing --service') unless service
        abort_usage('missing --owner') unless owner
        abort_usage('missing telemetry JSON file') if argv.empty?

        signals = telemetry_signals_from_file(argv.fetch(0))
        puts SloRulesEngine::Onboarding::DefinitionDraftGenerator.new.generate(
          service: service,
          owner: owner,
          environment: environment,
          signals: signals
        )
      end

      def recommend_calculation_basis(argv)
        observations_per_second = nil
        failed_observations_to_alert = nil
        parser = OptionParser.new do |opts|
          opts.on('--observations-per-second=VALUE', Float) { |value| observations_per_second = value }
          opts.on('--failed-observations-to-alert=VALUE', Float) { |value| failed_observations_to_alert = value }
        end
        parser.parse!(argv)
        abort_usage('missing --observations-per-second') unless observations_per_second
        abort_usage('missing --failed-observations-to-alert') unless failed_observations_to_alert

        result = SloRulesEngine::Application::RecommendCalculationBasis.new.call(
          {
            'observations_per_second' => observations_per_second,
            'failed_observations_to_alert' => failed_observations_to_alert
          },
          context: application_context
        )
        puts JSON.pretty_generate(result.value)
      end

      def reality_check(argv)
        provider_key = nil
        telemetry_path = nil
        lookup_result_paths = []
        online = false
        base_url = nil
        from = nil
        to = nil
        parser = OptionParser.new do |opts|
          opts.on('--provider=PROVIDER', 'Provider key') { |value| provider_key = value }
          opts.on('--telemetry=FILE', 'Telemetry inventory JSON file') { |value| telemetry_path = value }
          opts.on('--lookup-result=FILE', 'Telemetry lookup result JSON file') { |value| lookup_result_paths << value }
          opts.on('--online', 'Run explicit backend telemetry lookup before checking') { online = true }
          opts.on('--base-url=URL', 'Prometheus-compatible base URL for online lookup') { |value| base_url = value }
          opts.on('--from=TIMESTAMP', Integer, 'Online lookup window start') { |value| from = value }
          opts.on('--to=TIMESTAMP', Integer, 'Online lookup window end') { |value| to = value }
        end
        parser.parse!(argv)
        abort_usage('missing --provider') unless provider_key
        abort_usage('missing telemetry evidence') unless telemetry_path || !lookup_result_paths.empty? || online

        telemetry_signals = telemetry_path ? JSON.parse(File.read(telemetry_path), symbolize_names: true) : []
        lookup_results = lookup_result_paths.map { |path| JSON.parse(File.read(path), symbolize_names: true) }
        definitions = load_definitions(argv)
        lookup_results.concat(online_lookup_results(definitions, provider_key, base_url: base_url, from: from, to: to)) if online
        checker = SloRulesEngine::RealityCheck::TelemetryBindingChecker.new(provider: provider_key)
        reports = definitions.map do |definition|
          checker.check(definition, telemetry_signals, lookup_results: lookup_results).to_h.merge(service: definition.service)
        end
        findings = reports.flat_map { |report| report.fetch(:findings) }
        payload = {
          valid: findings.empty?,
          provider: provider_key,
          findings: findings,
          reports: reports
        }
        puts JSON.pretty_generate(payload)
        exit(payload[:valid] ? 0 : 1)
      rescue SloRulesEngine::Datadog::MissingCredentials => error
        puts JSON.pretty_generate(
          valid: false,
          provider: provider_key,
          error: {
            code: 'missing_credentials',
            message: error.message
          }
        )
        exit 1
      end

      def discover_telemetry(argv)
        provider_key = nil
        scope_file = nil
        output_dir = nil
        service = nil
        host = nil
        selector_values = []
        base_url = nil
        from = nil
        to = nil
        parser = OptionParser.new do |opts|
          opts.on('--provider=PROVIDER', 'Provider key') { |value| provider_key = value }
          opts.on('--scope-file=FILE', 'JSON file containing discovery scopes') { |value| scope_file = value }
          opts.on('--output-dir=DIR', 'Directory for batch discovery output') { |value| output_dir = value }
          opts.on('--service=SERVICE', 'Service scope for discovery') { |value| service = value }
          opts.on('--host=HOST', 'Host scope for Datadog discovery') { |value| host = value }
          opts.on('--selector=KEY=VALUE', 'Additional selector scope') { |value| selector_values << value }
          opts.on('--base-url=URL', 'Prometheus-compatible base URL') { |value| base_url = value }
          opts.on('--from=TIMESTAMP', Integer, 'Discovery lookback start') { |value| from = value }
          opts.on('--to=TIMESTAMP', Integer, 'Discovery lookback end') { |value| to = value }
        end
        parser.parse!(argv)
        abort_usage('missing --provider') unless provider_key
        if scope_file
          if !service.to_s.empty? || !selector_values.empty? || !host.to_s.empty?
            abort_usage('--scope-file cannot be combined with --service, --selector, or --host')
          end
          abort_usage('missing --output-dir') if output_dir.to_s.empty?

          scopes = SloRulesEngine::TelemetryBatchDiscovery.load_scopes(scope_file, provider: provider_key)
          adapter = telemetry_lookup_adapter(provider_key, base_url: base_url, from: from, to: to)
          result = SloRulesEngine::TelemetryBatchDiscovery::Runner.new(
            provider: provider_key,
            adapter: adapter,
            output_dir: output_dir
          ).run(scopes)
          puts JSON.pretty_generate(result)
          exit 1 unless result[:failed_scopes].zero?
          return
        end

        selectors = parse_selectors(selector_values)
        abort_usage('missing discovery scope') if service.to_s.empty? && selectors.empty? && host.to_s.empty?
        if provider_key == 'datadog' && !host.to_s.empty? && (!service.to_s.empty? || !selectors.empty?)
          abort_usage('datadog discovery cannot combine --host with --service or --selector')
        end
        abort_usage('--host is only supported for datadog discovery') if provider_key != 'datadog' && !host.to_s.empty?

        result = telemetry_lookup_adapter(provider_key, base_url: base_url, from: from, to: to).discover(
          service: service,
          selectors: selectors,
          host: host
        )
        puts JSON.pretty_generate(result.to_h)
      rescue SloRulesEngine::Datadog::MissingCredentials => error
        puts JSON.pretty_generate(
          valid: false,
          provider: provider_key,
          error: {
            code: 'missing_credentials',
            message: error.message
          }
        )
        exit 1
      end

      def online_lookup_results(definitions, provider_key, base_url:, from:, to:)
        adapter = telemetry_lookup_adapter(provider_key, base_url: base_url, from: from, to: to)
        definitions.flat_map do |definition|
          definition.slis.map do |sli|
            binding = sli.metric.binding_for(provider_key)
            adapter.lookup(
              metric: binding.metric,
              kind: signal_kind_for_sli(sli),
              query: binding.query,
              user_visible: true
            ).to_h
          end
        end
      end

      def signal_kind_for_sli(sli)
        text = [sli.uid, sli.title, sli.user_visible_rationale].compact.join(' ').downcase
        return 'latency' if text.include?('latency') || text.include?('duration')
        return 'errors' if text.include?('error') || text.include?('success')
        return 'availability' if text.include?('availability')
        return 'traffic' if text.include?('traffic') || text.include?('request')

        'unknown'
      end

      def telemetry_signals_from_file(path)
        payload = JSON.parse(File.read(path), symbolize_names: true)
        SloRulesEngine::TelemetryLookup.extract_signals(payload)
      end

      def parse_selectors(selector_values)
        Array(selector_values).each_with_object({}) do |selector, parsed|
          key, value = selector.split('=', 2)
          abort_usage("invalid selector #{selector.inspect}") if key.to_s.empty? || value.to_s.empty?

          parsed[key] = value
        end
      end
    end
  end
end
