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
end
