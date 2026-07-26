# frozen_string_literal: true

require 'json'
require 'yaml'

module SloRulesEngine
  module ProviderState
    class ManagedFileVerifier
      def verify(entry, checked_at:)
        path = Value.fetch(Value.fetch(entry, :desired), :path)
        Value.require_presence!('entry.desired.path', path)
        expected = expected_state(entry)
        actual = actual_state(entry, path)
        status = expected.fetch(:fingerprint) == actual.fetch(:fingerprint) ? 'succeeded' : 'failed'

        {
          status: status,
          checked_at: checked_at,
          path: path,
          expected: expected,
          actual: actual,
          findings: status == 'succeeded' ? [] : [failure_finding(entry, path, expected, actual)]
        }
      end

      private

      def expected_state(entry)
        return state(present: false) if Value.fetch(entry, :action) == 'delete'

        state(present: true, content: desired_content(entry))
      end

      def actual_state(entry, path)
        return state(present: false) unless File.exist?(path)

        state(present: true, content: read_content(entry, path))
      rescue JSON::ParserError, Psych::Exception, SystemCallError
        state(present: true, readable: false)
      end

      def desired_content(entry)
        desired = Value.fetch(entry, :desired)
        case Value.fetch(entry, :target)
        when 'manifest_file'
          Value.fetch(desired, :manifest)
        when 'external_generator_input'
          Value.fetch(desired, :spec)
        when /\Aprometheus_stack\./
          Value.fetch(desired, :resource)
        else
          raise ContractError.new('entry.target', 'is not an engine-owned managed file')
        end
      end

      def read_content(entry, path)
        if Value.fetch(entry, :target) == 'manifest_file'
          JSON.parse(File.read(path))
        else
          YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
        end
      end

      def state(present:, content: nil, readable: true)
        identity = { present: present }
        identity[:readable] = false if present && !readable
        identity[:content] = content if present && readable
        {
          present: present,
          readable: present ? readable : nil,
          fingerprint: Fingerprint.content(identity)
        }.compact
      end

      def failure_finding(entry, path, expected, actual)
        code, message = failure(entry, actual)
        {
          code: code,
          severity: 'error',
          message: message,
          path: path,
          expected_fingerprint: expected.fetch(:fingerprint),
          actual_fingerprint: actual.fetch(:fingerprint)
        }
      end

      def failure(entry, actual)
        if Value.fetch(entry, :action) == 'delete'
          return [
            'managed_file_present_after_delete',
            'managed file is still present after delete'
          ]
        end
        unless actual.fetch(:present)
          return [
            'managed_file_missing_after_write',
            'managed file is absent after write'
          ]
        end
        unless actual.fetch(:readable, true)
          return [
            'managed_file_unreadable_after_write',
            'managed file cannot be parsed after write'
          ]
        end

        [
          'managed_file_content_mismatch',
          'managed file content does not match the live plan after write'
        ]
      end
    end
  end
end
