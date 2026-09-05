# frozen_string_literal: true

require 'json'
require 'optparse'

module SloRulesEngine
  module CLI
    module OnboardingCommands
      def validate_handoff(argv)
        handoff_path = argv.shift
        abort_usage('missing handoff packet path') if handoff_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        result = SloRulesEngine::Onboarding::HandoffValidator.new.validate_file(handoff_path)
        puts JSON.pretty_generate(result.to_h)
        exit 1 unless result.valid?
      end

      def draft_from_handoff(argv)
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
        handoff_path = argv.shift
        abort_usage('missing handoff packet path') if handoff_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        puts SloRulesEngine::Onboarding::HandoffDraftGenerator.new.generate(
          handoff_path,
          service: service,
          owner: owner,
          environment: environment
        )
      rescue SloRulesEngine::Onboarding::HandoffDraftGenerator::DraftError => error
        validation = if error.code == 'invalid_handoff'
                       SloRulesEngine::Onboarding::HandoffValidator.new.validate_file(handoff_path)
                     end
        puts JSON.pretty_generate(
          valid: false,
          handoff_file: handoff_path,
          error: {
            code: error.code,
            message: error.message
          },
          errors: validation&.errors&.map(&:to_h) || []
        )
        exit 1
      end

      def onboarding_summary(argv)
        handoff_dir = nil
        parser = OptionParser.new do |opts|
          opts.on('--handoff-dir=DIR', 'Write per-scope onboarding handoff packets under DIR') { |value| handoff_dir = value }
        end
        parser.parse!(argv)
        index_path = argv.shift
        abort_usage('missing discovery index path') if index_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        summary = SloRulesEngine::Onboarding::SummaryBuilder.new.build(index_path, handoff_dir: handoff_dir)
        puts JSON.pretty_generate(summary)
      end

      def onboarding_artifact_index(argv)
        handoff_dir = nil
        draft_dir = nil
        manifest_dir = nil
        output_path = nil
        providers = []
        parser = OptionParser.new do |opts|
          opts.on('--handoff-dir=DIR', 'Directory containing per-scope onboarding handoff packets') { |value| handoff_dir = value }
          opts.on('--draft-dir=DIR', 'Directory containing reviewed draft definition files named by scope label') { |value| draft_dir = value }
          opts.on('--manifest-dir=DIR', 'Directory containing generated provider manifests and manifest-review reports') { |value| manifest_dir = value }
          opts.on('--provider=PROVIDER', 'Provider manifest/report key to include; may be supplied more than once') { |value| providers << value }
          opts.on('--output=FILE', 'Write the onboarding artifact index to FILE') { |value| output_path = value }
        end
        parser.parse!(argv)
        index_path = argv.shift
        abort_usage('missing discovery index path') if index_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        artifact_index = SloRulesEngine::Onboarding::ArtifactIndexBuilder.new.build(
          index_path,
          handoff_dir: handoff_dir,
          draft_dir: draft_dir,
          manifest_dir: manifest_dir,
          providers: providers
        )
        write_json_file(output_path, artifact_index) if output_path
        puts JSON.pretty_generate(artifact_index)
      end

      def review_handoff(argv)
        accepted_candidate_uids = []
        rejected_candidate_uids = []
        notes = []
        validate_only = false
        parser = OptionParser.new do |opts|
          opts.on('--accept=UID', 'Accept a candidate SLI uid from the handoff packet') { |value| accepted_candidate_uids << value }
          opts.on('--reject=UID', 'Reject a candidate SLI uid from the handoff packet') { |value| rejected_candidate_uids << value }
          opts.on('--note=TEXT', 'Add a review note to the handoff packet') { |value| notes << value }
          opts.on('--validate-only', 'Validate request safety without reading or writing the handoff packet') { validate_only = true }
        end
        parser.parse!(argv)
        handoff_path = argv.shift
        abort_usage('missing handoff packet path') if handoff_path.to_s.empty?
        abort_usage('unexpected arguments') unless argv.empty?

        result = SloRulesEngine::Application::ReviewOnboardingHandoff.new.call(
          {
            'handoff_file' => handoff_path,
            'accept' => accepted_candidate_uids,
            'reject' => rejected_candidate_uids,
            'notes' => notes,
            'validate_only' => validate_only
          },
          context: application_context
        )
        puts JSON.pretty_generate(result.value)
        exit result.exit_status unless result.exit_status.zero?
      rescue SloRulesEngine::Application::InputSafety::Error,
             SloRulesEngine::Application::CommandError => error
        puts JSON.pretty_generate(valid: false, handoff_file: handoff_path, error: { code: error.code, message: error.message })
        exit 1
      end
    end
  end
end
