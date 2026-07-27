# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

class Net::HTTP
  class FakePrometheusStatusResponse
    attr_reader :body

    def initialize(body)
      @body = body
    end
  end

  def self.get_response(uri)
    expression = URI.decode_www_form(uri.query.to_s).to_h.fetch('query')
    File.open(ENV.fetch('PROMETHEUS_REQUEST_LOG'), 'a') do |file|
      file.puts("#{uri.host} #{uri.path}?#{uri.query}")
    end
    raise 'private backend failure' if ENV['PROMETHEUS_FAIL_HOST'] == uri.host

    value =
      if expression.start_with?('timestamp(')
        (Time.now.utc - 10).to_f
      elsif expression.end_with?(':error_budget_remaining_ratio')
        0.8
      elsif expression.end_with?(':error_budget_ratio')
        0.001
      elsif expression.end_with?(':objective_ratio')
        0.999
      elsif expression.end_with?(':success_ratio')
        0.9998
      elsif expression.end_with?(':observations')
        42
      elsif expression.include?(':burn_rate:')
        0.2
      else
        raise "unexpected query #{expression.inspect}"
      end
    payload = {
      status: 'success',
      data: {
        resultType: 'vector',
        result: [
          {
            metric: {},
            value: [Time.now.utc.to_f, value.to_s]
          }
        ]
      }
    }
    FakePrometheusStatusResponse.new(JSON.generate(payload))
  end
end
