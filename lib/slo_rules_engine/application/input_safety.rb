# frozen_string_literal: true

require 'pathname'
require 'uri'

module SloRulesEngine
  module Application
    module InputSafety
      class Error < ArgumentError
        attr_reader :code, :details

        def initialize(code, message, details = {})
          @code = code
          @details = details
          super(message)
        end
      end

      class PathPolicy
        MAX_PATH_BYTES = 4_096
        AGENT_MAX_FILE_BYTES = 1_048_576
        AGENT_MAX_TOTAL_BYTES = 4_194_304
        MAX_FILES = 100
        CONTROL_CHARACTERS = /[\u0000-\u001F\u007F]/
        TRAVERSAL_SEGMENT = %r{(?:\A|[/\\])\.\.(?:[/\\]|\z)}
        PREENCODED_SEGMENT = /%[0-9A-Fa-f]{2}/

        def self.agent(workspace_root: Dir.pwd)
          new(
            workspace_root: workspace_root,
            confined: true,
            max_file_bytes: AGENT_MAX_FILE_BYTES,
            max_total_bytes: AGENT_MAX_TOTAL_BYTES
          )
        end

        def self.human(workspace_root: Dir.pwd)
          new(workspace_root: workspace_root, confined: false)
        end

        def initialize(workspace_root:, confined:, max_file_bytes: nil, max_total_bytes: nil)
          @workspace_root = File.expand_path(workspace_root)
          @confined = confined
          @max_file_bytes = max_file_bytes
          @max_total_bytes = max_total_bytes
        end

        def confined?
          @confined
        end

        def validate_lexical_paths!(entries)
          entries.compact.each do |entry|
            validate_lexical!(
              entry.fetch(:path),
              field: entry.fetch(:field),
              extensions: entry[:extensions],
              access: entry.fetch(:access, :read)
            )
          end
        end

        def resolve_read_files(paths, field:, extensions:, prevalidated: false)
          unless paths.is_a?(Array) && paths.length.between?(1, MAX_FILES)
            raise Error.new(
              'invalid_agent_input_path_count',
              "#{field} must contain between 1 and #{MAX_FILES} paths",
              field: field,
              minimum: 1,
              maximum: MAX_FILES
            )
          end
          unless prevalidated
            validate_lexical_paths!(
              paths.map { |path| { path: path, field: field, extensions: extensions } }
            )
          end

          resolved = paths.map do |path|
            resolved_path = resolve_existing(path, field: field)
            unless File.file?(resolved_path)
              unsafe_path!(field, 'not_regular_file')
            end
            size = File.size(resolved_path)
            if @max_file_bytes && size > @max_file_bytes
              raise Error.new(
                'agent_input_file_too_large',
                'agent input file exceeds the per-file byte limit',
                field: field,
                maximum_bytes: @max_file_bytes
              )
            end
            [resolved_path, size]
          end
          total_bytes = resolved.sum { |_path, size| size }
          if @max_total_bytes && total_bytes > @max_total_bytes
            raise Error.new(
              'agent_input_files_too_large',
              'agent input files exceed the aggregate byte limit',
              field: field,
              maximum_bytes: @max_total_bytes
            )
          end

          resolved.map(&:first)
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR => error
          raise Error.new(
            'unreadable_agent_input_file',
            'agent input file cannot be read',
            field: field,
            reason: error.class.name
          )
        end

        def resolve_read_file(path, field:, extensions:, prevalidated: false)
          resolve_read_files(
            [path],
            field: field,
            extensions: extensions,
            prevalidated: prevalidated
          ).fetch(0)
        end

        def resolve_read_root(path, field:, prevalidated: false)
          validate_lexical!(path, field: field) unless prevalidated
          expanded = File.expand_path(path, @workspace_root)
          ancestor = expanded
          ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.dirname(ancestor) == ancestor
          resolved_ancestor = File.realpath(ancestor)
          ensure_contained!(resolved_ancestor, field)
          unsafe_path!(field, 'not_directory') if File.exist?(expanded) && !File.directory?(expanded)
          expanded
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => error
          raise Error.new(
            'unreadable_agent_input_path',
            'agent input path cannot be resolved',
            field: field,
            reason: error.class.name
          )
        end

        def resolve_write_root(path, field:, prevalidated: false)
          validate_lexical!(path, field: field, access: :write) unless prevalidated
          expanded = File.expand_path(path, @workspace_root)
          resolved = resolve_existing_or_ancestor(expanded)
          ensure_contained!(resolved, field, access: :write)
          unsafe_path!(field, 'not_directory', access: :write) if File.exist?(expanded) && !File.directory?(expanded)
          expanded
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => error
          raise Error.new(
            'unresolvable_agent_output_path',
            'agent output path cannot be resolved safely',
            field: field,
            reason: error.class.name
          )
        end

        def resolve_write_file(path, field:, extensions:, prevalidated: false)
          validate_lexical!(path, field: field, extensions: extensions, access: :write) unless prevalidated
          expanded = File.expand_path(path, @workspace_root)
          resolved = if File.exist?(expanded) || File.symlink?(expanded)
                       File.realpath(expanded)
                     else
                       resolve_existing_or_ancestor(File.dirname(expanded))
                     end
          ensure_contained!(resolved, field, access: :write)
          unsafe_path!(field, 'not_regular_file', access: :write) if File.exist?(expanded) && !File.file?(expanded)
          expanded
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR => error
          raise Error.new(
            'unresolvable_agent_output_path',
            'agent output path cannot be resolved safely',
            field: field,
            reason: error.class.name
          )
        end

        def resolve_write_child(root, segments, field:)
          return File.join(root, *segments) unless @confined

          Array(segments).each do |segment|
            unsafe_path!(field, 'unsafe_generated_segment', access: :write) unless safe_child_segment?(segment)
          end
          expanded_root = File.expand_path(root)
          candidate = File.join(expanded_root, *segments)
          canonical_root = canonical_future_path(expanded_root)
          canonical_candidate = canonical_future_path(candidate)
          ensure_contained!(canonical_candidate, field, access: :write)
          unless canonical_candidate.start_with?("#{canonical_root}#{File::SEPARATOR}")
            unsafe_path!(field, 'generated_path_escape', access: :write)
          end
          unsafe_path!(field, 'not_regular_file', access: :write) if File.exist?(candidate) && !File.file?(candidate)
          candidate
        rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR => error
          raise Error.new(
            'unresolvable_agent_output_path',
            'agent output path cannot be resolved safely',
            field: field,
            reason: error.class.name
          )
        end

        private

        def validate_lexical!(path, field:, extensions: nil, access: :read)
          unsafe_path!(field, 'not_a_string', access: access) unless path.is_a?(String)
          unsafe_path!(field, 'empty', access: access) if path.empty?
          unsafe_path!(field, 'too_long', access: access) if path.bytesize > MAX_PATH_BYTES
          unsafe_path!(field, 'control_character', access: access) if path.match?(CONTROL_CHARACTERS)
          if @confined && extensions && !extensions.include?(File.extname(path).downcase)
            unsafe_path!(field, 'unexpected_extension', access: access)
          end
          return unless @confined

          unsafe_path!(field, 'absolute_path', access: access) if Pathname.new(path).absolute?
          unsafe_path!(field, 'path_traversal', access: access) if path.match?(TRAVERSAL_SEGMENT)
          unsafe_path!(field, 'pre_encoded_path', access: access) if path.match?(PREENCODED_SEGMENT)
        end

        def resolve_existing(path, field:)
          resolved = File.realpath(File.expand_path(path, @workspace_root))
          ensure_contained!(resolved, field)
          resolved
        end

        def resolve_existing_or_ancestor(path)
          ancestor = path
          ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor) || File.dirname(ancestor) == ancestor
          File.realpath(ancestor)
        end

        def canonical_future_path(path)
          ancestor = path
          ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor) || File.dirname(ancestor) == ancestor
          resolved_ancestor = File.realpath(ancestor)
          suffix = Pathname.new(path).relative_path_from(Pathname.new(ancestor)).to_s
          File.expand_path(suffix, resolved_ancestor)
        end

        def safe_child_segment?(segment)
          segment.is_a?(String) && !segment.empty? && segment.bytesize <= MAX_PATH_BYTES &&
            !%w[. ..].include?(segment) && !segment.match?(CONTROL_CHARACTERS) &&
            !segment.match?(%r{[/\\]}) && !segment.match?(PREENCODED_SEGMENT)
        end

        def ensure_contained!(resolved, field, access: :read)
          return unless @confined

          root = File.realpath(@workspace_root)
          return if resolved == root || resolved.start_with?("#{root}#{File::SEPARATOR}")

          unsafe_path!(field, 'symlink_escape', access: access)
        end

        def unsafe_path!(field, reason, access: :read)
          output = access == :write
          raise Error.new(
            output ? 'unsafe_agent_output_path' : 'unsafe_agent_input_path',
            output ? 'agent output path is not allowed' : 'agent input path is not allowed',
            field: field,
            reason: reason
          )
        end
      end

      class NetworkPolicy
        MAX_HOSTS = 20
        MAX_HOST_BYTES = 253
        HOST_LABEL = /\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\z/

        def self.agent
          new(confined: true)
        end

        def self.human
          new(confined: false)
        end

        def initialize(confined:)
          @confined = confined
        end

        def confined?
          @confined
        end

        def validate_base_url!(value, field:, allowed_hosts: [])
          unsafe_url!(field, 'not_a_string') unless value.is_a?(String)
          unsafe_url!(field, 'control_character') if value.match?(PathPolicy::CONTROL_CHARACTERS)
          unsafe_url!(field, 'pre_encoded_url') if value.match?(PathPolicy::PREENCODED_SEGMENT)

          uri = URI.parse(value)
          unsafe_url!(field, 'unsupported_scheme') unless %w[http https].include?(uri.scheme)
          unsafe_url!(field, 'missing_host') if uri.host.to_s.empty?
          unsafe_url!(field, 'credentials_in_url') if uri.user || uri.password
          unsafe_url!(field, 'query_not_allowed') if uri.query
          unsafe_url!(field, 'fragment_not_allowed') if uri.fragment
          unsafe_url!(field, 'base_path_not_allowed') unless uri.path.to_s.empty? || uri.path == '/'
          uri.port

          hosts = validate_allowed_hosts!(allowed_hosts, field: 'allowed_hosts')
          if confined? && !hosts.include?(uri.host.downcase)
            unsafe_url!(field, 'host_not_allowlisted')
          end

          uri.to_s.sub(%r{/\z}, '')
        rescue URI::InvalidURIError, URI::InvalidComponentError
          unsafe_url!(field, 'invalid_url')
        end

        def validate_allowed_hosts!(values, field:)
          hosts = Array(values)
          if confined? && !hosts.length.between?(1, MAX_HOSTS)
            raise Error.new(
              'invalid_agent_host_allowlist',
              "#{field} must contain between 1 and #{MAX_HOSTS} exact hosts",
              field: field,
              minimum: 1,
              maximum: MAX_HOSTS
            )
          end

          hosts.map do |host|
            invalid_host!(field) unless valid_host?(host)
            invalid_host!(field) if host.include?('*') || host.match?(PathPolicy::PREENCODED_SEGMENT)

            host.downcase
          end.uniq
        end

        private

        def valid_host?(host)
          host.is_a?(String) && !host.empty? && host.bytesize <= MAX_HOST_BYTES &&
            host.split('.').all? { |label| label.match?(HOST_LABEL) }
        end

        def unsafe_url!(field, reason)
          raise Error.new(
            'unsafe_agent_endpoint',
            'agent provider endpoint is not allowed',
            field: field,
            reason: reason
          )
        end

        def invalid_host!(field)
          raise Error.new(
            'invalid_agent_host_allowlist',
            'agent host allowlist must contain exact DNS names or IPv4 literals without wildcards',
            field: field
          )
        end
      end

      class ResourcePolicy
        KINDS = %w[unknown latency errors availability traffic freshness user_journey saturation].freeze
        PROMETHEUS_METRIC = /\A[a-zA-Z_:][a-zA-Z0-9_:]*\z/
        DATADOG_METRIC = /\A[a-zA-Z][a-zA-Z0-9_.]*\z/
        SCOPE_KEY = /\A[a-zA-Z_][a-zA-Z0-9_.-]*\z/
        PROMETHEUS_SCOPE_KEY = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/
        SCOPE_VALUE = /\A[a-zA-Z0-9_.:-]+\z/
        HOST = /\A[a-zA-Z0-9][a-zA-Z0-9.:-]*\z/
        MAX_RESOURCE_BYTES = 512
        MAX_QUERY_BYTES = 16_384
        MAX_SELECTORS = 20
        MAX_WINDOW_SECONDS = 31 * 24 * 60 * 60

        def validate_metric!(value, provider:, field: 'metric')
          pattern = provider == 'datadog' ? DATADOG_METRIC : PROMETHEUS_METRIC
          validate_resource!(value, field: field, pattern: pattern)
        end

        def valid_metric?(value, provider:)
          validate_metric!(value, provider: provider)
          true
        rescue Error
          false
        end

        def validate_kind!(value)
          return value if KINDS.include?(value)

          invalid_resource!('kind', 'unsupported_value')
        end

        def validate_query!(value, field: 'query')
          return nil if value.nil?

          invalid_resource!(field, 'not_a_string') unless value.is_a?(String)
          invalid_resource!(field, 'empty') if value.empty?
          invalid_resource!(field, 'too_long') if value.bytesize > MAX_QUERY_BYTES
          invalid_resource!(field, 'control_character') if value.match?(PathPolicy::CONTROL_CHARACTERS)
          value
        end

        def validate_scope!(service:, selectors:, host:, provider:)
          validate_resource!(service, field: 'service', pattern: SCOPE_VALUE) unless service.to_s.empty?
          validate_resource!(host, field: 'host', pattern: HOST) unless host.to_s.empty?
          unless selectors.is_a?(Hash) && selectors.length <= MAX_SELECTORS
            invalid_resource!('selectors', 'too_many_entries')
          end
          selectors.each do |key, value|
            key_pattern = provider == 'datadog' ? SCOPE_KEY : PROMETHEUS_SCOPE_KEY
            validate_resource!(key, field: 'selector_key', pattern: key_pattern)
            validate_resource!(value, field: 'selector_value', pattern: SCOPE_VALUE)
          end
          if service.to_s.empty? && selectors.empty? && host.to_s.empty?
            invalid_resource!('scope', 'missing')
          end
          if provider == 'datadog' && !host.to_s.empty? && (!service.to_s.empty? || !selectors.empty?)
            invalid_resource!('scope', 'datadog_host_scope_conflict')
          end
          if provider != 'datadog' && !host.to_s.empty?
            invalid_resource!('host', 'unsupported_for_provider')
          end
          true
        end

        def validate_window!(from:, to:)
          [[:from, from], [:to, to]].each do |field, value|
            next if value.nil?
            invalid_resource!(field.to_s, 'not_nonnegative_integer') unless value.is_a?(Integer) && value >= 0
          end
          return true if from.nil? || to.nil?

          invalid_resource!('window', 'reversed') if from > to
          invalid_resource!('window', 'too_large') if to - from > MAX_WINDOW_SECONDS
          true
        end

        private

        def validate_resource!(value, field:, pattern:)
          invalid_resource!(field, 'not_a_string') unless value.is_a?(String)
          invalid_resource!(field, 'empty') if value.empty?
          invalid_resource!(field, 'too_long') if value.bytesize > MAX_RESOURCE_BYTES
          invalid_resource!(field, 'control_character') if value.match?(PathPolicy::CONTROL_CHARACTERS)
          invalid_resource!(field, 'pre_encoded_value') if value.match?(PathPolicy::PREENCODED_SEGMENT)
          invalid_resource!(field, 'invalid_characters') unless value.match?(pattern)
          value
        end

        def invalid_resource!(field, reason)
          raise Error.new(
            'unsafe_agent_resource_identifier',
            'agent resource identifier is not allowed',
            field: field,
            reason: reason
          )
        end
      end
    end
  end
end
