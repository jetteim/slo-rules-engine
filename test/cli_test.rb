# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tempfile'

class CLITest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_generate_fails_when_provider_binding_is_missing
    Tempfile.create(['missing-binding', '.rb']) do |file|
      file.write(<<~RUBY)
        require_relative '#{ROOT}/lib/sre'

        SRE.define do
          service 'catalog-api'
          owner 'catalog-platform'

          sli do
            uid 'http-requests'
            title 'HTTP requests'

            metric 'http_requests_total' do
              data_source 'otel'
              type 'counter'
            end

            instance do
              uid 'public-api'

              slo do
                uid 'successful-requests'
                objective 0.99
                success_selector status: 'success'
              end
            end
          end
        end
      RUBY
      file.flush

      stdout, _stderr, status = Open3.capture3('ruby', "#{ROOT}/bin/rules-ctl", 'generate', '--provider=datadog', file.path)
      payload = JSON.parse(stdout)

      refute status.success?
      assert_equal false, payload.fetch('valid')
      assert payload.fetch('errors').any? { |error| error.fetch('message').include?('missing datadog query binding') }
    end
  end
end
