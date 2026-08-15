# frozen_string_literal: true

require 'digest'
require 'json'

class StructureInventory
  attr_reader :root

  def initialize(root:, policy_path:, contracts_path:)
    @root = File.expand_path(root)
    @policy_path = policy_path
    @contracts_path = contracts_path
  end

  def production_paths
    @production_paths ||= begin
      paths = Dir.glob(File.join(root, 'lib/**/*.rb'))
      executable = File.join(root, 'bin/rules-ctl')
      paths << executable if File.file?(executable)
      relative_paths(paths)
    end
  end

  def boundary_coverage
    assignments = Hash.new { |hash, path| hash[path] = [] }
    boundaries = policy.fetch('boundaries').map do |boundary|
      paths = expand_globs(boundary.fetch('paths')) & production_paths
      paths.each { |path| assignments[path] << boundary.fetch('id') }
      {
        id: boundary.fetch('id'),
        description: boundary.fetch('description'),
        allowed_dependencies: boundary.fetch('allowed_dependencies'),
        file_count: paths.length,
        paths: paths
      }
    end

    unassigned = production_paths.reject { |path| assignments.key?(path) }
    multiply_assigned = assignments.filter_map do |path, boundary_ids|
      next unless boundary_ids.length > 1

      { path: path, boundaries: boundary_ids.sort }
    end.sort_by { |entry| entry.fetch(:path) }

    {
      valid: unassigned.empty? && multiply_assigned.empty?,
      unassigned: unassigned,
      multiply_assigned: multiply_assigned,
      boundaries: boundaries
    }
  end

  def dependency_evaluation
    rules = policy.fetch('rules').map { |rule| evaluate_dependency_rule(rule) }
    {
      valid: rules.all? { |rule| rule.fetch(:valid) },
      reference_count: rules.sum { |rule| rule.fetch(:actual_references).sum { |ref| ref.fetch(:occurrences) } },
      rules: rules
    }
  end

  def contract_evaluation
    expected = contracts
    actual = {
      command_ids: command_ids,
      command_registry_sha256: digest(command_registry.to_h),
      command_catalog_sha256: digest(command_catalog),
      schema_ids: schema_ids,
      use_cases: documented_use_cases
    }
    errors = []

    compare_contract(errors, 'command IDs', expected.fetch('command_ids'), actual.fetch(:command_ids))
    compare_contract(
      errors,
      'command registry digest',
      expected.fetch('command_registry_sha256'),
      actual.fetch(:command_registry_sha256)
    )
    compare_contract(
      errors,
      'command catalog digest',
      expected.fetch('command_catalog_sha256'),
      actual.fetch(:command_catalog_sha256)
    )
    compare_contract(errors, 'schema IDs', expected.fetch('schema_ids'), actual.fetch(:schema_ids))

    expected_use_cases = expected.fetch('use_cases').map { |entry| entry.slice('id', 'title') }
    compare_contract(errors, 'documented use cases', expected_use_cases, actual.fetch(:use_cases))
    expected.fetch('use_cases').each do |use_case|
      use_case.fetch('tests').each do |test_path|
        errors << "#{use_case.fetch('id')} references missing test #{test_path}" unless File.file?(File.join(root, test_path))
      end
    end

    { valid: errors.empty?, errors: errors, actual: actual }
  end

  def report
    boundaries = boundary_coverage
    dependencies = dependency_evaluation
    contract_status = contract_evaluation
    production = file_summary(production_paths)
    tests = file_summary(relative_paths(Dir.glob(File.join(root, 'test/**/*.rb'))))

    {
      schema_version: 'structure-report/v1',
      production: production,
      tests: tests,
      composition: {
        root_require_count: File.readlines(File.join(root, 'lib/slo_rules_engine.rb')).count do |line|
          line.match?(/^require_relative /)
        end
      },
      commands: {
        count: command_ids.length,
        ids: command_ids,
        registry_sha256: contract_status.dig(:actual, :command_registry_sha256),
        catalog_sha256: contract_status.dig(:actual, :command_catalog_sha256),
        module_count: command_module_paths.length,
        module_paths: command_module_paths
      },
      schema_contracts: {
        count: schema_ids.length,
        ids: schema_ids,
        command_ref_count: command_schema_refs.length,
        command_refs: command_schema_refs
      },
      use_cases: {
        count: documented_use_cases.length,
        ids: documented_use_cases.map { |use_case| use_case.fetch('id') }
      },
      boundaries: boundaries,
      dependency_debt: dependencies,
      contracts: {
        valid: contract_status.fetch(:valid),
        errors: contract_status.fetch(:errors)
      }
    }
  end

  private

  def policy
    @policy ||= JSON.parse(File.read(@policy_path))
  end

  def contracts
    @contracts ||= JSON.parse(File.read(@contracts_path))
  end

  def command_registry
    load_cli
    SloRulesEngine::CLI::CommandRegistry.default
  end

  def command_catalog
    load_cli
    SloRulesEngine::CLI::CommandCatalog.to_h
  end

  def load_cli
    return if defined?(SloRulesEngine::CLI::CommandRegistry)

    require File.join(root, 'lib/slo_rules_engine/cli')
  end

  def command_ids
    @command_ids ||= command_registry.definitions.map(&:id)
  end

  def command_module_paths
    @command_module_paths ||= relative_paths(Dir.glob(File.join(root, 'lib/slo_rules_engine/cli/*_commands.rb')))
  end

  def schema_ids
    @schema_ids ||= production_paths.filter { |path| path.start_with?('lib/') }.flat_map do |path|
      File.read(File.join(root, path)).scan(%r{slo-rules-engine/[a-z0-9._/-]+/v[0-9]+})
    end.uniq.sort
  end

  def command_schema_refs
    @command_schema_refs ||= command_registry.definitions.flat_map do |definition|
      definition.schemas.values.map { |schema| schema.fetch(:ref) }
    end.uniq.sort
  end

  def documented_use_cases
    @documented_use_cases ||= File.readlines(File.join(root, 'docs/use-cases.md')).filter_map do |line|
      match = line.match(/^## Use Case (\d+): (.+)$/)
      next unless match

      { 'id' => format('UC-%02d', match[1].to_i), 'title' => match[2].strip }
    end
  end

  def evaluate_dependency_rule(rule)
    source_paths = expand_globs(rule.fetch('source_paths'))
    excluded_paths = expand_globs(rule.fetch('exclude_paths', []))
    source_paths -= excluded_paths
    pattern = Regexp.new(rule.fetch('forbidden_constant_pattern'))
    counts = Hash.new(0)

    source_paths.each do |path|
      File.read(File.join(root, path)).scan(pattern).each do |match|
        constant = match.is_a?(Array) ? match.join : match
        counts[[path, constant]] += 1
      end
    end

    actual = counts.map do |(path, constant), occurrences|
      { path: path, constant: constant, occurrences: occurrences }
    end.sort_by { |reference| [reference.fetch(:path), reference.fetch(:constant)] }
    allowed = rule.fetch('allowed_references').map do |reference|
      {
        path: reference.fetch('path'),
        constant: reference.fetch('constant'),
        occurrences: reference.fetch('occurrences')
      }
    end.sort_by { |reference| [reference.fetch(:path), reference.fetch(:constant)] }

    {
      id: rule.fetch('id'),
      intent: rule.fetch('intent'),
      removal_packet: rule['removal_packet'],
      valid: actual == allowed,
      allowed_references: rule.fetch('allowed_references'),
      actual_references: actual,
      unexpected_references: actual - allowed,
      stale_allowlist_references: allowed - actual
    }
  end

  def expand_globs(globs)
    relative_paths(globs.flat_map { |glob| Dir.glob(File.join(root, glob)) }.select { |path| File.file?(path) })
  end

  def relative_paths(paths)
    paths.map { |path| path.delete_prefix("#{root}/") }.uniq.sort
  end

  def file_summary(paths)
    files = paths.map do |path|
      content = File.read(File.join(root, path))
      {
        path: path,
        lines: content.lines.length,
        methods: content.scan(/^\s*def\s+/).length,
        types: content.scan(/^\s*(?:class|module)\s+/).length
      }
    end

    {
      file_count: paths.length,
      line_count: files.sum { |file| file.fetch(:lines) },
      hotspots: files.sort_by { |file| [-file.fetch(:lines), file.fetch(:path)] }.first(10)
    }
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
  end

  def canonicalize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, entry), canonical|
        canonical[key.to_s] = canonicalize(entry)
      end.sort.to_h
    when Array
      value.map { |entry| canonicalize(entry) }
    when Symbol
      value.to_s
    else
      value
    end
  end

  def compare_contract(errors, label, expected, actual)
    return if expected == actual

    errors << "#{label} changed: expected #{expected.inspect}, got #{actual.inspect}"
  end
end
