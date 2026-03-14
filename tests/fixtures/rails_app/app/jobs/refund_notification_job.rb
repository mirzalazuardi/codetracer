# frozen_string_literal: true

class RefundNotificationJob
  include Sidekiq::Job

  def perform(order_id, user_id)
    order = Order.find(order_id)
    user = User.find(user_id)

    # Send email notification
    UserMailer.refund_confirmation(order, user).deliver_later

    # Send SMS if enabled
    if user.sms_notifications_enabled?
      SmsService.send(user.phone, "Your refund for order ##{order.id} has been processed.")
    end

    # Notify Slack channel
    SlackNotifier.notify('#refunds', "Refund processed for order ##{order.id}")

    # Update analytics
    AnalyticsService.track('refund_completed', order_id: order.id, user_id: user.id)
  end
end
