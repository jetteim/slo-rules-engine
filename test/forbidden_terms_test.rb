# frozen_string_literal: true

require 'minitest/autorun'

class ForbiddenTermsTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_repository_does_not_contain_internal_terms
    terms = File.readlines(File.join(ROOT, '.forbidden-terms'), chomp: true).reject(&:empty?)
    files = Dir.glob(File.join(ROOT, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }
    files.reject! { |path| path.include?('/.git/') || path.end_with?('/.forbidden-terms') }

    findings = []
    files.each do |path|
      content = File.read(path)
      terms.each do |term|
        findings << "#{path.sub("#{ROOT}/", '')}: #{term}" if content.downcase.include?(term.downcase)
      end
    end

    assert_empty findings
  end

  def test_private_artifact_path_scanner_flags_nonpublic_analysis_outputs
    findings = private_artifact_path_findings([
      File.join(ROOT, 'artifacts', 'service.private.json'),
      File.join(ROOT, 'tmp', 'raw-inventory.json'),
      File.join(ROOT, 'tmp', 'source-snapshot.json'),
      File.join(ROOT, 'tmp', 'nonpublic-model.md'),
      File.join(ROOT, 'examples', 'services', 'checkout.rb')
    ])

    assert_equal(
      [
        'artifacts/service.private.json',
        'tmp/raw-inventory.json',
        'tmp/source-snapshot.json',
        'tmp/nonpublic-model.md'
      ],
      findings
    )
  end

  def test_repository_does_not_contain_private_analysis_artifacts
    files = Dir.glob(File.join(ROOT, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }
    files.reject! { |path| path.include?('/.git/') }

    assert_empty private_artifact_path_findings(files)
  end

  private

  def private_artifact_path_findings(files)
    forbidden_patterns = [
      /\.private\./i,
      /raw-inventory/i,
      /source-snapshot/i,
      /nonpublic/i
    ]

    files.each_with_object([]) do |path, findings|
      relative = path.sub("#{ROOT}/", '')
      findings << relative if forbidden_patterns.any? { |pattern| relative.match?(pattern) }
    end
  end
end
