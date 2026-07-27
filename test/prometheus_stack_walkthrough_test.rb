# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'yaml'

class PrometheusStackWalkthroughTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_reviewed_bundle_walkthrough_covers_complete_managed_file_lifecycle
    definition = File.join(ROOT, 'examples', 'prometheus-stack', 'reviewed-checkout.rb')

    Dir.mktmpdir do |dir|
      generated_dir = File.join(dir, 'generated')
      managed_dir = File.join(dir, 'managed')
      journal_dir = File.join(dir, 'journals')

      validation = json_command('validate', definition)
      assert_equal true, validation.fetch(0).fetch('valid')

      generated = json_command(
        'generate',
        '--provider=prometheus_stack',
        "--output-dir=#{generated_dir}",
        definition
      )
      assert_equal 'checkout-api', generated.fetch(0).fetch('service')

      manifest_path = File.join(generated_dir, 'checkout-api', 'prometheus_stack', 'manifest.json')
      report_path = File.join(generated_dir, 'manifest-review', 'prometheus_stack.json')
      review = json_command(
        'manifest-review',
        '--provider=prometheus_stack',
        "--manifest=#{manifest_path}",
        "--report=#{report_path}"
      )
      assert_equal true, review.fetch('valid')
      assert_equal true, review.fetch('saved_report').fetch('fresh')

      dry_run = json_command(
        'apply',
        '--provider=prometheus_stack',
        '--dry-run',
        "--output-dir=#{managed_dir}",
        "--manifest=#{manifest_path}"
      ).fetch(0)
      assert_equal %w[write write write write], actions(dry_run)
      dry_run.fetch('operations').each do |operation|
        refute File.exist?(operation.fetch('payload').fetch('path'))
      end

      applied = json_command(
        'apply',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{managed_dir}",
        "--journal-dir=#{journal_dir}",
        "--manifest=#{manifest_path}",
        "--review-report=#{report_path}"
      ).fetch(0)
      assert_equal %w[write write write write], actions(applied)
      assert_equal 'succeeded', applied.dig('execution', 'result', 'status')
      assert_equal 'succeeded', applied.dig('execution', 'result', 'verification', 'status')
      assert_equal 4,
                   applied.dig('execution', 'result', 'verification', 'summary', 'succeeded_resources')
      assert File.exist?(applied.dig('execution', 'operation_journal', 'path'))

      resources = applied.fetch('operations').to_h do |operation|
        [operation.fetch('target'), operation.fetch('payload').fetch('path')]
      end
      prometheus_rule_path = resources.fetch('prometheus_stack.prometheus_rule')
      grafana_path = resources.fetch('prometheus_stack.grafana_dashboard')
      route_path = resources.fetch('prometheus_stack.alertmanager_route_intent')

      prometheus_rule = load_yaml(prometheus_rule_path)
      assert_equal [1, 5, 2, 2],
                   prometheus_rule.fetch('spec').fetch('groups').map { |group| group.fetch('rules').length }

      dashboard_resource = load_yaml(grafana_path)
      dashboard = JSON.parse(dashboard_resource.fetch('data').fetch('checkout-api-slo.json'))
      assert_equal 6, dashboard.fetch('panels').length

      route_intent = load_yaml(route_path)
      assert_equal true, route_intent.fetch('receiver_contract').fetch('configuration_required')
      refute_includes route_intent.fetch('receiver_contract'), 'url'

      clean_diff = json_command(
        'diff',
        '--provider=prometheus_stack',
        "--output-dir=#{managed_dir}",
        "--manifest=#{manifest_path}"
      ).fetch(0)
      assert_equal %w[noop noop noop noop], actions(clean_diff)

      imported = json_command(
        'import',
        '--provider=prometheus_stack',
        "--output-dir=#{managed_dir}",
        "--manifest=#{manifest_path}"
      ).fetch(0)
      assert_equal 'manifest_bundle', imported.fetch('source')
      assert_equal [], imported.fetch('findings')
      assert_equal 3, imported.fetch('state').fetch('bundle_files').length

      stale_rule = load_yaml(prometheus_rule_path)
      stale_rule.fetch('spec').fetch('groups').fetch(0).fetch('rules').fetch(0)['expr'] = 'stale_expr'
      File.write(prometheus_rule_path, YAML.dump(stale_rule))

      drift = json_command(
        'diff',
        '--provider=prometheus_stack',
        "--output-dir=#{managed_dir}",
        "--manifest=#{manifest_path}"
      ).fetch(0)
      assert_equal %w[noop update noop noop], actions(drift)

      repaired = json_command(
        'apply',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{managed_dir}",
        "--journal-dir=#{journal_dir}",
        "--manifest=#{manifest_path}",
        "--review-report=#{report_path}"
      ).fetch(0)
      assert_equal %w[noop write noop noop], actions(repaired)
      assert_equal 'succeeded', repaired.dig('execution', 'result', 'status')
      assert_equal 'succeeded', repaired.dig('execution', 'result', 'verification', 'status')
      assert_equal 1,
                   repaired.dig('execution', 'result', 'verification', 'summary', 'succeeded_resources')
      refute_equal 'stale_expr',
                   load_yaml(prometheus_rule_path).fetch('spec').fetch('groups').fetch(0).fetch('rules').fetch(0).fetch('expr')

      pruned = json_command(
        'prune',
        '--provider=prometheus_stack',
        '--confirm',
        "--output-dir=#{managed_dir}",
        "--journal-dir=#{journal_dir}",
        "--manifest=#{manifest_path}",
        "--review-report=#{report_path}"
      ).fetch(0)
      assert_equal %w[delete delete delete delete], actions(pruned)
      assert_equal 'succeeded', pruned.dig('execution', 'result', 'status')
      assert_equal 'succeeded', pruned.dig('execution', 'result', 'verification', 'status')
      assert pruned.dig('execution', 'result', 'verification', 'resources').all? do |resource|
        resource.dig('actual', 'present') == false
      end
      pruned.fetch('operations').each do |operation|
        refute File.exist?(operation.fetch('payload').fetch('path'))
      end
    end
  end

  private

  def actions(plan)
    plan.fetch('operations').map { |operation| operation.fetch('action') }
  end

  def json_command(*argv)
    stdout, stderr, status = Open3.capture3('ruby', File.join(ROOT, 'bin', 'rules-ctl'), *argv)
    assert status.success?, stderr.empty? ? stdout : stderr
    JSON.parse(stdout)
  end

  def load_yaml(path)
    YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
  end
end
