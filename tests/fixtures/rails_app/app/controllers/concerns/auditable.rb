# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern

  included do
    before_action :track_request
    after_action :record_response
  end

  private

  def track_request
    RequestTracker.log(request, current_user)
  end

  def record_response
    ResponseTracker.log(response, current_user)
  end
end
