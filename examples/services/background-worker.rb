# frozen_string_literal: true

require_relative '../../lib/sre'

SRE.define do
  service 'background-worker'
  owner 'platform-team'
  description 'Synthetic low-volume background worker service level definition.'
  environments 'production'

  sli do
    uid 'job-completion'
    title 'Job completion'
    user_visible_rationale 'Represents whether scheduled background work completes for consumers.'

    measurement_details do
      source 'synthetic-otel-fixture'
      measurement_point 'scheduled job completion boundary'
      threshold_requirements 'completion metric with job and status dimensions'
      caveats 'synthetic example data only'
    end

    metric 'worker.job.completed' do
      data_source 'otel'
      type 'counter'
      selector service: 'background-worker'
    end

    instance do
      uid 'scheduled-run'
      selector schedule: 'periodic'

      slo do
        uid 'completed-runs'
        objective 0.99
        success_selector status: 'completed'
        calculation_basis 'time_slice'
        documentation 'Scheduled job completes successfully.'
        miss_policy do
          trigger 'error budget exhausted'
          response 'assign one responder to restore scheduled work completion'
          authority 'pause risky changes for the affected worker'
          exit_condition 'burn rate returns below policy threshold'
          review_cadence 'next business day'
        end
        reality_check_notes 'synthetic low-volume example; time-slice basis avoids one failed run dominating alert behavior'
        observability_handoff 'bind provider queries', 'generate decision dashboard'
      end
    end
  end
end
