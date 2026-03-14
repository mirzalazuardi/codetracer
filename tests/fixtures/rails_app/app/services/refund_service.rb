# frozen_string_literal: true

class RefundService
  def self.call(order, user)
    new(order, user).call
  end

  def initialize(order, user)
    @order = order
    @user = user
  end

  def call
    return failure('Order already refunded') if @order.refunded?

    if full_refund?
      process_full_refund
    else
      process_partial_refund
    end
  end

  private

  def full_refund?
    @order.shipped_at.nil? || @order.items.none?(&:delivered?)
  end

  def process_full_refund
    result = PaymentGateway.refund_full(@order.payment_id)
    if result.success?
      @order.update!(status: :refunded, refunded_at: Time.current)
      InventoryService.restore(@order.items)
      success
    else
      failure(result.error)
    end
  end

  def process_partial_refund
    refundable_items = @order.items.reject(&:delivered?)
    amount = refundable_items.sum(&:price)

    result = PaymentGateway.refund_partial(@order.payment_id, amount)
    if result.success?
      @order.update!(status: :partially_refunded)
      InventoryService.restore(refundable_items)
      success
    else
      failure(result.error)
    end
  end

  def success
    OpenStruct.new(success?: true, error: nil)
  end

  def failure(error)
    OpenStruct.new(success?: false, error: error)
  end
end
