# I Built a Bash Script That Traces Code Faster Than Your IDE (And Saves AI Tokens)

You're debugging a Rails app. The bug is somewhere in `process_payment`. You could:

**A)** Open your IDE, wait for LSP to index, click through 12 files.

**B)** Paste the whole service into ChatGPT. Hope it doesn't hallucinate the call graph.

**C)** Run one command:

```bash
codetracer process_payment . --mode flow --scope
```

In under a second: where it's defined, every call site with enclosing method, every assignment, every place the return value goes — across all files.

**I chose option C.** So I built it.

---

## What is codetracer?

A single-file bash script (~1400 lines) that traces symbols across Ruby and JavaScript/TypeScript codebases. No IDE, no LSP, no AI agent.

**Requirements:** bash 4+ (or zsh 5+) and ripgrep. That's it.

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/mirzalazuardi/codetracer/main/codetracer.sh \
  -o /usr/local/bin/codetracer && chmod +x /usr/local/bin/codetracer
```

---

## The Killer Feature: Case-Variant Expansion

Type a symbol in **any** naming convention. codetracer finds all forms automatically:

```
Input: processPayment

Searches simultaneously:
  process_payment      (snake_case)
  PROCESS_PAYMENT      (SCREAMING_SNAKE)
  processPayment       (camelCase)
  ProcessPayment       (PascalCase)
  process-payment      (kebab-case)
```

All these commands produce **identical results**:

```bash
codetracer process_payment
codetracer processPayment
codetracer ProcessPayment
```

No more "I searched for `process_payment` but the JS file uses `processPayment`" moments.

---

## Five Modes for Different Questions

### 1. Where is it defined?

```bash
codetracer PaymentService . --mode def
```

Finds `def`, `class`, `module`, `function`, `const =`, `async function`, etc.

### 2. Who calls it?

```bash
codetracer send_email . --mode call --scope
```

Every call site with full scope chain:

```
app/services/order_service.rb:42:    send_email(user, receipt)
  scope -> mod Billing > cls OrderService > def complete_order:38
```

### 3. How does data flow?

```bash
codetracer current_user . --mode flow
```

Tracks: assignments, passed as argument, returned/yielded, mutations.

### 4. Which files touch it?

```bash
codetracer stripe_key . --mode file
```

File map with hit counts per file.

### 5. Everything at once

```bash
codetracer order_total . --mode full --scope
```

---

## NEW: Rails Route Tracing

Just shipped this week. Trace a route through the full request lifecycle:

```bash
codetracer --action "OrdersController#refund" ./app
```

Output:

```
━━━ ROUTE TRACE: OrdersController#refund ━━━

OrdersController (app/controllers/orders_controller.rb)
├── before_action :authenticate_user!          :23  [ApplicationController]
├── before_action :set_order                   :8
├── def refund                                 :67
│   ├── if @order.refundable?                  :68
│   │   ├── call: RefundService.call           :69
│   │   └── enqueue: RefundNotificationJob     :74  [async]
│   └── else                                   :76
│       └── render json: errors                :77
└── after_action :log_refund_attempt           :10
```

Callbacks, conditionals, service calls, Sidekiq jobs — all in one tree. Perfect for understanding unfamiliar Rails controllers or creating sequence diagrams.

---

## Why Not Just Use AI?

I use AI daily. But every question you ask about code structure — *"where is this defined?"*, *"who calls this?"* — costs tokens, takes seconds, and might be wrong.

codetracer gives those answers **instantly, deterministically, for free.**

### Save Tokens When You Do Use AI

Instead of pasting 500-line files, extract only what matters:

```bash
# Get 60 focused lines instead of 2000+ raw lines
codetracer process_payment . --mode flow --scope 2>&1 | head -60
```

That's a **30x reduction in tokens**.

---

## The Scope Chain

This is my favorite feature. Every match shows its full nesting context:

```bash
codetracer process_payment . --mode call --scope
```

```
fixture_payment_service.rb:40:        process_payment(order, order.amount)
  scope -> mod Billing:5 > cls PaymentService:6 > def batch_process:38 > blk each:39
```

You instantly know: this call happens inside an `each` block, inside `batch_process` method, inside `PaymentService` class, inside `Billing` module.

No clicking through files. No mental stack tracing.

---

## Works on macOS and Linux

Tested on:
- macOS with bash 4+ or zsh 5+
- Ubuntu/Debian
- Arch Linux

```bash
# macOS
brew install ripgrep

# Ubuntu
sudo apt install ripgrep

# Optional: fzf for interactive mode, ctags for precise indexing
brew install fzf universal-ctags
```

---

## Interactive Mode with fzf

```bash
codetracer render . --inter
```

Fuzzy-pick any match, preview context, press Enter to open in your editor.

---

## Real Workflow Example

Debugging an unknown bug:

```bash
# 1. Where does this symbol exist?
codetracer process_payment . --mode file

# 2. Read the definition
codetracer process_payment . --mode def --ctags

# 3. Find callers and their context
codetracer process_payment . --mode call --scope

# 4. Trace data through the system
codetracer process_payment . --mode flow --scope --ctx 4
```

Four commands. Full picture. No IDE required.

---

## Try It

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/mirzalazuardi/codetracer/main/codetracer.sh \
  -o /usr/local/bin/codetracer && chmod +x /usr/local/bin/codetracer

# Try it
codetracer YourClassName ./your-project --mode def
```

---

## Links

**GitHub:** [github.com/mirzalazuardi/codetracer](https://github.com/mirzalazuardi/codetracer)

If this looks useful, I'd appreciate a star. And if you have feature requests or find bugs, issues and PRs are welcome.

---

*Built for engineers who prefer a terminal over a GUI and a shell script over a language server.*
