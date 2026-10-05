# frozen_string_literal: true

require 'digest'
require 'json'

module SloRulesEngine
  # Shared byte-level policies only. Artifact identities, schema rules, error
  # handling, and finding construction remain with their owning workflows.
  module ArtifactIntegrity
    module Fingerprint
      module_function

      def content(value, fetch_values: false)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(value, fetch_values: fetch_values)))
      end

      def text(value)
        Digest::SHA256.hexdigest(value.to_s)
      end

      # Preserve onboarding's fetch semantics for Hash subclasses; legacy state
      # and release helpers use bracket reads. Array order is never normalized.
      def canonicalize(value, fetch_values: false)
        case value
        when Hash
          value.keys.sort_by(&:to_s).each_with_object({}) do |key, canonical|
            entry = fetch_values ? value.fetch(key) : value[key]
            canonical[key.to_s] = canonicalize(entry, fetch_values: fetch_values)
          end
        when Array
          value.map { |entry| canonicalize(entry, fetch_values: fetch_values) }
        else
          value
        end
      end
    end

    module CredentialScanner
      FORBIDDEN_KEY = /\A(?:api[_-]?key|app[_-]?key|access[_-]?key|secret|password|token|authorization|credential|credentials)\z/i

      module_function

      def paths(value, path)
        case value
        when Hash
          value.flat_map do |key, entry|
            key_path = "#{path}.#{key}"
            matches = key.to_s.match?(FORBIDDEN_KEY) ? [key_path] : []
            matches + paths(entry, key_path)
          end
        when Array
          value.each_with_index.flat_map { |entry, index| paths(entry, "#{path}[#{index}]") }
        else
          []
        end
      end
    end
  end
end
