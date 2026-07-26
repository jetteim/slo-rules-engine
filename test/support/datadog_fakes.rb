# frozen_string_literal: true

class FakeDatadogClient
  attr_reader :requests, :existing_state_requests, :created_and_waited_slos,
              :created_and_waited_monitors, :state

  def initialize(
    slos: {},
    monitors: {},
    dashboards: {},
    managed_state: nil,
    slo_create_response: nil,
    skip_mutation_paths: []
  )
    @state = { slos: slos, monitors: monitors, dashboards: dashboards }
    @managed_state = managed_state
    @requests = []
    @existing_state_requests = []
    @created_and_waited_slos = []
    @created_and_waited_monitors = []
    @slo_create_response = slo_create_response
    @skip_mutation_paths = skip_mutation_paths
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
    response = response_for(path)
    mutate_state(method, path, payload, response) unless @skip_mutation_paths.include?(path)
    response
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

  private

  def response_for(path)
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

  def mutate_state(method, path, payload, response)
    if method == 'DELETE'
      delete_from_state(path)
      return
    end

    target = target_for_path(path)
    return unless target

    id = method == 'PUT' ? path.split('/').last : response_id(response) || path.split('/').last
    name = payload[:name] || payload['name'] || payload[:title] || payload['title']
    @state.fetch(target)[name] = {
      id: id,
      payload: payload,
      match_identity: { strategy: 'source_ref', confidence: 'high' }
    }
  end

  def delete_from_state(path)
    target = target_for_path(path)
    return unless target

    id = path.sub(/\?.*\z/, '').split('/').last
    @state.fetch(target).delete_if { |_name, resource| resource.fetch(:id).to_s == id }
    return unless @managed_state

    @managed_state.fetch(target).delete_if { |resource| resource.fetch(:id).to_s == id }
  end

  def target_for_path(path)
    return :slos if path.start_with?('/api/v1/slo')
    return :monitors if path.start_with?('/api/v1/monitor')
    return :dashboards if path.start_with?('/api/v1/dashboard')
  end

  def response_id(response)
    data = response['data'] || response[:data]
    return data.fetch(0, {})['id'] || data.fetch(0, {})[:id] if data.is_a?(Array)
    return data['id'] || data[:id] if data.is_a?(Hash)

    response['id'] || response[:id]
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
