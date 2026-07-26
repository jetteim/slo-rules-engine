# frozen_string_literal: true

require 'minitest/autorun'

class UseCasesDocumentationTest < Minitest::Test
  USE_CASES_PATH = File.expand_path('../docs/use-cases.md', __dir__)
  README_PATH = File.expand_path('../README.md', __dir__)

  def test_every_use_case_names_expected_outputs_and_intent_boundary
    sections.each do |heading, body|
      assert_includes body, '**What to expect:**', "#{heading} must state concrete expected outputs"
      assert_match(
        /\*\*(Intent preserved|Safety boundary):\*\*/,
        body,
        "#{heading} must state the intent or safety boundary"
      )
    end
  end

  def test_output_map_covers_every_provider_and_operation_journals
    document = File.read(USE_CASES_PATH)

    assert_includes document, '| `datadog` |'
    assert_includes document, '| `prometheus_stack` |'
    assert_includes document, '| `sloth` |'
    assert_includes document, '| Operation journal |'
  end

  def test_usage_covers_durable_file_execution_results
    document = File.read(USE_CASES_PATH)
    readme = File.read(README_PATH)

    assert_operator document.scan('--journal-dir').length, :>=, 3
    assert_includes document, 'ProviderStateResult'
    assert_includes document, 'partial_failure'
    assert_includes readme, '--journal-dir=./work/journals'
    assert_includes readme, 'ProviderStateResult'
  end

  private

  def sections
    document = File.read(USE_CASES_PATH)
    matches = document.enum_for(:scan, /^## Use Case \d+: .+$/).map { Regexp.last_match }
    matches.each_with_index.to_h do |match, index|
      finish = matches.fetch(index + 1, nil)&.begin(0) || document.length
      [match[0], document[match.end(0)...finish]]
    end
  end
end
