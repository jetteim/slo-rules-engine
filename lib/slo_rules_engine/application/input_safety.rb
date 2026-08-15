# frozen_string_literal: true

require 'pathname'

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

        def validate_lexical_paths!(entries)
          entries.compact.each do |entry|
            validate_lexical!(
              entry.fetch(:path),
              field: entry.fetch(:field),
              extensions: entry[:extensions]
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

        private

        def validate_lexical!(path, field:, extensions: nil)
          unsafe_path!(field, 'not_a_string') unless path.is_a?(String)
          unsafe_path!(field, 'empty') if path.empty?
          unsafe_path!(field, 'too_long') if path.bytesize > MAX_PATH_BYTES
          unsafe_path!(field, 'control_character') if path.match?(CONTROL_CHARACTERS)
          if @confined && extensions && !extensions.include?(File.extname(path).downcase)
            unsafe_path!(field, 'unexpected_extension')
          end
          return unless @confined

          unsafe_path!(field, 'absolute_path') if Pathname.new(path).absolute?
          unsafe_path!(field, 'path_traversal') if path.match?(TRAVERSAL_SEGMENT)
          unsafe_path!(field, 'pre_encoded_path') if path.match?(PREENCODED_SEGMENT)
        end

        def resolve_existing(path, field:)
          resolved = File.realpath(File.expand_path(path, @workspace_root))
          ensure_contained!(resolved, field)
          resolved
        end

        def ensure_contained!(resolved, field)
          return unless @confined

          root = File.realpath(@workspace_root)
          return if resolved == root || resolved.start_with?("#{root}#{File::SEPARATOR}")

          unsafe_path!(field, 'symlink_escape')
        end

        def unsafe_path!(field, reason)
          raise Error.new(
            'unsafe_agent_input_path',
            'agent input path is not allowed',
            field: field,
            reason: reason
          )
        end
      end
    end
  end
end
