# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module SlothEvidenceCommands
      def sloth_evidence(argv)
        dispatch_registered_subcommand(
          'sloth-evidence',
          argv,
          'usage: sloth-evidence capture|status'
        )
      end

      def sloth_evidence_capture(argv)
        manifest_path = nil
        input_paths = []
        generated_rules_path = nil
        reviewer = nil
        reviewed_at = nil
        output_path = nil
        parser = OptionParser.new do |opts|
          opts.on('--manifest=FILE', 'Reviewed Sloth provider manifest') { |value| manifest_path = value }
          opts.on('--input=FILE', 'Native Sloth prometheus/v1 input; repeat for each manifest spec') do |value|
            input_paths << value
          end
          opts.on('--generated-rules=FILE', 'Saved Sloth-generated Prometheus rule YAML') do |value|
            generated_rules_path = value
          end
          opts.on('--reviewer=IDENTITY', 'Reviewer attesting the downstream mapping') { |value| reviewer = value }
          opts.on('--reviewed-at=TIMESTAMP', 'Explicit ISO 8601 review timestamp') { |value| reviewed_at = value }
          opts.on('--output=FILE', 'Write the reviewed downstream evidence artifact') { |value| output_path = value }
        end
        parser.parse!(argv)
        abort_usage('missing --manifest') if manifest_path.to_s.empty?
        abort_usage('missing --input') if input_paths.empty?
        abort_usage('missing --generated-rules') if generated_rules_path.to_s.empty?
        abort_usage('missing --reviewer') if reviewer.to_s.empty?
        abort_usage('missing --reviewed-at') if reviewed_at.to_s.empty?
        abort_usage('missing --output') if output_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        evidence = SloRulesEngine::Sloth::DownstreamEvidence::Builder.new.build(
          manifest_path: manifest_path,
          input_paths: input_paths,
          generated_rules_path: generated_rules_path,
          reviewer: reviewer,
          reviewed_at: reviewed_at
        )
        write_json_file(output_path, evidence)
        puts JSON.pretty_generate(evidence)
      rescue SloRulesEngine::Sloth::DownstreamEvidence::ContractError => error
        render_sloth_evidence_error(error, action: 'capture')
      end

      def sloth_evidence_status(argv)
        evidence_path = argv.shift
        abort_usage('missing Sloth downstream evidence path') if evidence_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        status = SloRulesEngine::Sloth::DownstreamEvidence::StatusEvaluator.new.evaluate(evidence_path)
        puts JSON.pretty_generate(status)
        exit 1 unless status.fetch(:fresh)
      rescue SloRulesEngine::Sloth::DownstreamEvidence::ContractError => error
        render_sloth_evidence_error(error, action: 'status')
      end

      private

      def render_sloth_evidence_error(error, action:)
        puts JSON.pretty_generate(
          valid: false,
          provider: 'sloth',
          mode: "sloth_evidence_#{action}",
          error: {
            code: 'invalid_sloth_downstream_evidence',
            message: error.message
          },
          findings: error.findings
        )
        exit 1
      end
    end
  end
end
