# frozen_string_literal: true

class AuditLogJob
  include Sidekiq::Job

  def perform(action, record_id, metadata = {})
    AuditLog.create!(
      action: action,
      record_id: record_id,
      metadata: metadata,
      created_at: Time.current
    )
  end
end
