// fixtures/paymentService.js
// Covers: function, const =, let =, async function, export function,
//         export default, class, call sites, assignments, mutations

const PROCESS_PAYMENT_TIMEOUT = 5000;

// ── Definitions ───────────────────────────────────────────────

function processPayment(order, amount) {
  const result = gateway.charge(amount);
  return processPaymentResult(result);
}

const processPaymentHandler = async (req, res) => {
  const result = await processPayment(req.body.order, req.body.amount);
  res.json(result);
};

const processPaymentValidator = function (order) {
  return order && order.total > 0;
};

async function processPaymentWithRetry(order, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      return await processPayment(order, order.total);
    } catch (e) {
      if (i === retries - 1) throw e;
    }
  }
}

export function processPaymentExport(order) {
  return processPayment(order, order.total);
}

export default function processPaymentDefault(order) {
  return processPayment(order, order.total);
}

class PaymentService {
  processPayment(order, amount) {
    return gateway.charge(order, amount);
  }

  async processPaymentAsync(order) {
    return await this.processPayment(order, order.total);
  }
}

// ── Call sites ────────────────────────────────────────────────

function checkout(cart) {
  const result = processPayment(cart.order, cart.total);
  return result;
}

async function handleSubmit(event) {
  event.preventDefault();
  await processPayment(currentOrder, currentOrder.amount);
}

const runBatch = (orders) => {
  return orders.map(order => processPayment(order, order.total));
};

// ── Passed as argument ────────────────────────────────────────

function withRetry(fn, times) {
  return fn();
}

const scheduled = withRetry(processPayment, 3);
queue.push(processPayment);
Promise.resolve().then(processPayment);

// ── Assignments ───────────────────────────────────────────────

let processPaymentFn = processPayment;
var processPaymentRef = processPaymentHandler;
const config = {
  processPayment: true,
  timeout: PROCESS_PAYMENT_TIMEOUT,
};
const { processPayment: payFn } = handlers;

// ── Return / resolve / emit ───────────────────────────────────

function getPaymentFn() {
  return processPayment;
}

function resolvePayment(order) {
  return new Promise((resolve) => {
    resolve(processPayment(order, order.total));
  });
}

function emitPayment(emitter, order) {
  emitter.emit("payment", processPayment(order, order.total));
}

// ── Mutations ─────────────────────────────────────────────────

const paymentQueue = [];
paymentQueue.push(processPaymentHandler);
paymentQueue.unshift(processPaymentHandler);

const paymentMap = new Map();
paymentMap.set("default", processPayment);
paymentMap.delete("old");

// ── Unrelated symbol (should NOT match) ───────────────────────

function refundPayment(order) {
  return gateway.refund(order);
}

function validateCard(card) {
  return card.number.length === 16;
}
