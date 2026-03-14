# fixtures/payment_service.rb
# Covers: def, def self., class, module, lambda, proc,
#         call sites, assignments, pass-as-arg, return, yield, mutations

module Billing
  class PaymentService
    PROCESS_PAYMENT_TIMEOUT = 30

    process_payment_logger = lambda { |msg| puts msg }
    process_payment_hook   = proc { |order| order.notify }

    def initialize(gateway)
      @gateway = gateway
      @process_payment_retries = 0
    end

    # ── Definition under test ──────────────────────────────────
    def process_payment(order, amount)
      result = @gateway.charge(amount)
      return process_payment_result(result)
    end

    def self.process_payment(order)
      new(DefaultGateway).process_payment(order, order.total)
    end

    def process_payment_result(result)
      yield result if block_given?
      result
    end

    # ── Call sites ─────────────────────────────────────────────
    def retry_process_payment(order)
      @process_payment_retries += 1
      process_payment(order, order.total)
    end

    def batch_process
      orders.each do |order|
        process_payment(order, order.amount)
      end
    end

    # ── Passed as argument ─────────────────────────────────────
    def schedule(callback)
      queue.push(callback)
      run_later(:process_payment, order: @current_order)
    end

    # ── Assignments ────────────────────────────────────────────
    def build_context
      process_payment_method = :credit_card
      opts = { process_payment: true, retries: 3 }
      handler = method(:process_payment)
      [process_payment_method, opts, handler]
    end

    # ── Return / yield ─────────────────────────────────────────
    def run_payment_flow(order)
      result = process_payment(order, order.total)
      yield process_payment_result(result)
      return process_payment_result(result)
    end

    # ── Mutations ──────────────────────────────────────────────
    def reset_state
      @process_payment_retries = 0
      payment_queue.clear
      failed_payments = []
      failed_payments.push(process_payment_logger)
    end

    private

    def validate_order(order)
      raise ArgumentError, "invalid" unless order.valid?
    end
  end

  # Another class calling the service
  class OrderController
    def complete_order(order)
      PaymentService.process_payment(order)
    end

    def handle_checkout(cart)
      svc = PaymentService.new(StripeGateway)
      svc.process_payment(cart.to_order, cart.total)
    end
  end
end
