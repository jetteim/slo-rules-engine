# frozen_string_literal: true

class FakeDatadogClient
  attr_reader :requests, :existing_state_requests, :created_and_waited_slos, :created_and_waited_monitors

  def initialize(slos: {}, monitors: {}, dashboards: {}, managed_state: nil, slo_create_response: nil)
    @state = { slos: slos, monitors: monitors, dashboards: dashboards }
    @managed_state = managed_state
    @requests = []
    @existing_state_requests = []
    @created_and_waited_slos = []
    @created_and_waited_monitors = []
    @slo_create_response = slo_create_response
  end

  def existing_state(desired: nil)
    @existing_state_requests << desired
    @state
  end

  def validate_credentials!
    true
  end

  def managed_state(service:)
    @managed_state || {
      slos: @state.fetch(:slos).map { |name, entry| { id: entry.fetch(:id), name: name } },
      monitors: @state.fetch(:monitors).map { |name, entry| { id: entry.fetch(:id), name: name } },
      dashboards: @state.fetch(:dashboards).map { |title, entry| { id: entry.fetch(:id), title: title } }
    }
  end

  def request(method, path, payload: nil)
    @requests << { method: method, path: path, payload: payload }
    case path
    when '/api/v1/slo'
      @slo_create_response || { 'data' => [{ 'id' => 'generated-slo-1' }] }
    when '/api/v1/monitor'
      { 'id' => "monitor-#{@requests.length}" }
    when '/api/v1/dashboard'
      { 'id' => 'dashboard-1' }
    else
      { 'id' => "request-#{@requests.length}" }
    end
  end

  def create_and_wait_slo(payload)
    @created_and_waited_slos << payload
    request('POST', '/api/v1/slo', payload: payload)
  end

  def create_and_wait_monitor(payload)
    @created_and_waited_monitors << payload
    request('POST', '/api/v1/monitor', payload: payload)
  end

  def delete_slo(id, force: false)
    path = force ? "/api/v1/slo/#{id}?force=true" : "/api/v1/slo/#{id}"
    request('DELETE', path)
  end

  def delete_monitor(id)
    request('DELETE', "/api/v1/monitor/#{id}")
  end

  def delete_dashboard(id)
    request('DELETE', "/api/v1/dashboard/#{id}")
  end
end

class FakeResponse
  attr_reader :code, :body

  def initialize(code, body, headers = {})
    @code = code
    @body = body
    @headers = headers
  end

  def [](key)
    @headers[key]
  end
end
