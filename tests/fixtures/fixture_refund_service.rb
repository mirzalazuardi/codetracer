# fixtures/refund_service.rb
# Contains ZERO occurrences of the payment-processing symbol.
# Used to assert --mode file does NOT list this file.

module Billing
  class RefundService
    def issue_refund(order, amount)
      @gateway.refund(order.transaction_id, amount)
    end

    def self.full_refund(order)
      new.issue_refund(order, order.total)
    end

    def partial_refund(order, pct)
      amount = order.total * pct / 100.0
      issue_refund(order, amount)
    end
  end
end
