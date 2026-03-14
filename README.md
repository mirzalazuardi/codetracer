<div align="center">

```
  ██████╗ ██████╗ ██████╗ ███████╗████████╗██████╗  █████╗  ██████╗███████╗██████╗
 ██╔════╝██╔═══██╗██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗
 ██║     ██║   ██║██║  ██║█████╗     ██║   ██████╔╝███████║██║     █████╗  ██████╔╝
 ██║     ██║   ██║██║  ██║██╔══╝     ██║   ██╔══██╗██╔══██║██║     ██╔══╝  ██╔══██╗
 ╚██████╗╚██████╔╝██████╔╝███████╗   ██║   ██║  ██║██║  ██║╚██████╗███████╗██║  ██║
  ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝  ╚═╝
```

**A zero-dependency bash script for tracing symbols across Ruby & JavaScript codebases.**  
*Find definitions, call sites, data flow, and enclosing scope — without an IDE, LSP, or AI agent.*

---

[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](https://github.com/mirzalazuardi/codetracer/blob/main/LICENSE)
[![Requires](https://img.shields.io/badge/requires-ripgrep-red?style=flat-square)](https://github.com/BurntSushi/ripgrep)
[![Optional](https://img.shields.io/badge/optional-fzf%20%7C%20ctags-orange?style=flat-square)](https://github.com/junegunn/fzf)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](https://github.com/mirzalazuardi/codetracer/blob/main/CONTRIBUTING.md)

[Features](#-features) · [Install](#-install) · [Usage](#-usage) · [Examples](#-examples) · [Workflows](#-workflows) · [FAQ](#-faq)

</div>

---

## Why codetracer?

You're debugging a Rails app or a Node.js service. The bug is somewhere in the data flow for `process_payment`. You could:

- **Option A** — Open your IDE, wait for the LSP to index, click through 12 files.
- **Option B** — Paste the whole service into an AI chat. Hope it doesn't hallucinate the call graph.
- **Option C** — Run one command.

```bash
codetracer process_payment . --mode flow --scope
```

In under a second you get: where it's defined, every call site with its enclosing method, every assignment, every place the return value goes, and every mutation — across all files, in all naming conventions simultaneously.

**codetracer is Option C.**

### Minimize dependency on AI agents

AI coding agents are powerful, but every question you ask them about code structure — *"where is this method defined?"*, *"who calls this?"*, *"what files does this touch?"* — costs tokens, takes seconds to respond, and produces answers that may be wrong or stale.

codetracer gives you those answers **instantly, deterministically, and for free.** No API calls, no hallucinations, no token budget. The answers come directly from your code, not from a model's interpretation of it.

This doesn't mean you shouldn't use AI — it means you should **use AI for reasoning, not for searching.** Let codetracer find the relevant code first, then feed only what's needed to the AI.

### Reduce token usage when you do use AI

When you do need AI help, context size matters. A typical approach is to paste entire files or let an AI agent scan your codebase — both burn through tokens on irrelevant code. codetracer lets you **extract only the exact lines that matter:**

```bash
# Instead of pasting 500-line files, get the 40 lines that actually matter
codetracer process_payment . --mode flow --scope 2>&1 | head -40
```

A full `process_payment` trace across 10 files might produce ~60 lines of focused context. Pasting the raw files would be ~2,000+ lines. That's a **30x reduction in tokens** — which means faster responses, lower cost, and less noise for the model to sift through.

---

## ✨ Features

| Feature | What it does |
|---|---|
| **Multi-convention search** | Type `processPayment` — it searches `process_payment`, `ProcessPayment`, `PROCESS_PAYMENT`, `process-payment`, and `Process Payment` simultaneously |
| **Definition locator** | Finds `def`, `class`, `module`, `function`, `const =`, `export function`, `async function` |
| **Call site tracer** | Every place the symbol is invoked, with file + line |
| **Data flow analysis** | Assignments → passed as argument → returned/yielded → mutations, in one pass |
| **File map** | Which files contain the symbol + hit count per file |
| **Enclosing scope** | For every match, walks back to the nearest `def` or `function` — "which method am I inside?" |
| **ctags integration** | Precise symbol index, auto-generated if missing |
| **Interactive fzf mode** | Fuzzy-pick any match, preview context, open in `$EDITOR` |
| **Token-saving output** | Pipe + `head` gives minimal, exact context for AI prompts |

---

## 📦 Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/mirzalazuardi/codetracer/main/codetracer.sh \
  -o /usr/local/bin/codetracer && chmod +x /usr/local/bin/codetracer
```

### Manual

```bash
git clone https://github.com/mirzalazuardi/codetracer.git
cd codetracer
chmod +x codetracer.sh
sudo mv codetracer.sh /usr/local/bin/codetracer
```

### Dependencies

| Tool | Required | Purpose | Install |
|---|---|---|---|
| [`ripgrep`](https://github.com/BurntSushi/ripgrep) | ✅ Required | Fast search engine | `brew install ripgrep` |
| `bash 4+` **or** `zsh 5+` | ✅ Required | Shell runtime | `brew install bash` or `brew install zsh` |
| `awk`, `grep`, `find` | ✅ Required | Scope walking, tag lookup | Built-in on macOS/Linux |
| [`fzf`](https://github.com/junegunn/fzf) | ⬜ Optional | Interactive mode (`--inter`) | `brew install fzf` |
| [`universal-ctags`](https://ctags.io/) | ⬜ Optional | Precise definitions (`--ctags`) | `brew install universal-ctags` |

**Linux:**

```bash
# Ubuntu / Debian
sudo apt install ripgrep fzf universal-ctags

# Arch
sudo pacman -S ripgrep fzf ctags
```

**Running under zsh (macOS default shell since Catalina):**

```bash
# Works directly — no extra setup needed
zsh codetracer.sh process_payment

# Or make it executable and it uses the bash shebang automatically
chmod +x codetracer.sh
./codetracer.sh process_payment
```

---

## 🚀 Usage

```
codetracer <word> [path] [options]
```

### Arguments

| Argument | Description |
|---|---|
| `word` | Symbol to trace — any naming convention accepted |
| `path` | Root directory to search (default: `.`) |

### Options

```
-m, --mode  <mode>    def | call | flow | file | full  (default: full)
-l, --lang  <lang>    ruby | js | all                  (default: all)
-c, --ctx   <n>       Lines of context per match       (default: 3)
-s, --scope           Show enclosing method/function for every match
-t, --ctags           Use ctags index for precise definitions
-i, --inter           Interactive fuzzy picker (requires fzf)
-h, --help            Full usage guide with all examples
```

### Modes

```
def    → Where is this symbol DEFINED?
         Ruby:  def, def self., class, module, lambda, proc
         JS/TS: function, const =, let =, async function,
                export function, export default function, class

call   → Every CALL SITE where it's invoked
         Catches: word(  .word(  word{  word.method

flow   → Full DATA FLOW trace
         1. Definitions
         2. Assignments & bindings  (x = word, word:, => word)
         3. Passed as argument      (fn(word), word =>)
         4. Returned / yielded      (return word, yield word, resolve(word))
         5. Mutations               (word.push, word.merge!, word.delete)

file   → Which FILES contain it + hit count per file

full   → All of the above (default)
```

---

## 💡 Case-Variant Expansion

This is the core feature. Type a symbol in **any** naming convention and codetracer resolves it to all equivalent forms automatically, then searches them all in a single regex pass.

```
Input: processPayment
```

```
  snake_case       process_payment
  SCREAMING_SNAKE  PROCESS_PAYMENT
  camelCase        processPayment
  PascalCase       ProcessPayment
  kebab-case       process-payment
  Title Case       Process Payment
  space sep        process payment
```

All inputs below produce **identical results:**

```bash
codetracer process_payment
codetracer processPayment
codetracer ProcessPayment
codetracer PROCESS_PAYMENT
codetracer process-payment
codetracer "process payment"
```

The variant table is printed at the top of every run so you always see exactly what was searched.

---

## 📖 Examples

### Basic — trace a symbol anywhere

```bash
# Trace in current directory, all modes, all languages
codetracer process_payment

# Trace inside a specific folder
codetracer render_invoice ./app

# Limit to Ruby only
codetracer charge_card . --lang ruby

# Limit to JS/TS only
codetracer fetchUser ./src --lang js
```

### `--mode def` — find where it's defined

```bash
# Where is this Ruby method defined?
codetracer charge_card . --lang ruby --mode def

# Where is this JS/TS function defined?
codetracer fetchUser ./src --lang js --mode def

# Find a class definition
codetracer InvoiceService . --mode def

# Precise definition using ctags index (auto-generated if missing)
codetracer PaymentGateway . --mode def --ctags
```

### `--mode call` — find every call site

```bash
# Every place this method is called
codetracer send_email . --mode call

# Call sites with 5 lines of context
codetracer handleError ./src --lang js --mode call --ctx 5

# Call sites + which function each one lives inside
codetracer validate_token . --mode call --scope
```

### `--mode flow` — trace the data

```bash
# Where is data assigned, passed, returned, mutated?
codetracer current_user . --mode flow

# Flow in Ruby only
codetracer order_items . --lang ruby --mode flow

# Flow with enclosing scope labels on every match
codetracer payload ./api --mode flow --scope
```

### `--mode file` — blast radius map

```bash
# Which files touch this symbol?
codetracer stripe_key . --mode file

# File map limited to JS
codetracer apiClient ./frontend --lang js --mode file
```

### `--scope` — always know where you are

```bash
# Every match shows its nearest enclosing def/function
codetracer render_invoice . --mode call --scope

# Combined with flow — full picture
codetracer order_total . --mode flow --scope --ctx 4
```

### `--ctags` — precise indexing

```bash
# Auto-generates ./tags if missing, then looks up the symbol
codetracer PaymentService . --mode def --ctags

# ctags + full trace
codetracer order_total . --mode full --ctags --scope
```

### `--inter` — interactive fuzzy picker

```bash
# Fuzzy-select any match → opens in $EDITOR / nvim / vim / code
codetracer render . --inter

# Narrow language first, then pick interactively
codetracer dispatch ./store --lang js --inter
```

### Combining flags

```bash
# Ruby definitions only, tight context, ctags-precise
codetracer after_save . --lang ruby --mode def --ctags --ctx 1

# Full JS trace, scope labels, wide context
codetracer useAuthStore ./src --lang js --mode full --scope --ctx 6

# Everything: all modes, ctags, scope labels
codetracer order_total . --mode full --ctags --scope
```

---

## 🔬 Workflows

### Debugging an unknown bug

```bash
# 1. Find where the symbol exists at all
codetracer process_payment . --mode file

# 2. Read the definition
codetracer process_payment . --mode def --ctags

# 3. Find who calls it and from where
codetracer process_payment . --mode call --scope

# 4. Trace the data through the system
codetracer process_payment . --mode flow --scope --ctx 4
```

### Refactoring safely

```bash
# How many files will be affected?
codetracer send_notification . --mode file

# Is this covered by tests?
codetracer send_notification spec/ --mode call
codetracer send_notification __tests__/ --lang js --mode call

# What are all the callers I need to update?
codetracer send_notification . --mode call --scope
```

### Minimal AI context — save tokens

When you need to ask an AI about a specific piece of code, don't paste entire files. Use codetracer to extract only what's relevant:

```bash
# Get only the 60 most relevant lines
codetracer process_payment . --mode flow --scope 2>&1 | head -60

# Extract just the method body
awk '/def process_payment/,/^  end/' app/services/payment_service.rb

# Combine definition + call sites + tests into one clean snippet
{
  echo "=== DEFINITION ==="
  awk '/def process_payment/,/^  end/' app/services/payment_service.rb
  echo "=== CALLERS ==="
  codetracer process_payment . --mode call --scope 2>&1 | head -40
  echo "=== TESTS ==="
  rg -A 15 "it.*process_payment" spec/ -n | head -30
} > /tmp/context.txt

wc -l /tmp/context.txt   # know your token cost before pasting
```

### Orient yourself in a new codebase

```bash
# What are the major entry points?
rg "def self\." --include="*.rb" -l | head -20

# What are the biggest files?
find . -name "*.rb" | xargs wc -l | sort -rn | head -20

# Build ctags index once, reuse across all codetracer runs
ctags -R --languages=Ruby,JavaScript,TypeScript \
  --exclude=node_modules --exclude=.git --exclude=vendor .

# Now trace any symbol with --ctags flag for precision
codetracer InvoiceService . --mode def --ctags
```

---

## 🧭 Decision Tree

```
Got a bug?
    │
    ▼
codetracer <symbol> . --mode file
    │
    ├── 0 results ──→ wrong casing? try a partial: rg "payment" -l
    │
    ├── 1–3 files ──→ --mode def --ctags  then read the method
    │
    └── 10+ files ──→ --mode flow --scope first, find the hot path
            │
            ▼
        Found the suspect line?
            ├── Yes ──→ check --scope, check callers, check tests
            └── No  ──→ go one level up: who calls THIS method?
                        repeat until you reach the data origin
```

---

## ❓ FAQ

**Q: Does it work on monorepos?**  
Yes. Pass any subdirectory as the `path` argument. e.g. `codetracer charge ./packages/billing --lang ruby`

**Q: What if the codebase mixes Ruby and JS?**  
Use `--lang all` (the default). codetracer searches both with language-appropriate definition patterns.

**Q: How do I keep the ctags index fresh?**  
Add a git hook:

```bash
echo 'ctags -R --languages=Ruby,JavaScript,TypeScript --exclude=node_modules --exclude=.git .' \
  > .git/hooks/post-checkout && chmod +x .git/hooks/post-checkout
```

**Q: Why not just use an IDE?**  
You can use both. codetracer is for terminal-first workflows, remote servers, CI pipelines, quick orientation in unfamiliar repos, and generating minimal context for AI tools — without spinning up a full IDE or waiting for an LSP.

**Q: Can I pipe the output?**  
Yes, all output goes to stdout. Use `2>&1` to also capture warnings:

```bash
codetracer process_payment . --mode flow 2>&1 | grep "def\|call" | head -30
codetracer invoice_total . --mode file 2>&1 > /tmp/results.txt
```

**Q: Does it support TypeScript?**  
Yes. `.ts` and `.tsx` files are included under `--lang js` and `--lang all`. TypeScript-specific patterns (type annotations, interfaces) are on the roadmap.

---

## 🗺 Roadmap

- [ ] `--mode test` — find test files and cases for a symbol
- [ ] `--mode git` — show git log entries touching a symbol (`git log -S`)
- [ ] TypeScript interface / type alias definitions
- [ ] Python support (`--lang python`)
- [ ] Go support (`--lang go`)
- [ ] JSON/YAML config file (`.codetracerrc`)
- [ ] `--out json` for programmatic consumption
- [ ] Shell completions (bash, zsh, fish)

Want something on this list sooner? Open an issue or a PR.

---

## 🤝 Contributing

Contributions are welcome. Please:

1. Fork the repo
2. Create a branch: `git checkout -b feat/my-feature`
3. Make your changes
4. Test against at least one Ruby and one JS file
5. Open a PR with a clear description

For bug reports, include: OS, bash version (`bash --version`), ripgrep version (`rg --version`), and the exact command that failed.

---

## 📄 License

MIT — see [LICENSE](https://github.com/mirzalazuardi/codetracer/blob/main/LICENSE).

---

<div align="center">

Made for engineers who prefer a terminal over a GUI and a shell script over a language server.

**If this saved you time, consider giving it a ⭐**

</div>
