// fixtures/paymentService.ts
// TypeScript variant — verifies *.ts is picked up under --lang js

interface Order {
  id: string;
  total: number;
}

interface PaymentResult {
  success: boolean;
  transactionId: string;
}

// ── Definitions ───────────────────────────────────────────────

async function processPayment(order: Order, amount: number): Promise<PaymentResult> {
  const result = await gateway.charge(order.id, amount);
  return processPaymentResult(result);
}

const processPaymentValidator = (order: Order): boolean => {
  return order.total > 0;
};

export class PaymentProcessor {
  async processPayment(order: Order): Promise<PaymentResult> {
    return processPayment(order, order.total);
  }
}

// ── Call sites ────────────────────────────────────────────────

async function checkout(cart: { order: Order; total: number }) {
  const result = await processPayment(cart.order, cart.total);
  return result;
}

// ── Assignments ───────────────────────────────────────────────

const processPaymentFn: typeof processPayment = processPayment;
const config: Record<string, unknown> = {
  processPayment: true,
};

// ── Return ────────────────────────────────────────────────────

function getProcessor(): typeof processPayment {
  return processPayment;
}
