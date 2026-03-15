# codetracer — LLM Context File

> **Audience**: AI agents, LLMs, automated tools.
> This file is machine-optimized: no prose padding, all facts, exact values only.
> Human README: `README.md`

---

## Identity

```
name:       codetracer
type:       bash script (single file, also runs under zsh)
file:       codetracer.sh
shebang:    #!/usr/bin/env bash
requires:   bash >= 4.0  OR  zsh >= 5.0,  ripgrep (rg)
optional:   fzf, universal-ctags, pygmentize (Pygments)
purpose:    trace symbols across Ruby/JS/TS codebases without an IDE or LLM
repo:       https://github.com/mirzalazuardi/codetracer
invoke:     bash codetracer.sh <word>   # explicit bash
            zsh  codetracer.sh <word>   # explicit zsh
            ./codetracer.sh <word>      # uses shebang (bash)
```

---

## Invocation Schema

```
codetracer <WORD> [PATH] [FLAGS]
```

| Positional | Type | Default | Notes |
|---|---|---|---|
| `WORD` | string | required | Symbol in any naming convention |
| `PATH` | string | `.` | Root directory, relative or absolute |

| Flag | Short | Values | Default |
|---|---|---|---|
| `--mode` | `-m` | `def` `call` `flow` `file` `full` | `full` |
| `--lang` | `-l` | `ruby` `js` `all` | `all` |
| `--ctx` | `-c` | integer | `3` |
| `--scope` | `-s` | boolean flag | `false` |
| `--ctags` | `-t` | boolean flag | `false` |
| `--inter` | `-i` | boolean flag | `false` — requires fzf |
| `--help` | `-h` | boolean flag | — exits 0 after printing help |
| `--route` | — | `"VERB /path"` or curl file path | — sets MODE=route |
| `--action` | — | `"Controller#action"` | — sets MODE=route |
| `--model` | — | `"Model#method"` or `"Model"` | — sets MODE=model |
| `--depth` | — | integer | `3` (route/model mode) |
| `--async` | — | `mark` `inline` `full` | `mark` (route mode only) |
| `--highlight` | — | boolean flag | `false` — requires pygmentize |

---

## Exit Codes

| Code | Condition |
|---|---|
| `0` | Success, or `--help` |
| `1` | bash < 4.0 detected |
| `1` | codetracer.sh not found (test runner only) |

---

## Core Algorithm: build_variants()

**Input**: raw string in any naming convention
**Output**: global `$WORD_REGEX` — ERE alternation of all forms
**Side effect**: prints variant table to stdout

### Tokenization pipeline

```
raw input
  → replace [-_ ] with space
  → split camelCase: s/([a-z0-9])([A-Z])/\1 \2/g
  → split acronyms:  s/([A-Z])([A-Z][a-z])/\1 \2/g
  → lowercase all
  → trim leading/trailing spaces
  → split on spaces → words[]
```

### Variant construction from words[]

```
snake_case      : join(words, "_")
SCREAMING_SNAKE : upper(snake)
camelCase       : words[0] + title(words[1..])
PascalCase      : title(words[0]) + title(words[1..])
kebab-case      : join(words, "-")
Title Case      : join(title(words), " ")
space sep       : join(words, " ")
```

### Deduplication

Exact-string dedup using `printf | grep -xF` (portable, no `declare -A`, works on bash 4+).

### Regex output format

```
WORD_REGEX = "(variant1|variant2|...|variantN)"
```

Special regex chars in each variant are escaped with `sed 's/[.()[\^$*+?{}|\\]/\\&/g'` before joining.

### Input equivalence examples

All of these produce the same `WORD_REGEX`:

```
process_payment  →  (process_payment|PROCESS_PAYMENT|processPayment|ProcessPayment|process-payment|Process Payment|process payment)
processPayment   →  identical
ProcessPayment   →  identical
PROCESS_PAYMENT  →  identical
process-payment  →  identical
"process payment" → identical
```

---

## Feature Functions

### find_definitions()

**Triggered by**: `--mode def`, `--mode full`
**Output**: matched lines ± `$CTX` context lines

Ruby regex applied to `*.rb *.rake`:
```
^\s*(def\s+WORD|def\s+self\.WORD|class\s+WORD|module\s+WORD|WORD\s*=\s*lambda|WORD\s*=\s*proc)
```

JS/TS regex applied to `*.js *.jsx *.ts *.tsx`:
```
(function\s+WORD[\s(]
|const\s+WORD\s*=\s*(async\s+)?(\(|function)
|let\s+WORD\s*=
|var\s+WORD\s*=
|WORD\s*:\s*(async\s+)?function
|async\s+WORD\s*\(
|^\s*(export\s+)?(default\s+)?function\s+WORD
|class\s+WORD[\s{])
```

---

### find_calls()

**Triggered by**: `--mode call`, `--mode full`
**Output**: matched lines ± `$CTX` context lines

Regex (applied to all language globs):
```
WORD[(\s.{]|\.WORD[(\s]|WORD\b
```

---

### find_flow()

**Triggered by**: `--mode flow`, `--mode full`
**Output**: 4 subsections, each ± 1 line context

| Subsection | Pattern |
|---|---|
| Assignments | `(WORD\s*=(?!=)|=>\s*WORD|WORD:)` |
| Passed as arg | `[,(]\s*WORD\s*[,)]|\bWORD\b.*=>` |
| Returned/yielded | `(return\s+WORD|yield\s+WORD|resolve\(WORD|emit.*WORD)` |
| Mutations | `WORD\.(push|pop|shift|unshift|merge!|update|delete|destroy|append|prepend|replace|set|clear)\b` |

---

### find_files()

**Triggered by**: `--mode file`, `--mode full`
**Output**: per-file hit count, total file count

```
rg --smart-case -l -e WORD_REGEX [globs]
→ for each file: rg --count -e WORD_REGEX FILE
→ printf "  %4s hits  %s\n"
→ printf "  Total: %s files\n"
```

---

### show_enclosing_scope()

**Triggered by**: `--scope` flag (any mode)
**Output**: for each match — file, line, nearest enclosing def/function, match text

Algorithm: for each `file:lineno` match, runs awk over the file scanning lines `1..lineno` for:
```
/^\s*(def |function |const [A-Za-z_]+ = (async )?(\(|function)|async function )/
```
Returns the last matched line before the target — that is the enclosing scope.
Falls back to `? (top-level)` if none found.

---

### ctags_lookup()

**Triggered by**: `--ctags` flag
**Requires**: `ctags` binary (universal-ctags recommended)
**Output**: tag name, file, approximate line number

- Looks for `$ROOT/tags`
- If missing: runs `ctags -R --languages=Ruby,JavaScript,TypeScript --exclude=node_modules --exclude=.git --exclude=vendor`
- Searches tags file with `grep -E "^WORD_REGEX\t"`

---

### interactive_mode()

**Triggered by**: `--inter` flag
**Requires**: `fzf` binary
**Behavior**:
1. `rg` finds all matches
2. `fzf --ansi` presents them with a right-side preview (±5 lines)
3. On `ENTER`: opens selection in `$EDITOR` → `nvim` → `vim` → `code --goto`
4. On `ESC`: exits cleanly

---

### trace_route()

**Triggered by**: `--route` or `--action` flag (sets MODE=route)
**Purpose**: Trace Rails route through controller lifecycle
**Output**: Nested tree with box-drawing characters

#### Route tracing sub-functions

| Function | Purpose |
|---|---|
| `parse_curl_file()` | Parse curl command from shell file → verb, path, query/body params |
| `parse_routes_file()` | Parse `config/routes.rb` → controller#action mapping |
| `find_controller_file()` | Locate controller file (handles namespaces like `Admin::`) |
| `parse_callbacks()` | Extract before/after/around_action with only:/except: filtering |
| `resolve_callback_origin()` | Find where callback is defined (parent controller, concern) |
| `parse_action_body()` | AWK-based parser for action method body |
| `detect_service_calls()` | Find `ServiceClass.call(args)` patterns |
| `detect_async_jobs()` | Find Sidekiq (`perform_async`) and DelayedJob (`.delay.`) patterns |
| `detect_params()` | Find `params[:key]`, `params.fetch`, `params.require`, `.permit` |

#### Curl file parsing

When `--route` receives a file path instead of "VERB /path", it parses the curl command:

```
Input:  curl -X POST "http://localhost:3000/orders/123/refund?notify=true" -d '{"reason": "damaged"}'

Output:
  CURL_VERB = "POST"
  CURL_PATH = "/orders/:id/refund"     ← numeric segments converted to :id
  CURL_QUERY_PARAMS = "notify"         ← extracted from ?key=value
  CURL_BODY_PARAMS = "reason"          ← extracted from JSON body
```

Expected params are shown in trace output before callbacks.

#### Route parsing patterns

```
# Resources
resources :orders              → OrdersController
post 'refund', on: :member     → #refund action

# Direct routes
post '/path', to: 'ctrl#act'   → controller#action

# Namespaces
namespace :admin do            → Admin:: prefix
```

#### Async mode behavior

| Mode | Behavior |
|---|---|
| `mark` | Shows `[async]` marker on job enqueue lines |
| `inline` | Expands job's `perform` method in tree |
| `full` | Recursively expands nested async jobs |

#### Params detection patterns

| Pattern | Output |
|---|---|
| `params[:key]` | `params: :key  [query]` |
| `params["key"]` | `params: :key  [query]` |
| `params.fetch(:key)` | `params: :key  [query]` |
| `params.require(:key)` | `params: :key  [query]` |
| `.permit(:a, :b, :c)` | `permit: :a, :b, :c  [query]` |

#### Cross-class call chain tracing

All trace modes (`--route`, `--action`, `--model`) follow calls into other classes:

| Pattern | Traced as |
|---|---|
| `ServiceClass.call(...)` | `ServiceClass#call` |
| `ClassName.new(...)` | `ClassName#initialize` |
| `ClassName.new(...).method(...)` | `ClassName#method` |
| `Interactor::Organizer` with `organize` | Expands each organized class |
| Method not in file (gem method) | Shows class summary (methods, attributes, DSL) |

Depth controlled by `--depth` (default: 3). Visited `class#method` pairs tracked to prevent infinite loops.

#### Curl param value display

When `--route` receives a curl file, query params are URL-decoded with original values shown:

```
Input:  ?order%5Bdate%5D%5Bgeq%5D=Sun,+15+Mar+2026&payment_methods%5B%5D=cash&payment_methods%5B%5D=credit

Output:
  order[date][geq] # Sun, 15 Mar 2026
  payment_methods[] # cash, credit
```

Array params deduplicated, values merged with commas.

#### Output format

```
━━━ ROUTE TRACE: Controller#action ━━━

ControllerName (filepath)
├── before_action :callback    :line  [origin]
├── def action_name            :line
│   ├── params: :key           :line  [query]
│   ├── permit: :a, :b         :line  [query]
│   ├── conditional            :line
│   │   ├── call: Service.call :line
│   │   └── enqueue: Job       :line  [async]
│   └── else                   :line
└── after_action :callback     :line

[ServiceClass#call (filepath)]
├── def call                   :line
│   ├── ...body...
```

---

### trace_model()

**Triggered by**: `--model` flag (sets MODE=model)
**Purpose**: Trace Rails model structure and method call chains
**Input**: `"Model#method"` or `"Model"` (full structure)

#### Model tracing sub-functions

| Function | Purpose |
|---|---|
| `parse_model_input()` | Parse `"Order#method"` → MODEL_CLASS + MODEL_METHOD. Strips args `(...)` |
| `find_model_file()` | Convert PascalCase → snake_case, search `app/models/` |
| `extract_model_includes()` | Find `include`, `extend`, `prepend` statements |
| `extract_model_associations()` | Find `has_many`, `has_one`, `belongs_to`, `has_and_belongs_to_many` |
| `extract_model_validations()` | Find `validates`, `validate`, `validates_*_of` |
| `extract_model_callbacks()` | Find `before_save`, `after_create`, `around_update`, etc. |
| `extract_model_scopes()` | Find `scope :name` |
| `extract_model_methods()` | List or trace methods; follows cross-class calls for target method |
| `extract_cross_class_calls()` | AWK parser: extracts `ClassName.method()` patterns from method body |
| `trace_call_chain()` | Recursive tracer: follows calls across files with visited tracking |

#### Output format

```
━━━ MODEL TRACE: Order#oc_order ━━━

[Order (app/models/order.rb)]

[Includes]
├── include Archivable
└── include Payable

[Associations]
├── has_many :order_items
└── belongs_to :outlet

[Validations]
├── validates :order_no, presence: true

[Callbacks]
├── before_save :calculate_totals

[Scopes]
├── scope :active

[Methods]
├── def oc_order
│   ├── if condition
│   │   ├── call: OrderCompliment
│   ...

[OrderCompliment [organizer] (filepath)]
└── organize ClassA, ClassB

[ClassA#call (filepath)]
├── def call
│   ├── ...body...
```

---

### highlight mode

**Triggered by**: `--highlight` flag
**Requires**: `pygmentize` binary (from Pygments)
**Config**: 16-color terminal, gruvbox-dark theme

| Component | Behavior |
|---|---|
| Method bodies | Full body extracted → batch pygmentize → tree prefixes added |
| Tree items (callbacks, etc.) | ANSI stripped → re-highlighted as Ruby via pygmentize |
| Fallback | If pygmentize unavailable, uses default ANSI coloring |

```bash
pygmentize -l ruby -f terminal -O style=gruvbox-dark
```

---

## Dispatch Table

```
--inter=true                  → interactive_mode(); exit 0

--mode=route                  → trace_route()
                                (triggered by --route or --action)

--mode=model                  → trace_model()
                                (triggered by --model)

--mode=def                    → find_definitions()
                                if --ctags: ctags_lookup()

--mode=call                   → find_calls()
                                if --scope: show_enclosing_scope()

--mode=flow                   → find_definitions()
                                find_flow()
                                if --scope: show_enclosing_scope()

--mode=file                   → find_files()

--mode=full (default)         → find_definitions()
                                if --ctags: ctags_lookup()
                                find_calls()
                                find_flow()
                                find_files()
                                if --scope: show_enclosing_scope()
```

---

## Language → File Glob Mapping

| `--lang` | Globs searched | rg type flags |
|---|---|---|
| `ruby` | `*.rb` `*.rake` `*.gemspec` `Gemfile` | `--type ruby` |
| `js` | `*.js` `*.jsx` `*.ts` `*.tsx` `*.mjs` `*.cjs` | `--type js --type ts` |
| `all` (default) | `*.rb` `*.rake` `*.js` `*.jsx` `*.ts` `*.tsx` `*.mjs` | none |

---

## Platform & Shell Compatibility

| Issue | macOS bash 3.2 | macOS zsh 5+ | Linux bash 5 | Linux zsh | Fix in script |
|---|---|---|---|---|---|
| `declare -A` | BREAKS | BREAKS | OK | OK | Replaced with `printf \| grep -xF` dedup |
| `grep -P` | BREAKS | BREAKS | OK | OK | Replaced with `grep -E` (POSIX ERE) |
| `xargs -I{} echo -e` | BREAKS | BREAKS | OK | OK | Replaced with `printf` |
| `--include=` (rg flag) | BREAKS silently | BREAKS silently | BREAKS silently | BREAKS silently | `rg` uses `--glob=`, not `--include=` |
| bash version < 4 | BREAKS | N/A | OK | N/A | Hard exit + instructions |
| `BASH_VERSINFO` | OK | UNDEFINED | OK | UNDEFINED | Guarded: `[ -n "${BASH_VERSION:-}" ]` |
| `ZSH_VERSION` | UNDEFINED | OK | UNDEFINED | OK | Guarded: `[ -n "${ZSH_VERSION:-}" ]` |
| `words=($tokens)` word-split | OK | BREAKS — `SH_WORD_SPLIT` only affects command context, not array assignment | OK | BREAKS | `read -ra` (bash) / `read -rA` (zsh) branch |
| `${words[0]}` 0-index | OK | BREAKS — zsh `read -A` is 1-indexed, `[0]` = empty | OK | BREAKS | `for w in "${words[@]}"` + `_first` flag; no explicit index |
| `wc -l` whitespace | Leading spaces | Leading spaces | No spaces | No spaces | `\| tr -d ' '` |
| `BASH_SOURCE[0]` (tests) | OK | UNDEFINED | OK | UNDEFINED | `${BASH_SOURCE[0]:-$0}` |

### Shell compat block (runs once at startup)

```
if ZSH_VERSION set:
    setopt SH_WORD_SPLIT    # retained for general compat (simple commands)
    setopt KSH_ARRAYS       # retained for general compat
    if ZSH_VERSION major < 5 → exit 1 with instructions
    NOTE: array word-splitting uses read -rA branch, not setopt

elif BASH_VERSION set:
    if BASH_VERSINFO[0] < 4 → exit 1 with instructions
    (macOS hint: brew install bash)

else:
    exit 1 — unsupported shell
```

**macOS setup (run once):**
```bash
brew install bash ripgrep          # if using bash
brew install zsh ripgrep           # if using zsh (zsh already built-in on macOS 10.15+)
brew install fzf universal-ctags   # optional
```

---

## Output Format

All output is to **stdout**. Warnings go to **stdout** (not stderr) via `warn()`.
ANSI color codes are always emitted. To strip: `codetracer ... | sed 's/\x1b\[[0-9;]*[mGKHF]//g'`

### Output structure per run

```
[variant table]          ← always printed
[header box]             ← always printed: root / lang / mode / ctx
[feature output ...]     ← depends on --mode
[done banner]            ← always printed
```

### Match line format (rg output)

```
filepath:linenum:matched_line_content
```

### Scope output format

```
  filepath:linenum
    scope → SCOPE_LINE_NUM: def/function declaration
    match → matched line content
```

### File map format

```
    N hits  filepath
  Total: N files
```

---

## Global Variables Set at Runtime

| Variable | Type | Set by | Used by |
|---|---|---|---|
| `WORD` | string | arg parse | all features |
| `ROOT` | string | arg parse | all features |
| `LANG` | string | arg parse | glob/type selection |
| `MODE` | string | arg parse | dispatch |
| `CTX` | integer | arg parse | rg -C |
| `INTERACTIVE` | bool | arg parse | dispatch guard |
| `USE_CTAGS` | bool | arg parse | dispatch guard |
| `SHOW_SCOPE` | bool | arg parse | dispatch guard |
| `GLOBS` | array | lang block | rg --include= args |
| `RG_TYPE` | string | lang block | appended to RG_FLAGS |
| `RG_FLAGS` | string | lang block | base rg invocation |
| `WORD_REGEX` | string | build_variants() | all rg -e patterns |
| `ROUTE_INPUT` | string | arg parse | route mode — "VERB /path" or file path |
| `ACTION_INPUT` | string | arg parse | route mode — "Controller#action" |
| `MODEL_INPUT` | string | arg parse | model mode — "Model#method" or "Model" |
| `ROUTE_DEPTH` | integer | arg parse | route/model recursion depth (default: 3) |
| `MODEL_DEPTH` | integer | arg parse | model recursion depth (default: 3) |
| `ASYNC_MODE` | string | arg parse | route mode — mark\|inline\|full |
| `HIGHLIGHT` | bool | arg parse | enable pygmentize highlighting (default: false) |
| `TRACE_VISITED` | string | trace_call_chain() | space-separated "Class#method" visited tracker |

---

## Known Limitations

```
1. No Python, Go, or other language support
2. Scope detector (awk) is heuristic — may miss complex nesting
3. ctags index goes stale when files change (must regenerate manually or via git hook)
4. fzf interactive mode is not automatable (blocks on stdin)
5. WORD_REGEX can become very long for single-token words with no dedup benefit
6. rg --color=always emits ANSI — downstream pipes must strip
7. No JSON output mode (yet)
```

---

## Test Suite

```
file:     codetracer_test.sh
fixtures: tests/fixtures/
          ruby/                    # Ruby fixtures
          js/                      # JS/TS fixtures
          rails_app/               # Rails app fixtures for route tracing
            config/routes.rb
            app/controllers/
            app/services/
            app/jobs/
```

**Run:**
```bash
bash codetracer_test.sh
```

**Suites:**
```
1   Case-variant expansion         (no rg required)
2   Mode: def — Ruby               (requires rg)
3   Mode: def — JS/TS              (requires rg)
4   Mode: def — lang: all          (requires rg)
5   Mode: call                     (requires rg)
6   Mode: flow                     (requires rg)
7   Mode: file                     (requires rg)
8   Mode: full                     (requires rg)
9   Flag: --ctx                    (requires rg)
10  Flag: --scope                  (requires rg)
11  Flag: --help                   (no rg required)
12  Edge cases                     (no rg required)
13  False positive guard           (requires rg)
14  Bug regressions                (no rg required)
15  Optional: ctags                (skipped if ctags absent)
16  Optional: fzf                  (skipped if fzf absent)
17  Definition edge cases          (requires rg)
18  Route: action parsing          (requires rg)
19  Route: callback detection      (requires rg)
20  Route: service/async detection (requires rg)
21  Route: error handling          (requires rg)
22  Route: params detection        (requires rg)
23  Route: curl file parsing       (requires rg)
```

Total: 180 tests across 23 suites.

**Test helper contract:**
- `run()` — executes codetracer, merges stderr, strips ANSI, always returns 0
- `assert_contains label pattern output` — grep -qE; calls pass() or fail()
- `assert_not_contains label pattern output` — inverse
- `assert_min_lines label n output` — wc -l comparison
- `skip label reason` — increments SKIP, prints reason
- Exit code: 0 = all non-skipped passed; 1 = any failure

---

## LLM Usage Patterns

### Minimal context extraction (use before asking an LLM)

```bash
# Definition only — cheapest context
codetracer process_payment . --mode def --ctx 2 2>&1 \
  | sed 's/\x1b\[[0-9;]*[mGKHF]//g' | head -40

# Full flow, scoped — medium context
codetracer process_payment . --mode flow --scope --ctx 2 2>&1 \
  | sed 's/\x1b\[[0-9;]*[mGKHF]//g' | head -80

# Method body only (awk, no codetracer needed)
awk '/def process_payment/,/^  end/' app/services/payment_service.rb

# Compose definition + callers + test into one block
{
  echo "=== DEFINITION ==="
  awk '/def process_payment/,/^  end/' app/services/payment_service.rb
  echo "=== CALLERS ==="
  codetracer process_payment . --mode call --scope 2>&1 \
    | sed 's/\x1b\[[0-9;]*[mGKHF]//g' | head -40
  echo "=== TEST ==="
  rg -A 15 "it.*process_payment" spec/ -n | head -30
}
```

### Answering "where is X defined?"

```bash
codetracer X . --mode def --ctags --lang ruby
# or
codetracer X . --mode def --lang js
```

### Answering "what calls X?"

```bash
codetracer X . --mode call --scope
```

### Answering "how does data flow through X?"

```bash
codetracer X . --mode flow --scope --ctx 3
```

### Answering "how many places does X appear?"

```bash
codetracer X . --mode file
```

---

## Changelog (structural)

| Version | Change |
|---|---|
| initial | Literal WORD search only |
| +variants | `build_variants()` added; `WORD_REGEX` used in all `rg` calls |
| +help-fix | `--help` early exit before `WORD="$1"` (was consumed as symbol) |
| +compat-mac | `declare -A` → `grep -xF`; `grep -P` → `grep -E`; `xargs echo -e` → `printf`; bash guard added |
| +zsh | `setopt SH_WORD_SPLIT KSH_ARRAYS`; dual shell detection; `BASH_SOURCE[0]:-$0` in tests |
| +zsh-array | `words=($tokens)` → `read -ra/-rA` branch; `${words[0]}` → for-loop+`_first` flag |
| +rg-glob | `--include=` → `--glob=` throughout (rg has never had `--include`) |
| +route | `--route` and `--action` flags; `trace_route()` + 10 sub-functions; Rails controller lifecycle tracing |
| +model | `--model` flag; `trace_model()` + 7 extraction functions; model structure tracing |
| +cross-class | `extract_cross_class_calls()` + `trace_call_chain()`; recursive cross-file call tracing with visited tracking |
| +highlight | `--highlight` flag; pygmentize integration (gruvbox-dark, 16-color); batch highlighting for method bodies |
| +curl-values | URL-decode curl query params; show original values as comments; deduplicate array params |
| +new-init | `.new()` calls mapped to `initialize`; class summary fallback for DSL-only classes (serializers) |
