# frozen_string_literal: true

class OrdersController < ApplicationController
  include Auditable

  before_action :set_order, only: [:show, :refund, :receipt, :cancel]
  before_action :authorize_refund, only: [:refund]
  after_action :log_refund_attempt, only: [:refund]
  around_action :measure_performance, only: [:refund]

  def index
    @orders = current_user.orders.includes(:items)
    render json: @orders
  end

  def show
    render json: @order
  end

  def refund
    if @order.refundable?
      result = RefundService.call(@order, current_user)
      if result.success?
        RefundNotificationJob.perform_async(@order.id, current_user.id)
        AuditLogJob.perform_in(5.minutes, 'refund', @order.id)
        render json: { status: 'refunded', order: @order }
      else
        render json: { error: result.error }, status: :unprocessable_entity
      end
    else
      render json: { error: 'Order not refundable' }, status: :bad_request
    end
  end

  def receipt
    pdf = ReceiptService.generate(@order)
    send_data pdf, filename: "receipt_#{@order.id}.pdf"
  end

  def cancel
    if @order.cancellable?
      @order.cancel!
      OrderCancellationJob.perform_async(@order.id)
      render json: { status: 'cancelled' }
    else
      render json: { error: 'Order cannot be cancelled' }, status: :bad_request
    end
  end

  def pending
    @orders = current_user.orders.pending
    render json: @orders
  end

  def completed
    @orders = current_user.orders.completed
    render json: @orders
  end

  private

  def set_order
    @order = current_user.orders.find(params[:id])
  end

  def authorize_refund
    unless @order.user == current_user || current_user.admin?
      render json: { error: 'Unauthorized' }, status: :forbidden
    end
  end

  def log_refund_attempt
    RefundAuditService.log(@order, current_user, response.status)
  end

  def measure_performance
    start_time = Time.current
    yield
    duration = Time.current - start_time
    Rails.logger.info("Refund took #{duration}s")
  end
end
