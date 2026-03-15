#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  codetracer — trace words/symbols in Ruby & JS codebases    ║
# ║  Tools: rg, grep, awk, ctags, find, fzf (optional)          ║
# ║  Shells: bash 4+  ·  zsh 5+                                 ║
# ╚══════════════════════════════════════════════════════════════╝
# NOTE ON ZSH: The shebang uses bash for `./codetracer.sh`.
#              Running as `zsh codetracer.sh` also works — the
#              compat block below handles all zsh differences.
set -euo pipefail

# ─── Shell compatibility (bash 4+ or zsh 5+) ─────────────────
if [ -n "${ZSH_VERSION:-}" ]; then
  # ── Running under zsh ──────────────────────────────────────
  # SH_WORD_SPLIT : unquoted $var splits on IFS, like bash
  # KSH_ARRAYS    : arrays become 0-indexed, like bash
  setopt SH_WORD_SPLIT KSH_ARRAYS 2>/dev/null

  # Version check: require zsh 5.0+
  _zsh_major="${ZSH_VERSION%%.*}"
  if (( _zsh_major < 5 )); then
    echo "ERROR: codetracer requires zsh 5.0 or later."
    echo "  Your version : ${ZSH_VERSION}"
    echo "  macOS fix    : zsh is built-in; upgrade macOS or brew install zsh"
    echo "  Linux fix    : sudo apt install zsh  /  sudo pacman -S zsh"
    exit 1
  fi
  unset _zsh_major

elif [ -n "${BASH_VERSION:-}" ]; then
  # ── Running under bash ─────────────────────────────────────
  # macOS ships bash 3.2 by default (GPLv3 licensing reason).
  # Fix: brew install bash
  if (( BASH_VERSINFO[0] < 4 )); then
    echo "ERROR: codetracer requires bash 4.0 or later."
    echo "  Your version : ${BASH_VERSION}"
    echo "  macOS fix    : brew install bash"
    echo "  Alternatively: zsh codetracer.sh  (zsh 5+ also supported)"
    exit 1
  fi

else
  echo "ERROR: unsupported shell. Run with bash 4+ or zsh 5+."
  echo "  bash codetracer.sh <word>"
  echo "  zsh  codetracer.sh <word>"
  exit 1
fi

# ─── Colors ───────────────────────────────────────────────────
RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

# ─── Helpers ──────────────────────────────────────────────────
banner() {
  echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${RESET}"
}

info()    { echo -e "${GREEN}  ➜${RESET} $1"; }
warn()    { echo -e "${YELLOW}  ⚠${RESET}  $1"; }
hit()     { echo -e "${MAGENTA}  ●${RESET} $1"; }
section() { echo -e "\n${BOLD}${BLUE}[$1]${RESET}"; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" &>/dev/null || { warn "Missing: $cmd (some features disabled)"; }
  done
}

usage() {
  cat <<EOF

${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗
║                   codetracer  —  usage guide                     ║
╚══════════════════════════════════════════════════════════════════╝${RESET}

${BOLD}SYNOPSIS${RESET}
  codetracer <word> [path] [options]

  Traces any symbol (method, function, variable, class) across a Ruby
  or JavaScript/TypeScript codebase. Auto-expands the input into all
  naming conventions (snake_case, camelCase, PascalCase, kebab-case,
  SCREAMING_SNAKE, "Title Case") and searches all of them at once.

${BOLD}ARGUMENTS${RESET}
  ${YELLOW}word${RESET}   The symbol to trace. Any casing is accepted — they all resolve
         to the same token set. Quoted phrases are also supported.

           process_payment   processPayment   ProcessPayment
           process-payment   PROCESS_PAYMENT  "process payment"
           → all produce identical search results

  ${YELLOW}path${RESET}   Root directory to search (default: current working directory).
         Relative or absolute paths both work.

${BOLD}OPTIONS${RESET}
  ${GREEN}-m, --mode  <mode>${RESET}     What to look for  (default: full)

    ${CYAN}def${RESET}    Find where the symbol is DEFINED
           Ruby:  def, def self., class, module, lambda, proc
           JS/TS: function, const =, let =, class, async function,
                  export function, export default function

    ${CYAN}call${RESET}   Find every CALL SITE / usage in code
           Catches: word(  .word(  word{  word.method

    ${CYAN}flow${RESET}   Full DATA FLOW trace
           1. Definitions
           2. Assignments & bindings  (x = word, word:, => word)
           3. Passed as argument      (fn(word), word =>)
           4. Returned / yielded      (return word, yield word, resolve(word))
           5. Mutations               (word.push, word.merge!, word.update)

    ${CYAN}file${RESET}   Show which FILES contain the symbol + hit count per file

    ${CYAN}full${RESET}   All of the above combined (default when no --mode given)

  ${GREEN}-l, --lang  <lang>${RESET}     Language filter  (default: all)

    ${CYAN}ruby${RESET}   Only search:  *.rb  *.rake  *.gemspec  Gemfile
    ${CYAN}js${RESET}     Only search:  *.js  *.jsx  *.ts  *.tsx  *.mjs  *.cjs
    ${CYAN}all${RESET}    Search both Ruby and JS/TS files

  ${GREEN}-c, --ctx   <n>${RESET}        Lines of context printed above/below each match
                         (default: 3)

  ${GREEN}-s, --scope${RESET}            For every match, walk backward in the file and
                         print the nearest enclosing def / function name
                         and its line number. Useful to instantly know
                         "which method is this line inside?"

  ${GREEN}-t, --ctags${RESET}            Use ctags for precise symbol definitions.
                         Auto-generates a ./tags index if one doesn't exist.
                         Best combined with --mode def.

  ${GREEN}-i, --inter${RESET}            Interactive fuzzy picker via fzf.
                         Preview window shows ±5 lines of context.
                         Press ENTER to open the selection in \$EDITOR
                         (falls back to nvim → vim → code).
                         Requires: fzf

  ${GREEN}-h, --help${RESET}             Print this help and exit

${BOLD}ROUTE TRACING (Rails)${RESET}
  ${GREEN}--route  <route>${RESET}        Trace a Rails route through the request lifecycle.
                         Format: "VERB /path" (e.g., "POST /orders/:id/refund")
                         OR: path to a shell file containing a curl command
                         Parses config/routes.rb to resolve controller#action.

                         Curl file support:
                           - Extracts HTTP verb and path from curl URL
                           - Converts numeric IDs to :id (e.g., /orders/123 → /orders/:id)
                           - Extracts query params from URL (?key=value)
                           - Extracts body params from -d '{"key": ...}'
                           - Shows expected params in trace output

  ${GREEN}--action <action>${RESET}       Trace a controller action directly.
                         Format: "Controller#action" (e.g., "OrdersController#refund")
                         Supports namespaced controllers (Admin::OrdersController#show)

  ${GREEN}--depth  <n>${RESET}            Recursion depth for nested service/job traces
                         (default: 3)
                           0 = unlimited (use with caution)
                           1 = callbacks + action body only
                           3 = typical depth for most codebases

  ${GREEN}--async  <mode>${RESET}         How to display async jobs (default: mark)
                           mark   = show [async] marker
                           inline = show job class name inline
                           full   = expand job's perform method

  ${GREEN}--highlight${RESET}              Enable syntax highlighting via pygmentize
                           Uses gruvbox-dark theme with 16-color terminal
                           Requires: pygmentize (pip install Pygments)

  Route trace output shows:
    ├── before_action callbacks (with origins: [ApplicationController], [Concern])
    ├── around_action callbacks
    ├── def action_name
    │   ├── params: :key              [query]  ← params[:key], params.fetch, params.require
    │   ├── permit: :a, :b, :c        [query]  ← .permit() allowed attributes
    │   ├── conditionals (if/unless/case)
    │   ├── service calls (ServiceClass.call)
    │   └── async jobs (Job.perform_async) [async]
    └── after_action callbacks

${BOLD}CASE-VARIANT EXPANSION${RESET}
  Every run prints the expanded variants table so you can verify
  what was actually searched. Example for input "processPayment":

    snake_case       process_payment
    SCREAMING_SNAKE  PROCESS_PAYMENT
    camelCase        processPayment
    PascalCase       ProcessPayment
    kebab-case       process-payment
    Title Case       Process Payment
    space sep        process payment

  All variants are joined into one regex alternation and passed to
  every rg -e call — no double scanning, one pass per feature.

${BOLD}REQUIRED TOOLS${RESET}
  ${GREEN}rg${RESET}  (ripgrep)   — fast search engine     brew install ripgrep
  ${GREEN}awk${RESET}             — scope walking          built-in
  ${GREEN}grep${RESET}            — tag file lookups       built-in
  ${GREEN}find${RESET}            — file discovery         built-in

${BOLD}OPTIONAL TOOLS${RESET}
  ${CYAN}fzf${RESET}              — interactive mode       brew install fzf
  ${CYAN}ctags${RESET}            — precise definitions    brew install universal-ctags

${BOLD}EXAMPLES${RESET}

  ${DIM}── Basic ──────────────────────────────────────────────────────────${RESET}

  # Trace a symbol in the current directory (all modes, all langs)
  codetracer process_payment

  # Same — casing doesn't matter, all variants searched
  codetracer processPayment
  codetracer ProcessPayment
  codetracer "process payment"

  # Trace inside a specific folder
  codetracer render_invoice ./app

  ${DIM}── Mode: def ──────────────────────────────────────────────────────${RESET}

  # Find where a Ruby method is defined
  codetracer charge_card . --lang ruby --mode def

  # Find where a JS/TS function is defined
  codetracer fetchUser ./src --lang js --mode def

  # Find a class definition across all files
  codetracer InvoiceService . --mode def

  # Precise definition with ctags index
  codetracer PaymentGateway . --mode def --ctags

  ${DIM}── Mode: call ─────────────────────────────────────────────────────${RESET}

  # Find every call site for a method
  codetracer send_email . --mode call

  # Call sites in JS only, with 5 lines of context
  codetracer handleError ./src --lang js --mode call --ctx 5

  # Call sites + which function each one lives inside
  codetracer validate_token . --mode call --scope

  ${DIM}── Mode: flow ─────────────────────────────────────────────────────${RESET}

  # Full data flow: where defined, assigned, passed, returned, mutated
  codetracer current_user . --mode flow

  # Data flow in Ruby only
  codetracer order_items . --lang ruby --mode flow

  # Flow + enclosing scope labels on every match
  codetracer payload ./api --mode flow --scope

  ${DIM}── Mode: file ─────────────────────────────────────────────────────${RESET}

  # Which files contain this symbol and how many times?
  codetracer stripe_key . --mode file

  # File map limited to JS source
  codetracer apiClient ./frontend --lang js --mode file

  ${DIM}── Combining flags ────────────────────────────────────────────────${RESET}

  # Definitions + ctags, Ruby only, tight context
  codetracer after_save . --lang ruby --mode def --ctags --ctx 1

  # Full trace in JS, with scope labels, wide context
  codetracer useAuthStore ./src --lang js --mode full --scope --ctx 6

  # All modes, precise definitions, scope labels
  codetracer order_total . --mode full --ctags --scope

  ${DIM}── Interactive mode ───────────────────────────────────────────────${RESET}

  # Fuzzy-pick any match and open it in your editor
  codetracer render . --inter

  # Narrow to JS before going interactive
  codetracer dispatch ./store --lang js --inter

  ${DIM}── Token-saving workflow (minimal LLM context) ───────────────────${RESET}

  # Get only the 60 most relevant lines to paste into an AI chat
  codetracer processOrder . --mode flow --scope 2>&1 | head -60

  # Dump definitions to a file for later review
  codetracer Invoice . --mode def --ctags > /tmp/invoice_defs.txt

  # Quick file map then open the most-hit file
  codetracer session_token . --mode file

  ${DIM}── Route tracing (Rails) ──────────────────────────────────────────${RESET}

  # Trace a route through the full request lifecycle
  codetracer --route "POST /orders/:id/refund" ./app

  # Trace from a curl file (extracts verb, path, query/body params)
  codetracer --route ./curls/create_order.sh ./app

  # Trace a controller action directly
  codetracer --action "OrdersController#refund" ./app

  # Trace with deeper recursion into services
  codetracer --action "CheckoutController#create" ./app --depth 5

  # Trace a namespaced admin controller
  codetracer --action "Admin::UsersController#destroy" ./app

  # Show full async job expansion
  codetracer --action "OrdersController#ship" ./app --async full

EOF
  exit 0
}

# ─── Defaults ─────────────────────────────────────────────────
WORD=""
ROOT="."
LANG="all"
MODE="full"
CTX=3
INTERACTIVE=false
USE_CTAGS=false
SHOW_SCOPE=false

# Route tracing defaults
ROUTE_INPUT=""
ACTION_INPUT=""
ROUTE_DEPTH=3
ASYNC_MODE="mark"

# Model tracing defaults
MODEL_INPUT=""
MODEL_CLASS=""
MODEL_METHOD=""
MODEL_DEPTH=3
HIGHLIGHT=false

# Curl parsing results (populated by parse_curl_file)
CURL_VERB=""
CURL_PATH=""
CURL_QUERY_PARAMS=""
CURL_BODY_PARAMS=""

# ─── Arg Parse ────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

# Handle --help / -h before consuming the first positional arg as WORD
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

# Check if first arg is --route, --action, or --model (no WORD required)
if [[ "${1:-}" == "--route" || "${1:-}" == "--action" || "${1:-}" == "--model" ]]; then
  WORD=""  # No word for route/model tracing mode
else
  WORD="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--lang)    LANG="$2";        shift 2 ;;
    -m|--mode)    MODE="$2";        shift 2 ;;
    -c|--ctx)     CTX="$2";         shift 2 ;;
    -i|--inter)   INTERACTIVE=true; shift ;;
    -t|--ctags)   USE_CTAGS=true;   shift ;;
    -s|--scope)   SHOW_SCOPE=true;  shift ;;
    -h|--help)    usage ;;
    --route)      ROUTE_INPUT="$2"; MODE="route"; shift 2 ;;
    --action)     ACTION_INPUT="$2"; MODE="route"; shift 2 ;;
    --model)      MODEL_INPUT="$2"; MODE="model"; shift 2 ;;
    --depth)      ROUTE_DEPTH="$2"; MODEL_DEPTH="$2"; shift 2 ;;
    --async)      ASYNC_MODE="$2"; shift 2 ;;
    --highlight)  HIGHLIGHT=true; shift ;;
    -*)           warn "Unknown option: $1"; shift ;;
    *)            ROOT="$1";        shift ;;
  esac
done

# ─── Auto-detect Rails root ────────────────────────────────────
# If ROOT doesn't contain config/routes.rb, walk up to find the Rails root.
# This allows passing ./app or any subdirectory as ROOT.
if [[ ("$MODE" == "route" || "$MODE" == "model") && ! -f "$ROOT/config/routes.rb" ]]; then
  _check_dir="$(cd "$ROOT" 2>/dev/null && pwd)"
  while [[ -n "$_check_dir" && "$_check_dir" != "/" ]]; do
    if [[ -f "$_check_dir/config/routes.rb" ]]; then
      ROOT="$_check_dir"
      break
    fi
    _check_dir="${_check_dir%/*}"
  done
  unset _check_dir
fi

# ─── Tool check ───────────────────────────────────────────────
require rg grep awk find
$INTERACTIVE && require fzf
$USE_CTAGS   && require ctags

# ─── Language globs ───────────────────────────────────────────
case "$LANG" in
  ruby) GLOBS=("*.rb" "*.rake" "*.gemspec" "Gemfile")
        RG_TYPE="--type ruby" ;;
  js)   GLOBS=("*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs" "*.cjs")
        RG_TYPE="--type js --type ts" ;;
  all)  GLOBS=("*.rb" "*.rake" "*.js" "*.jsx" "*.ts" "*.tsx" "*.mjs")
        RG_TYPE="" ;;
  *)    warn "Unknown lang '$LANG', using all"; GLOBS=(); RG_TYPE="" ;;
esac

# ─── Build rg flags ───────────────────────────────────────────
RG_FLAGS="--color=always --line-number --smart-case"
[[ -n "$RG_TYPE" ]] && RG_FLAGS="$RG_FLAGS $RG_TYPE"

# ═══════════════════════════════════════════════════════════════
#  CASE-VARIANT EXPANDER
#  Input: any of snake_case / camelCase / PascalCase /
#         kebab-case / "space words" / SCREAMING_SNAKE
#  Output: WORD_REGEX = alternation of all detected forms
#
#  Strategy:
#   1. Tokenize input into lowercase words[]
#   2. Reconstruct every naming convention
#   3. Build regex: (form1|form2|form3|...)
# ═══════════════════════════════════════════════════════════════
build_variants() {
  local raw="$1"

  # ── Tokenize: split on _, -, space, then split camelCase/PascalCase ──
  # Step 1: replace - and _ and space with space
  local normalized
  normalized=$(echo "$raw" | sed 's/[-_ ]/ /g')

  # Step 2: insert space before uppercase letters (handles camel/pascal)
  # e.g. processPayment → process Payment → process payment
  normalized=$(echo "$normalized" \
    | sed 's/\([a-z0-9]\)\([A-Z]\)/\1 \2/g' \
    | sed 's/\([A-Z]\)\([A-Z][a-z]\)/\1 \2/g')

  # Step 3: lowercase everything → array of tokens
  local tokens
  tokens=$(echo "$normalized" | tr '[:upper:]' '[:lower:]' | tr -s ' ')
  # Remove leading/trailing whitespace
  tokens=$(echo "$tokens" | sed 's/^ //;s/ $//')

  # ── Build words array (portable bash + zsh) ─────────────────
  # Problem: zsh does NOT word-split unquoted vars in array assignment
  # even with SH_WORD_SPLIT set — that option only affects simple
  # command contexts, not `arr=(...)` assignments.
  # Fix: use `read -ra` (bash) / `read -rA` (zsh) which both split
  # on IFS (space) into an array, regardless of shell.
  local words=()
  if [ -n "${ZSH_VERSION:-}" ]; then
    read -rA words <<< "$tokens"
  else
    read -ra words <<< "$tokens"
  fi
  local n=${#words[@]}

  # snake_case: process_payment
  local snake
  snake=$(IFS=_; echo "${words[*]}")

  # SCREAMING_SNAKE: PROCESS_PAYMENT
  local screaming
  screaming=$(echo "$snake" | tr '[:lower:]' '[:upper:]')

  # camelCase: processPayment
  # Avoid ${words[0]} — bash is 0-indexed, zsh read -A is 1-indexed.
  # Use a for-loop with a first-element flag instead: portable on both.
  local camel="" _first=true
  for w in "${words[@]}"; do
    if $_first; then
      camel="$w"
      _first=false
    else
      camel+="$(printf '%s' "${w:0:1}" | tr '[:lower:]' '[:upper:]')${w:1}"
    fi
  done
  unset _first

  # PascalCase: ProcessPayment
  local pascal=""
  for w in "${words[@]}"; do
    pascal+="$(echo "${w:0:1}" | tr '[:lower:]' '[:upper:]')${w:1}"
  done

  # kebab-case: process-payment
  local kebab
  kebab=$(IFS=-; echo "${words[*]}")

  # Title Case (space): Process Payment
  local title=""
  for w in "${words[@]}"; do
    title+="$(echo "${w:0:1}" | tr '[:lower:]' '[:upper:]')${w:1} "
  done
  title="${title% }"  # trim trailing space

  # lowercase space: process payment
  local spaced
  spaced=$(IFS=' '; echo "${words[*]}")

  # ── Deduplicate variants (portable: no declare -A needed) ────
  # Works on bash 4+ and is safe on macOS with brew bash
  local seen_list=""
  local variants=()
  for v in "$snake" "$screaming" "$camel" "$pascal" "$kebab" "$title" "$spaced"; do
    [[ -z "$v" ]] && continue
    # Check if v is already in seen_list (delimited by newlines)
    if ! printf '%s\n' "$seen_list" | grep -qxF "$v"; then
      seen_list="${seen_list}${v}"$'\n'
      variants+=("$v")
    fi
  done

  # ── Print summary ──
  section "Case variants detected for: ${BOLD}$raw${RESET}"
  local labels=("snake_case" "SCREAMING_SNAKE" "camelCase" "PascalCase" "kebab-case" "Title Case" "space sep")
  local idx=0
  for v in "${variants[@]}"; do
    printf "  ${DIM}%-16s${RESET}  ${YELLOW}%s${RESET}\n" "${labels[$idx]:-variant}" "$v"
    idx=$(( idx + 1 ))
  done

  # ── Return regex alternation ──
  # Escape special regex chars in each variant (spaces → \s+ for robustness)
  local regex_parts=()
  local escaped
  for v in "${variants[@]}"; do
    # escape dots and parens, leave the rest
    escaped=$(printf '%s' "$v" | sed 's/[.()[\^$*+?{}|\\]/\\&/g')
    # space-separated variant: match literal space OR underscore OR camel boundary
    regex_parts+=("$escaped")
  done

  # Join with |
  local IFS='|'
  WORD_REGEX="(${regex_parts[*]})"

  # Loose regex: matches identifiers CONTAINING any variant (with optional prefix/suffix)
  local loose_parts=()
  for v in "${regex_parts[@]}"; do
    loose_parts+=("\\w*${v}\\w*")
  done
  IFS='|'
  WORD_REGEX_LOOSE="(${loose_parts[*]})"
}

# Run it — replaces $WORD usage with $WORD_REGEX in all searches
# Skip for route/model mode which doesn't use WORD
if [[ "$MODE" != "route" && "$MODE" != "model" ]]; then
  build_variants "$WORD"
  echo -e "  ${DIM}regex: ${RESET}${CYAN}$WORD_REGEX${RESET}"
fi

# ═══════════════════════════════════════════════════════════════
#  FEATURE 1 — DEFINITION LOCATOR
#  Finds where a method/function/class is DEFINED
# ═══════════════════════════════════════════════════════════════
find_definitions() {
  banner "DEFINITIONS of: $WORD  ${DIM}→ regex: $WORD_REGEX${RESET}"

  # Ruby patterns (use WORD_REGEX_LOOSE for lambda/proc to catch suffixed identifiers)
  RUBY_DEF="^\s*(def\s+${WORD_REGEX_LOOSE}|def\s+self\.${WORD_REGEX_LOOSE}|class\s+${WORD_REGEX_LOOSE}|module\s+${WORD_REGEX_LOOSE}|${WORD_REGEX_LOOSE}\s*=\s*lambda|${WORD_REGEX_LOOSE}\s*=\s*proc)"
  # JS/TS patterns (use WORD_REGEX_LOOSE for identifiers that may have suffixes)
  JS_DEF="(function\s+${WORD_REGEX_LOOSE}[\s(]|const\s+${WORD_REGEX_LOOSE}\s*=\s*(async\s+)?(\(|function)|let\s+${WORD_REGEX_LOOSE}\s*=|var\s+${WORD_REGEX_LOOSE}\s*=|${WORD_REGEX_LOOSE}\s*:\s*(async\s+)?function|async\s+function\s+${WORD_REGEX_LOOSE}\s*\(|^\s*(export\s+)?(default\s+)?function\s+${WORD_REGEX_LOOSE}|class\s+${WORD_REGEX_LOOSE}[\s{])"

  local found=false

  # Ruby defs
  if [[ "$LANG" == "ruby" || "$LANG" == "all" ]]; then
    section "Ruby Definitions"
    local ruby_output
    ruby_output=$(rg $RG_FLAGS -e "$RUBY_DEF" "$ROOT" --glob="*.rb" --glob="*.rake" -C "$CTX" 2>/dev/null) || true
    if [[ -n "$ruby_output" ]]; then
      # Show enclosing class/module from files with matching defs
      local def_files
      def_files=$(rg --color=never --no-line-number -l -e "$RUBY_DEF" "$ROOT" --glob="*.rb" --glob="*.rake" 2>/dev/null) || true
      if [[ -n "$def_files" ]]; then
        local enclosing
        enclosing=$(echo "$def_files" | while read -r f; do
          rg --color=always --line-number -e "^\s*(class|module)\s+\w+" "$f" 2>/dev/null
        done) || true
        [[ -n "$enclosing" ]] && echo "$enclosing"
      fi
      echo "$ruby_output"
      found=true
    else
      info "No Ruby definitions found."
    fi
  fi

  # JS/TS defs
  if [[ "$LANG" == "js" || "$LANG" == "all" ]]; then
    section "JS/TS Definitions"
    local js_output
    js_output=$(rg $RG_FLAGS -e "$JS_DEF" "$ROOT" --glob="*.js" --glob="*.jsx" --glob="*.ts" --glob="*.tsx" -C "$CTX" 2>/dev/null) || true
    if [[ -n "$js_output" ]]; then
      # Show enclosing class from files with matching defs
      local def_files
      def_files=$(rg --color=never --no-line-number -l -e "$JS_DEF" "$ROOT" --glob="*.js" --glob="*.jsx" --glob="*.ts" --glob="*.tsx" 2>/dev/null) || true
      if [[ -n "$def_files" ]]; then
        local enclosing
        enclosing=$(echo "$def_files" | while read -r f; do
          rg --color=always --line-number -e "^\s*((export\s+)?class\s+\w+)" "$f" 2>/dev/null
        done) || true
        [[ -n "$enclosing" ]] && echo "$enclosing"
      fi
      echo "$js_output"
      found=true
    else
      info "No JS/TS definitions found."
    fi
  fi

  $found || warn "No definitions found for: $WORD"
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 2 — CALL SITES
#  Finds every place the symbol is CALLED/USED
# ═══════════════════════════════════════════════════════════════
find_calls() {
  banner "CALL SITES of: $WORD"
  CALL_PAT="${WORD_REGEX}[(\s.{]|\.${WORD_REGEX}[(\s]|${WORD_REGEX}\b"

  local args=($RG_FLAGS -e "$CALL_PAT" "$ROOT" -C "$CTX")
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args+=("--glob=$g"); done

  section "All call sites"
  if rg "${args[@]}" 2>/dev/null | grep -q .; then
    rg "${args[@]}" 2>/dev/null
  else
    info "No call sites found."
  fi
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 3 — DATA FLOW
#  Traces: definitions → assignments → calls → returns
# ═══════════════════════════════════════════════════════════════
find_flow() {
  banner "DATA FLOW for: $WORD"

  section "1. Assignments / bindings"
  ASSIGN_PAT="(${WORD_REGEX_LOOSE}\s*=(?!=)|=>\s*${WORD_REGEX_LOOSE}|${WORD_REGEX_LOOSE}:)"
  local args=($RG_FLAGS -e "$ASSIGN_PAT" "$ROOT" -C 1)
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args+=("--glob=$g"); done
  rg "${args[@]}" 2>/dev/null || info "No assignments found."

  section "2. As argument / passed in"
  PASS_PAT="[,(]\s*${WORD_REGEX}\s*[,)]|\b${WORD_REGEX}\b.*=>"
  local args2=($RG_FLAGS -e "$PASS_PAT" "$ROOT" -C 1)
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args2+=("--glob=$g"); done
  rg "${args2[@]}" 2>/dev/null || info "No pass-as-argument found."

  section "3. Returned / yielded"
  RET_PAT="(return\s+${WORD_REGEX_LOOSE}|yield\s+${WORD_REGEX_LOOSE}|resolve\(${WORD_REGEX}|emit.*${WORD_REGEX})"
  local args3=($RG_FLAGS -e "$RET_PAT" "$ROOT" -C 1)
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args3+=("--glob=$g"); done
  rg "${args3[@]}" 2>/dev/null || info "No return/yield found."

  section "4. Mutations"
  MUT_PAT="(${WORD_REGEX_LOOSE}\.(push|pop|shift|unshift|merge!|update|delete|destroy|append|prepend|replace|set|clear)\b|\.(push|pop|shift|unshift|merge!|update|delete|destroy|append|prepend|replace|set|clear)\(${WORD_REGEX_LOOSE})"
  local args4=($RG_FLAGS -e "$MUT_PAT" "$ROOT" -C 1)
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args4+=("--glob=$g"); done
  rg "${args4[@]}" 2>/dev/null || info "No mutations found."
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 4 — FILE MAP
#  Which files contain the word + count per file
# ═══════════════════════════════════════════════════════════════
find_files() {
  banner "FILE MAP for: $WORD"

  local args=(--color=never --smart-case -l "$ROOT" -e "$WORD_REGEX")
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args+=("--glob=$g"); done

  section "Files containing '$WORD_REGEX'"
  local files
  files=$(rg "${args[@]}" 2>/dev/null) || true

  if [[ -z "$files" ]]; then
    info "No files found."; return
  fi

  local count
  echo "$files" | while read -r f; do
    count=$(rg --count --smart-case -e "$WORD_REGEX" "$f" 2>/dev/null || echo 0)
    printf "  ${GREEN}%4s hits${RESET}  %s\n" "$count" "$f"
  done

  local total
  total=$(echo "$files" | wc -l | tr -d ' ')
  printf "  \033[1mTotal: %s files\033[0m\n" "$total"
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 5 — SCOPE DETECTOR
#  For each match, build a breadcrumb scope chain showing all
#  nesting levels from module/class down to the match line.
#  Format: mod Billing:5 > cls PaymentService:6 > def batch_process:38 > blk each:39
# ═══════════════════════════════════════════════════════════════
show_enclosing_scope() {
  banner "ENCLOSING SCOPE for matches of: $WORD"
  info "Scanning for '$WORD' and resolving scope chain..."

  local args=(--color=never --smart-case --line-number "$ROOT" -e "$WORD_REGEX")
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args+=("--glob=$g"); done

  local scope
  rg "${args[@]}" 2>/dev/null | while IFS=: read -r file lineno rest; do
    scope=$(awk -v target="$lineno" '
      NR <= target {
        line = $0
        # measure indentation (tabs -> 2 spaces)
        gsub(/\t/, "  ", line)
        indent = 0
        while (substr(line, indent+1, 1) == " ") indent++

        trimmed = $0
        gsub(/^[ \t]+/, "", trimmed)

        # ── Detect scope closing: end (Ruby) or } (JS) ──
        if (trimmed ~ /^end( |$)/ || trimmed ~ /^\}/) {
          new_n = 0
          for (i = 1; i <= n; i++) {
            if (scope_indent[i] < indent) {
              new_n++
              scope_label[new_n] = scope_label[i]
              scope_indent[new_n] = scope_indent[i]
              scope_line[new_n] = scope_line[i]
            }
          }
          n = new_n
        }

        label = ""

        # ── Ruby: module / class ──
        if (trimmed ~ /^module /) {
          name = trimmed; sub(/^module /, "", name); sub(/[< \t].*/, "", name)
          label = "mod " name
        }
        else if (trimmed ~ /^class /) {
          name = trimmed; sub(/^class /, "", name); sub(/[< \t{(].*/, "", name)
          label = "cls " name
        }
        # ── Ruby: def self. / def ──
        else if (trimmed ~ /^def self\./) {
          name = trimmed; sub(/^def self\./, "", name); sub(/[( \t].*/, "", name)
          label = "defs " name
        }
        else if (trimmed ~ /^def /) {
          name = trimmed; sub(/^def /, "", name); sub(/[( \t].*/, "", name)
          label = "def " name
        }
        # ── Ruby: lambda / proc ──
        else if (trimmed ~ /= *lambda[ {(]/ || trimmed ~ /= *lambda$/) {
          name = trimmed; sub(/ *=.*/, "", name)
          label = "lam " name
        }
        else if (trimmed ~ /= *proc[ {(]/ || trimmed ~ /= *proc$/) {
          name = trimmed; sub(/ *=.*/, "", name)
          label = "prc " name
        }
        # ── JS: async function ──
        else if (trimmed ~ /^async function /) {
          name = trimmed; sub(/^async function /, "", name); sub(/[( \t].*/, "", name)
          label = "async " name
        }
        # ── JS: export / function ──
        else if (trimmed ~ /^(export )?(default )?function /) {
          name = trimmed
          sub(/^export /, "", name); sub(/^default /, "", name)
          sub(/^function /, "", name); sub(/[( \t{].*/, "", name)
          label = "fn " name
        }
        # ── JS: const arrow / const function ──
        else if (trimmed ~ /^const [A-Za-z_$][A-Za-z0-9_$]* *= *(async *)?[\(f]/) {
          name = trimmed; sub(/^const /, "", name); sub(/ *=.*/, "", name)
          label = "fn " name
        }
        # ── JS: class method — name(args) { (exclude keywords) ──
        else if (trimmed ~ /^[a-zA-Z_$][a-zA-Z0-9_$]*[ \t]*\(.*\).*\{[ \t]*$/ && trimmed !~ /^(if|else|for|while|switch|catch|return|throw|do|new) *\(/) {
          name = trimmed; sub(/[ \t]*\(.*/, "", name)
          label = "def " name
        }
        # ── JS: async class method — async name(args) { (not async function) ──
        else if (trimmed ~ /^async [a-zA-Z_$][a-zA-Z0-9_$]*[ \t]*\(/ && trimmed !~ /^async function /) {
          name = trimmed; sub(/^async /, "", name); sub(/[ \t]*\(.*/, "", name)
          label = "async " name
        }
        # ── Ruby: block (do |...|) ──
        else if (trimmed ~ / do( *\|.*\|)?[ \t]*$/) {
          name = trimmed; sub(/ do.*/, "", name)
          if (name ~ /\./) { sub(/.*\./, "", name) }
          sub(/[( ].*/, "", name)
          label = "blk " name
        }
        # ── JS: for / while loop ──
        else if (trimmed ~ /^for *\(/) { label = "loop for" }
        else if (trimmed ~ /^while *\(/) { label = "loop while" }
        # ── Ruby: while / until ──
        else if (trimmed ~ /^while /) { label = "loop while" }
        else if (trimmed ~ /^until /) { label = "loop until" }
        # ── Conditionals ──
        else if (trimmed ~ /^if[ (]/) {
          cond = trimmed; sub(/^if */, "", cond); sub(/[;){].*/, "", cond)
          if (length(cond) > 30) cond = substr(cond, 1, 27) "..."
          label = "if " cond
        }
        else if (trimmed ~ /^unless /) {
          cond = trimmed; sub(/^unless /, "", cond); sub(/[;){].*/, "", cond)
          if (length(cond) > 30) cond = substr(cond, 1, 27) "..."
          label = "unless " cond
        }
        else if (trimmed ~ /^case[ \t]/) { label = "case" }
        else if (trimmed ~ /^switch *\(/) { label = "switch" }
        # ── Error handling ──
        else if (trimmed ~ /^begin[ \t]*$/) { label = "begin" }
        else if (trimmed ~ /^rescue /) {
          name = trimmed; sub(/^rescue /, "", name); sub(/ .*/, "", name)
          label = "rescue " name
        }
        else if (trimmed ~ /^try *{/) { label = "try" }
        else if (trimmed ~ /^catch *\(/) {
          name = trimmed; sub(/^catch *\(/, "", name); sub(/\).*/, "", name)
          label = "catch " name
        }

        if (label != "") {
          # Pop scopes at indent >= current (they closed before this line)
          new_n = 0
          for (i = 1; i <= n; i++) {
            if (scope_indent[i] < indent) {
              new_n++
              scope_label[new_n] = scope_label[i]
              scope_indent[new_n] = scope_indent[i]
              scope_line[new_n] = scope_line[i]
            }
          }
          n = new_n
          # Push new scope
          n++
          scope_label[n] = label
          scope_indent[n] = indent
          scope_line[n] = NR
        }
      }
      END {
        if (n == 0) {
          print "? (top-level)"
        } else {
          result = ""
          for (i = 1; i <= n; i++) {
            if (result != "") result = result " > "
            result = result scope_label[i] ":" scope_line[i]
          }
          print result
        }
      }
    ' "$file" 2>/dev/null)

    printf "  ${CYAN}%s${RESET}:${YELLOW}%s${RESET}\n    ${DIM}scope -> %s${RESET}\n    ${DIM}match -> %s${RESET}\n\n" \
      "$file" "$lineno" "$scope" "$rest"
  done
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 6 — CTAGS PRECISE DEFINITIONS
# ═══════════════════════════════════════════════════════════════
ctags_lookup() {
  banner "CTAGS LOOKUP for: $WORD"

  local tagfile="$ROOT/tags"
  if [[ ! -f "$tagfile" ]]; then
    info "Generating ctags index in $ROOT ..."
    (cd "$ROOT" && ctags -R --languages=Ruby,JavaScript,TypeScript \
      --exclude=node_modules --exclude=.git --exclude=vendor \
      -f tags . 2>/dev/null)
  fi

  section "Tag entries"
  if grep -E "^${WORD_REGEX}"$'\t' "$tagfile" 2>/dev/null | grep -q .; then
    local lineno
    grep -E "^${WORD_REGEX}"$'\t' "$tagfile" | while IFS=$'\t' read -r tag file pattern rest; do
      lineno=$(grep -n "${WORD_REGEX}" "$ROOT/$file" 2>/dev/null | head -1 | cut -d: -f1)
      printf "  ${BOLD}%-30s${RESET}  ${GREEN}%s${RESET}  ${DIM}line ~%s${RESET}\n" \
        "$tag" "$file" "${lineno:-?}"
    done
  else
    warn "No ctags entry found for: $WORD_REGEX"
    info "Try running: ctags -R --languages=Ruby,JavaScript,TypeScript ."
  fi
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 7 — INTERACTIVE FZF MODE
# ═══════════════════════════════════════════════════════════════
interactive_mode() {
  banner "INTERACTIVE MODE (fzf)"
  info "Fuzzy-select a match to open in your editor..."

  local args=(--color=always --smart-case --line-number "$ROOT" -e "$WORD_REGEX")
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args+=("--glob=$g"); done

  local selection
  selection=$(rg "${args[@]}" 2>/dev/null \
    | fzf --ansi \
          --preview 'f=$(echo {} | cut -d: -f1); l=$(echo {} | cut -d: -f2); rg --color=always -n -C 5 '"$WORD"' "$f" | grep -A5 -B5 "^$l:"' \
          --preview-window=right:60% \
          --prompt="  $WORD > " \
          --header="ENTER=open  ESC=quit") || true

  if [[ -n "$selection" ]]; then
    local file lineno
    file=$(echo "$selection" | cut -d: -f1)
    lineno=$(echo "$selection" | cut -d: -f2)
    echo -e "\n${GREEN}Selected:${RESET} $file:$lineno"

    # Try to open in editor
    if command -v "$EDITOR" &>/dev/null; then
      "$EDITOR" +"$lineno" "$file"
    elif command -v nvim &>/dev/null; then
      nvim +"$lineno" "$file"
    elif command -v vim &>/dev/null; then
      vim +"$lineno" "$file"
    elif command -v code &>/dev/null; then
      code --goto "$file:$lineno"
    else
      warn "No editor found. Set \$EDITOR env var."
      echo "  File: $file  Line: $lineno"
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE 8 — ROUTE TRACING
#  Traces Rails routes through controller lifecycle
# ═══════════════════════════════════════════════════════════════

# Tree drawing characters
TREE_VERT="│"
TREE_BRANCH="├──"
TREE_LAST="└──"
TREE_SPACE="    "

# Visited files tracker (prevents infinite recursion)
VISITED_FILES=""

# ─── Pygmentize highlight helpers ─────────────────────────────
# Highlights a block of Ruby code via pygmentize (16-color, gruvbox-dark)
highlight_ruby() {
  if [[ "$HIGHLIGHT" == "true" ]] && command -v pygmentize &>/dev/null; then
    pygmentize -l ruby -f terminal -O style=gruvbox-dark 2>/dev/null || cat
  else
    cat
  fi
}

# Highlight a single line of Ruby code (strips trailing newline)
highlight_ruby_line() {
  local line="$1"
  if [[ "$HIGHLIGHT" == "true" ]] && command -v pygmentize &>/dev/null; then
    echo "$line" | pygmentize -l ruby -f terminal -O style=gruvbox-dark 2>/dev/null | tr -d '\n'
  else
    printf "%s" "$line"
  fi
}

# Extract raw method body (no formatting, just the Ruby lines)
extract_method_body() {
  local file="$1"
  local action="$2"
  awk -v action="$action" '
    BEGIN { in_method = 0; method_indent = -1 }
    {
      original = $0
      match(original, /^[ \t]*/)
      curr = RLENGTH
    }
    /^[ \t]*def (self\.)?[a-z_]+/ {
      if (in_method == 0) {
        name = original
        gsub(/^[ \t]*def[ \t]+/, "", name)
        gsub(/[ \t\(].*/, "", name)
        match_name = name
        gsub(/^self\./, "", match_name)
        if (match_name == action) {
          in_method = 1
          method_indent = curr
          print original
          next
        }
      }
    }
    in_method == 1 {
      if (original ~ /^[ \t]*end[ \t]*$/ && curr <= method_indent) {
        print original
        exit
      }
      if (original ~ /^[ \t]*def (self\.)?[a-z_]+/ && curr <= method_indent) {
        exit
      }
      print original
    }
  ' "$file"
}

# ─── Tree line formatter ───────────────────────────────────────
format_tree_line() {
  local depth="$1"
  local is_last="$2"
  local content="$3"
  local line_num="$4"
  local extra="${5:-}"

  local prefix=""
  local i
  for ((i=0; i<depth-1; i++)); do
    prefix+="${TREE_VERT}   "
  done

  if [[ "$is_last" == "true" ]]; then
    prefix+="${TREE_LAST} "
  else
    prefix+="${TREE_BRANCH} "
  fi

  # When highlight mode is on, re-highlight content as Ruby
  if [[ "$HIGHLIGHT" == "true" ]] && command -v pygmentize &>/dev/null; then
    # Strip existing ANSI from content, highlight as Ruby
    local raw_content
    raw_content=$(printf "%s" "$content" | sed $'s/\033\\[[0-9;]*m//g')
    content=$(printf "%s" "$raw_content" | pygmentize -l ruby -f terminal -O style=gruvbox-dark 2>/dev/null | tr -d '\n') || content="$raw_content"
  fi

  if [[ -n "$line_num" ]]; then
    printf "%s%s${DIM}:%s${RESET}" "$prefix" "$content" "$line_num"
  else
    printf "%s%s" "$prefix" "$content"
  fi

  if [[ -n "$extra" ]]; then
    printf "  ${DIM}%s${RESET}" "$extra"
  fi
  printf "\n"
}

# ─── Find controller file from name ────────────────────────────
find_controller_file() {
  local name="$1"
  # Convert PascalCase to snake_case: OrdersController → orders_controller
  local snake
  snake=$(echo "$name" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:upper:]' '[:lower:]')
  # Handle namespaces (:: → /)
  local path
  path=$(echo "$snake" | sed 's/::/\//g')
  # Search in app/controllers
  local file="$ROOT/app/controllers/${path}.rb"
  if [[ -f "$file" ]]; then
    echo "$file"
  else
    # Try finding with find command
    find "$ROOT" -path "*/controllers/*${path}.rb" -type f 2>/dev/null | head -1
  fi
}

# ─── Find model file from name ──────────────────────────────────
find_model_file() {
  local name="$1"
  local snake
  snake=$(echo "$name" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:upper:]' '[:lower:]')
  local path
  path=$(echo "$snake" | sed 's/::/\//g')
  local file="$ROOT/app/models/${path}.rb"
  if [[ -f "$file" ]]; then
    echo "$file"
  else
    find "$ROOT" -path "*/models/*${path}.rb" -type f 2>/dev/null | head -1
  fi
}

# ─── Find any Ruby class file (models, services, jobs, etc.) ───
find_ruby_class_file() {
  local name="$1"
  local snake
  snake=$(echo "$name" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:upper:]' '[:lower:]')
  local path
  path=$(echo "$snake" | sed 's/::/\//g')

  # Search in common Rails directories
  local dirs=("app/models" "app/services" "app/interactors" "app/commands"
              "app/jobs" "app/workers" "app/processors" "app/handlers"
              "app/mailers" "app/generators" "lib")
  local dir
  for dir in "${dirs[@]}"; do
    local file="$ROOT/${dir}/${path}.rb"
    if [[ -f "$file" ]]; then
      echo "$file"
      return 0
    fi
  done

  # Fallback: find anywhere under ROOT
  find "$ROOT" -path "*/app/*${path}.rb" -type f 2>/dev/null | head -1 ||
    find "$ROOT" -path "*/${path}.rb" -name "*.rb" -not -path "*/vendor/*" -not -path "*/node_modules/*" -type f 2>/dev/null | head -1
}

# ─── Extract cross-class method calls from a method body ───────
# Returns lines like: ClassName::SubClass method_name line_number
extract_cross_class_calls() {
  local file="$1"
  local method_name="$2"

  awk -v action="$method_name" '
    BEGIN { in_method = 0; method_indent = -1 }
    {
      match($0, /^[ \t]*/)
      curr_indent = RLENGTH
    }
    /^[ \t]*def (self\.)?[a-z_]+/ {
      if (in_method == 0) {
        mn = $0
        gsub(/^[ \t]*def[ \t]+/, "", mn)
        gsub(/^self\./, "", mn)
        gsub(/[ \t\(].*/, "", mn)
        if (mn == action) {
          in_method = 1
          method_indent = curr_indent
          next
        }
      }
    }
    in_method == 1 {
      if ($0 ~ /^[ \t]*end[ \t]*$/ && curr_indent <= method_indent) {
        in_method = 0; next
      }
      if ($0 ~ /^[ \t]*def (self\.)?[a-z_]+/ && curr_indent <= method_indent) {
        in_method = 0; next
      }

      line = $0
      gsub(/^[ \t]+/, "", line)
      # Skip comments
      if (line ~ /^#/) next

      # Pattern: ClassName.new(...).method(...) → class=ClassName method=method
      if (match(line, /[A-Z][a-zA-Z0-9_]*(::([A-Z][a-zA-Z0-9_]*))*\.new[^.]*\.[a-z_]+/)) {
        call = substr(line, RSTART, RLENGTH)
        # Extract class name (everything before .new)
        cls = call
        gsub(/\.new.*/, "", cls)
        # Extract method after .new(...).<method>
        mtd = call
        gsub(/.*\.new[^.]*\./, "", mtd)
        gsub(/[^a-z_].*/, "", mtd)
        print cls " " mtd " " NR
        next
      }
      # Pattern: ClassName.call/method(...) → class=ClassName method=call/method
      if (match(line, /[A-Z][a-zA-Z0-9_]*(::([A-Z][a-zA-Z0-9_]*))*\.[a-z_]+/)) {
        call = substr(line, RSTART, RLENGTH)
        cls = call
        gsub(/\.[a-z_]+$/, "", cls)
        mtd = call
        gsub(/.*\./, "", mtd)
        # Skip common ActiveRecord/Ruby methods that are not worth following
        skip_methods = "new find find_by where create update destroy delete all first last count includes joins order limit select pluck group sum transaction save find_or_initialize_by find_or_create_by find_by_id exists present blank nil try respond_to is_a class name to_s to_i to_f freeze eql"
        skip = 0
        n_skip = split(skip_methods, skip_arr, " ")
        for (si = 1; si <= n_skip; si++) {
          if (mtd == skip_arr[si]) { skip = 1; break }
        }
        if (skip) next
        print cls " " mtd " " NR
      }
    }
  ' "$file" 2>/dev/null | sort -u || true
}

# ─── Recursive call chain tracer ──────────────────────────────
# Tracks visited class#method to prevent infinite loops
TRACE_VISITED=""

trace_call_chain() {
  local file="$1"
  local method_name="$2"
  local current_depth="$3"
  local max_depth="$4"
  local indent_depth="$5"

  # Depth check
  [[ $current_depth -ge $max_depth ]] && return

  # Get cross-class calls
  local calls
  calls=$(extract_cross_class_calls "$file" "$method_name")
  [[ -z "$calls" ]] && return

  while IFS= read -r call_line; do
    local cls mtd lineno
    cls=$(echo "$call_line" | awk '{print $1}')
    mtd=$(echo "$call_line" | awk '{print $2}')
    lineno=$(echo "$call_line" | awk '{print $3}')

    # Skip if already visited (prevent infinite recursion)
    local visit_key="${cls}#${mtd}"
    if echo "$TRACE_VISITED" | grep -qF "$visit_key" 2>/dev/null; then
      continue
    fi
    TRACE_VISITED="${TRACE_VISITED} ${visit_key}"

    # Find the target file
    local target_file
    target_file=$(find_ruby_class_file "$cls")
    [[ -z "$target_file" || ! -f "$target_file" ]] && continue

    local rel_path="${target_file#$ROOT/}"

    # Check if it's an Interactor Organizer (organize Class1, Class2, ...)
    local organize_line
    organize_line=$(rg -n "^\s*organize\s+" "$target_file" 2>/dev/null | head -1 || true)
    if [[ -n "$organize_line" ]]; then
      echo ""
      section "${cls} [organizer] (${rel_path})"
      local org_lineno org_content
      org_lineno=$(echo "$organize_line" | cut -d: -f1)
      org_content=$(echo "$organize_line" | cut -d: -f2- | sed 's/^[[:space:]]*organize[[:space:]]*//')
      format_tree_line "$indent_depth" "true" "${MAGENTA}organize${RESET} ${org_content}" "$org_lineno"

      # Follow each organized interactor
      local organized_classes
      organized_classes=$(echo "$org_content" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      while IFS= read -r sub_cls; do
        [[ -z "$sub_cls" ]] && continue
        local sub_visit="${sub_cls}#call"
        if echo "$TRACE_VISITED" | grep -qF "$sub_visit" 2>/dev/null; then
          continue
        fi
        TRACE_VISITED="${TRACE_VISITED} ${sub_visit}"

        local sub_file
        sub_file=$(find_ruby_class_file "$sub_cls")
        [[ -z "$sub_file" || ! -f "$sub_file" ]] && continue

        local sub_rel="${sub_file#$ROOT/}"
        echo ""
        section "${sub_cls}#call (${sub_rel})"

        if rg -q "^\s*def\s+call" "$sub_file" 2>/dev/null; then
          parse_action_body "$sub_file" "call" "$indent_depth" "" "true"
          trace_call_chain "$sub_file" "call" $((current_depth + 1)) "$max_depth" "$indent_depth"
        else
          # Might be another organizer
          local nested_org
          nested_org=$(rg -n "^\s*organize\s+" "$sub_file" 2>/dev/null | head -1 || true)
          if [[ -n "$nested_org" ]]; then
            local n_lineno n_content
            n_lineno=$(echo "$nested_org" | cut -d: -f1)
            n_content=$(echo "$nested_org" | cut -d: -f2- | sed 's/^[[:space:]]*organize[[:space:]]*//')
            format_tree_line "$indent_depth" "true" "${MAGENTA}organize${RESET} ${n_content}" "$n_lineno"
          fi
        fi
      done <<< "$organized_classes"
      continue
    fi

    # Check if method exists in target file
    if ! rg -q "^\s*def\s+(self\.)?${mtd}" "$target_file" 2>/dev/null; then
      continue
    fi

    echo ""
    section "${cls}#${mtd} (${rel_path})"

    # Show the method body
    parse_action_body "$target_file" "$mtd" "$indent_depth" "" "true"

    # Recurse deeper
    trace_call_chain "$target_file" "$mtd" $((current_depth + 1)) "$max_depth" "$indent_depth"
  done <<< "$calls"
}

# ═══════════════════════════════════════════════════════════════
#  FEATURE — MODEL TRACING
#  Traces Rails models: associations, validations, callbacks,
#  scopes, concerns, and methods with call chains
# ═══════════════════════════════════════════════════════════════

parse_model_input() {
  local input="$1"
  # Strip arguments if provided: "Order#method(arg1, arg2)" → "Order#method"
  input="${input%%(*}"
  if [[ "$input" =~ ^([A-Za-z:]+)#([a-z_]+[!?]?)$ ]]; then
    MODEL_CLASS="${BASH_REMATCH[1]}"
    MODEL_METHOD="${BASH_REMATCH[2]}"
  else
    MODEL_CLASS="$input"
    MODEL_METHOD=""
  fi
}

# ─── Extract included modules/concerns ─────────────────────────
extract_model_includes() {
  local file="$1"
  local depth="$2"
  local matches
  matches=$(rg -n "^\s*(include|extend|prepend)\s+" "$file" 2>/dev/null | grep -v "^#" || true)

  [[ -z "$matches" ]] && return

  section "Includes"
  local count total
  total=$(echo "$matches" | wc -l | tr -d ' ')
  count=0

  while IFS= read -r line; do
    count=$((count + 1))
    local lineno content kind module_name is_last
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    kind=$(echo "$content" | awk '{print $1}')
    module_name=$(echo "$content" | awk '{print $2}' | tr -d ',')
    is_last="false"
    [[ $count -eq $total ]] && is_last="true"
    format_tree_line "$depth" "$is_last" "${YELLOW}${kind}${RESET} ${module_name}" "$lineno"
  done <<< "$matches"
}

# ─── Extract associations ──────────────────────────────────────
extract_model_associations() {
  local file="$1"
  local depth="$2"
  local matches
  matches=$(rg -n "^\s*(has_many|has_one|belongs_to|has_and_belongs_to_many)\s+" "$file" 2>/dev/null | grep -v "^\s*#" || true)

  [[ -z "$matches" ]] && return

  section "Associations"
  local count total
  total=$(echo "$matches" | wc -l | tr -d ' ')
  count=0

  while IFS= read -r line; do
    count=$((count + 1))
    local lineno content assoc_type assoc_rest is_last
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    assoc_type=$(echo "$content" | awk '{print $1}')
    assoc_rest=$(echo "$content" | sed "s/^${assoc_type}[[:space:]]*//")
    # Truncate long lines
    [[ ${#assoc_rest} -gt 60 ]] && assoc_rest="${assoc_rest:0:57}..."
    is_last="false"
    [[ $count -eq $total ]] && is_last="true"
    format_tree_line "$depth" "$is_last" "${GREEN}${assoc_type}${RESET} ${assoc_rest}" "$lineno"
  done <<< "$matches"
}

# ─── Extract validations ──────────────────────────────────────
extract_model_validations() {
  local file="$1"
  local depth="$2"
  local matches
  matches=$(rg -n "^\s*(validates?|validates_presence_of|validates_uniqueness_of|validates_numericality_of|validates_format_of|validates_inclusion_of|validates_exclusion_of|validates_length_of|validates_acceptance_of|validates_confirmation_of|validates_associated|validate)\s+" "$file" 2>/dev/null | grep -v "^\s*#" || true)

  [[ -z "$matches" ]] && return

  section "Validations"
  local count total
  total=$(echo "$matches" | wc -l | tr -d ' ')
  count=0

  while IFS= read -r line; do
    count=$((count + 1))
    local lineno content val_type val_rest is_last
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    val_type=$(echo "$content" | awk '{print $1}')
    val_rest=$(echo "$content" | sed "s/^${val_type}[[:space:]]*//")
    [[ ${#val_rest} -gt 60 ]] && val_rest="${val_rest:0:57}..."
    is_last="false"
    [[ $count -eq $total ]] && is_last="true"
    format_tree_line "$depth" "$is_last" "${CYAN}${val_type}${RESET} ${val_rest}" "$lineno"
  done <<< "$matches"
}

# ─── Extract callbacks ────────────────────────────────────────
extract_model_callbacks() {
  local file="$1"
  local depth="$2"
  local matches
  matches=$(rg -n "^\s*(before_validation|after_validation|before_save|after_save|around_save|before_create|after_create|around_create|before_update|after_update|around_update|before_destroy|after_destroy|around_destroy|after_commit|after_create_commit|after_update_commit|after_destroy_commit|after_rollback|after_initialize|after_find|after_touch)\s+" "$file" 2>/dev/null | grep -v "^\s*#" || true)

  [[ -z "$matches" ]] && return

  section "Callbacks"
  local count total
  total=$(echo "$matches" | wc -l | tr -d ' ')
  count=0

  while IFS= read -r line; do
    count=$((count + 1))
    local lineno content cb_type cb_rest is_last
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    cb_type=$(echo "$content" | awk '{print $1}')
    cb_rest=$(echo "$content" | sed "s/^${cb_type}[[:space:]]*//")
    [[ ${#cb_rest} -gt 60 ]] && cb_rest="${cb_rest:0:57}..."
    is_last="false"
    [[ $count -eq $total ]] && is_last="true"
    format_tree_line "$depth" "$is_last" "${YELLOW}${cb_type}${RESET} ${cb_rest}" "$lineno"
  done <<< "$matches"
}

# ─── Extract scopes ───────────────────────────────────────────
extract_model_scopes() {
  local file="$1"
  local depth="$2"
  local matches
  matches=$(rg -n "^\s*scope\s+:" "$file" 2>/dev/null | grep -v "^\s*#" || true)

  [[ -z "$matches" ]] && return

  section "Scopes"
  local count total
  total=$(echo "$matches" | wc -l | tr -d ' ')
  count=0

  while IFS= read -r line; do
    count=$((count + 1))
    local lineno content scope_name is_last
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    # Extract scope name
    scope_name=$(echo "$content" | sed 's/scope[[:space:]]*\(:[a-z_]*\).*/\1/')
    is_last="false"
    [[ $count -eq $total ]] && is_last="true"
    format_tree_line "$depth" "$is_last" "${MAGENTA}scope${RESET} ${scope_name}" "$lineno"
  done <<< "$matches"
}

# ─── Extract and trace methods ─────────────────────────────────
extract_model_methods() {
  local file="$1"
  local depth="$2"
  local target_method="${3:-}"
  local matches

  if [[ -n "$target_method" ]]; then
    matches=$(rg -n "^\s*def\s+(self\.)?${target_method}[\s(]?" "$file" 2>/dev/null || true)
  else
    matches=$(rg -n "^\s*def\s+" "$file" 2>/dev/null || true)
  fi

  [[ -z "$matches" ]] && return

  section "Methods"
  local count total
  total=$(echo "$matches" | wc -l | tr -d ' ')
  count=0

  while IFS= read -r line; do
    count=$((count + 1))
    local lineno content method_sig is_last
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    method_sig=$(echo "$content" | sed 's/^\(def[[:space:]]*[a-zA-Z_.:!?]*\).*/\1/')
    is_last="false"
    [[ $count -eq $total ]] && is_last="true"

    # Extract method name for body parsing
    local method_name
    method_name=$(echo "$content" | sed 's/def[[:space:]]*\(self\.\)\{0,1\}\([a-z_!?]*\).*/\2/')

    # If depth allows, trace method body (parse_action_body prints its own def header)
    if [[ $MODEL_DEPTH -gt 1 ]]; then
      parse_action_body "$file" "$method_name" "$depth" "" "true"
      # Follow cross-class calls when tracing a specific method
      if [[ -n "$target_method" ]]; then
        TRACE_VISITED="${MODEL_CLASS}#${method_name}"
        trace_call_chain "$file" "$method_name" 1 "$MODEL_DEPTH" "$depth"
      fi
    else
      format_tree_line "$depth" "$is_last" "${CYAN}${method_sig}${RESET}" "$lineno"
    fi
  done <<< "$matches"
}

# ─── Main model tracing function ──────────────────────────────
trace_model() {
  parse_model_input "$MODEL_INPUT"

  local model_file
  model_file=$(find_model_file "$MODEL_CLASS")
  if [[ -z "$model_file" || ! -f "$model_file" ]]; then
    warn "Model not found: $MODEL_CLASS"
    return 1
  fi

  banner "MODEL TRACE: $MODEL_INPUT"
  local rel_path="${model_file#$ROOT/}"
  section "${MODEL_CLASS} (${rel_path})"

  # Show parent class
  local parent_class
  parent_class=$(rg -o "class\s+${MODEL_CLASS}\s*<\s*(\S+)" "$model_file" 2>/dev/null | sed 's/class.*<[[:space:]]*//')
  [[ -n "$parent_class" ]] && info "inherits from ${parent_class}"

  if [[ -n "$MODEL_METHOD" ]]; then
    # Trace a specific method — show relevant callbacks too
    extract_model_callbacks "$model_file" 1
    extract_model_methods "$model_file" 1 "$MODEL_METHOD"
  else
    # Full model trace
    extract_model_includes "$model_file" 1
    extract_model_associations "$model_file" 1
    extract_model_validations "$model_file" 1
    extract_model_callbacks "$model_file" 1
    extract_model_scopes "$model_file" 1
    extract_model_methods "$model_file" 1
  fi
}

# ─── Parse routes.rb to find controller#action ─────────────────
parse_routes_file() {
  local verb="$1"
  local path="$2"
  local routes_file="$ROOT/config/routes.rb"

  [[ ! -f "$routes_file" ]] && return 1

  # Normalize path: remove leading slash, trailing slash
  path="${path#/}"
  path="${path%/}"

  # ── Detect namespace prefix ──────────────────────────────────
  # Check if the first path segment matches a namespace in routes.rb
  # e.g., "v2/order_items/oc_items" → namespace_prefix="v2", path="order_items/oc_items"
  local namespace_prefix=""
  local first_segment="${path%%/*}"
  if [[ "$first_segment" != "$path" ]]; then
    # Check if this segment is declared as a namespace in routes.rb
    if rg -q "namespace\s+:${first_segment}" "$routes_file" 2>/dev/null; then
      namespace_prefix="$first_segment"
      path="${path#${first_segment}/}"
    fi
  fi

  # Convert path params (:id) to regex pattern
  local path_pattern
  path_pattern=$(echo "$path" | sed 's/:[a-z_]*/:?[a-z_]*/g')

  # Build namespace controller prefix (e.g., "v2" → "V2::")
  local ns_ctrl_prefix=""
  if [[ -n "$namespace_prefix" ]]; then
    ns_ctrl_prefix=$(echo "$namespace_prefix" | awk '{print toupper($0)}')"::"
  fi

  # Direct route: post '/path', to: 'controller#action'
  local direct_match
  # Try with full path (including namespace prefix) first
  local full_path_pattern
  if [[ -n "$namespace_prefix" ]]; then
    full_path_pattern=$(echo "${namespace_prefix}/${path}" | sed 's/:[a-z_]*/:?[a-z_]*/g')
  else
    full_path_pattern="$path_pattern"
  fi
  direct_match=$(rg --no-line-number -o "(get|post|put|patch|delete)\s+['\"]/?${full_path_pattern}['\"].*to:\s*['\"]([a-z_/]+)#([a-z_]+)['\"]" "$routes_file" 2>/dev/null | head -1)
  # Also try without namespace prefix (routes inside namespace block use relative paths)
  if [[ -z "$direct_match" && -n "$namespace_prefix" ]]; then
    direct_match=$(rg --no-line-number -o "(get|post|put|patch|delete)\s+['\"]/?${path_pattern}['\"].*to:\s*['\"]([a-z_/]+)#([a-z_]+)['\"]" "$routes_file" 2>/dev/null | head -1)
  fi

  if [[ -n "$direct_match" ]]; then
    local ctrl action
    ctrl=$(echo "$direct_match" | sed "s/.*to:[[:space:]]*['\"]\\([a-z_/]*\\)#.*/\\1/")
    action=$(echo "$direct_match" | sed "s/.*#\\([a-z_]*\\)['\"].*/\\1/")
    # Convert to PascalCase controller name (portable, no \U)
    local pascal_ctrl
    pascal_ctrl=$(echo "${ctrl}_controller" | awk -F'_' '{
      for (i=1; i<=NF; i++) {
        printf "%s", toupper(substr($i,1,1)) substr($i,2)
      }
    }')
    # Prepend namespace if not already in the controller path
    if [[ -n "$ns_ctrl_prefix" && "$ctrl" != *"/"* ]]; then
      echo "${ns_ctrl_prefix}${pascal_ctrl}#${action}"
    else
      echo "${pascal_ctrl}#${action}"
    fi
    return 0
  fi

  # Resource routes: resources :orders with member { post 'refund' }
  local action_name
  local last_segment
  last_segment=$(echo "$path" | rev | cut -d'/' -f1 | rev)

  # Determine action based on path structure and verb
  if [[ "$last_segment" == ":id" || "$last_segment" =~ ^[0-9]+$ ]]; then
    # Path ends with :id - standard resource actions
    case "$verb" in
      GET)    action_name="show" ;;
      PATCH|PUT) action_name="update" ;;
      DELETE) action_name="destroy" ;;
      *)      action_name="show" ;;
    esac
  elif echo "$path" | grep -qE '^[a-z_]+$'; then
    # Path is just resource name (e.g., "orders")
    case "$verb" in
      GET)    action_name="index" ;;
      POST)   action_name="create" ;;
      *)      action_name="index" ;;
    esac
  else
    # Custom member/collection action (e.g., "orders/:id/refund" → "refund")
    action_name="$last_segment"
  fi

  # Find resource that might contain this action
  # When namespace is present, find the resource within the namespace block
  local resource_match=""
  if [[ -n "$namespace_prefix" ]]; then
    # Find namespace line number, then search for resources within that block
    local ns_line
    ns_line=$(rg -n "namespace\s+:${namespace_prefix}" "$routes_file" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$ns_line" ]]; then
      # Search from the namespace line onwards for the resource
      resource_match=$(tail -n +"$ns_line" "$routes_file" | rg --no-line-number "resources?\s+:([a-z_]+)" 2>/dev/null | while read -r line; do
        local res
        res=$(echo "$line" | sed 's/.*resources[[:space:]]*:\([a-z_]*\).*/\1/')
        if echo "$path" | grep -q "$res"; then
          echo "$res"
          break
        fi
      done | head -1)
    fi
  fi
  # Fallback: search all resources globally
  if [[ -z "$resource_match" ]]; then
    resource_match=$(rg --no-line-number "resources?\s+:([a-z_]+)" "$routes_file" 2>/dev/null | while read -r line; do
      local res
      res=$(echo "$line" | sed 's/.*resources[[:space:]]*:\([a-z_]*\).*/\1/')
      # Check if path contains this resource
      if echo "$path" | grep -q "$res"; then
        echo "$res"
      fi
    done | head -1)
  fi

  if [[ -n "$resource_match" ]]; then
    local pascal_ctrl
    pascal_ctrl=$(echo "${resource_match}_controller" | awk -F'_' '{
      for (i=1; i<=NF; i++) {
        printf "%s", toupper(substr($i,1,1)) substr($i,2)
      }
    }')
    echo "${ns_ctrl_prefix}${pascal_ctrl}#${action_name}"
    return 0
  fi

  return 1
}

# ─── Parse action input (Controller#action) ────────────────────
parse_action_input() {
  local input="$1"
  if [[ "$input" =~ ^([A-Za-z:]+)#([a-z_]+)$ ]]; then
    CONTROLLER="${BASH_REMATCH[1]}"
    ACTION="${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

# ─── Parse route input (VERB /path) ────────────────────────────
# ─── Parse curl command from file ──────────────────────────────
parse_curl_file() {
  local file="$1"
  local content verb url path query_string

  # Read file content, join continuation lines (remove trailing backslash)
  content=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%\\}"  # Remove trailing backslash
    content="$content$line "
  done < "$file"

  # Check if it contains curl
  if ! echo "$content" | grep -qi 'curl'; then
    return 1
  fi

  # Extract HTTP verb from -X or --request (default: GET)
  verb=$(echo "$content" | grep -oE '(-X|--request)[[:space:]]+[A-Z]+' | awk '{print toupper($NF)}')
  [[ -z "$verb" ]] && verb="GET"

  # Extract URL (handle both quoted and unquoted)
  url=$(echo "$content" | grep -oE "(https?://[^[:space:]\"']+|[\"']https?://[^\"']+[\"'])" | head -1 | tr -d "\"'")

  if [[ -z "$url" ]]; then
    return 1
  fi

  # Extract path from URL (remove protocol and host)
  path=$(echo "$url" | sed -E 's|https?://[^/]+||')

  # Extract query string if present
  if echo "$path" | grep -q '?'; then
    query_string=$(echo "$path" | sed 's/.*?//')
    path=$(echo "$path" | sed 's/?.*//')
    # Parse query params and store them
    CURL_QUERY_PARAMS=$(echo "$query_string" | tr '&' '\n' | sed 's/=.*//' | tr '\n' ' ')
  fi

  # Convert numeric path segments to :id (e.g., /orders/123/refund → /orders/:id/refund)
  path=$(echo "$path" | sed -E 's|/[0-9]+(/\|$)|/:id\1|g')

  # Extract JSON body from -d or --data (handle single or double quoted JSON)
  local json_body
  # Try single-quoted body first (most common for JSON)
  json_body=$(echo "$content" | grep -oE "(-d|--data)[[:space:]]+'[^']+'" | sed "s/(-d|--data)[[:space:]]*'//;s/'$//" | head -1)
  # If not found, try double-quoted body
  if [[ -z "$json_body" ]]; then
    json_body=$(echo "$content" | grep -oE '(-d|--data)[[:space:]]+"[^"]+"' | sed 's/(-d|--data)[[:space:]]*"//;s/"$//' | head -1)
  fi

  if [[ -n "$json_body" ]]; then
    # Extract keys from JSON (simple parsing for {"key": ...} patterns)
    CURL_BODY_PARAMS=$(echo "$json_body" | grep -oE '"[a-z_]+":' | tr -d '":' | tr '\n' ' ')
  fi

  # Set global vars for trace_route
  CURL_VERB="$verb"
  CURL_PATH="$path"

  return 0
}

parse_route_input() {
  local input="$1"
  local verb path

  # Check if input is a file (curl file)
  if [[ -f "$input" ]]; then
    if parse_curl_file "$input"; then
      verb="$CURL_VERB"
      path="$CURL_PATH"
      info "Parsed curl: $verb $path"
      [[ -n "$CURL_QUERY_PARAMS" ]] && info "Query params: $CURL_QUERY_PARAMS"
      [[ -n "$CURL_BODY_PARAMS" ]] && info "Body params: $CURL_BODY_PARAMS"
    else
      warn "Could not parse curl from file: $input"
      return 1
    fi
  else
    # Split on space: "POST /orders/:id/refund"
    verb=$(echo "$input" | awk '{print toupper($1)}')
    path=$(echo "$input" | awk '{print $2}')
  fi

  local result
  result=$(parse_routes_file "$verb" "$path")

  if [[ -n "$result" ]]; then
    CONTROLLER=$(echo "$result" | cut -d'#' -f1)
    ACTION=$(echo "$result" | cut -d'#' -f2)
    return 0
  fi

  warn "Could not resolve route: $verb $path"
  return 1
}

# ─── Parse callbacks from controller ───────────────────────────
parse_callbacks() {
  local file="$1"
  local action="$2"

  [[ ! -f "$file" ]] && return

  # Arrays to store callbacks
  BEFORE_CALLBACKS=()
  AFTER_CALLBACKS=()
  AROUND_CALLBACKS=()

  local callback_type callback_name only_actions except_actions line_num

  # Read file and extract callbacks
  while IFS=: read -r lnum line; do
    # Match: before_action :method_name, only: [...] / except: [...]
    if echo "$line" | grep -qE '^\s*(before_action|prepend_before_action|append_before_action)\s+:'; then
      callback_type="before"
      # Extract callback name: first :symbol after before_action
      callback_name=$(echo "$line" | sed 's/.*_action[[:space:]]*:\([a-z_!?]*\).*/\1/')

      # Check only: constraint
      if echo "$line" | grep -q 'only:'; then
        only_actions=$(echo "$line" | sed 's/.*only:[[:space:]]*\[\([^]]*\)\].*/\1/' | tr -d ' :')
        if ! echo ",$only_actions," | grep -q ",$action,"; then
          continue  # Skip - action not in only list
        fi
      fi

      # Check except: constraint
      if echo "$line" | grep -q 'except:'; then
        except_actions=$(echo "$line" | sed 's/.*except:[[:space:]]*\[\([^]]*\)\].*/\1/' | tr -d ' :')
        if echo ",$except_actions," | grep -q ",$action,"; then
          continue  # Skip - action in except list
        fi
      fi

      BEFORE_CALLBACKS+=("${callback_name}:${lnum}")

    elif echo "$line" | grep -qE '^\s*after_action\s+:'; then
      callback_type="after"
      callback_name=$(echo "$line" | sed 's/.*_action[[:space:]]*:\([a-z_!?]*\).*/\1/')

      if echo "$line" | grep -q 'only:'; then
        only_actions=$(echo "$line" | sed 's/.*only:[[:space:]]*\[\([^]]*\)\].*/\1/' | tr -d ' :')
        if ! echo ",$only_actions," | grep -q ",$action,"; then
          continue
        fi
      fi

      if echo "$line" | grep -q 'except:'; then
        except_actions=$(echo "$line" | sed 's/.*except:[[:space:]]*\[\([^]]*\)\].*/\1/' | tr -d ' :')
        if echo ",$except_actions," | grep -q ",$action,"; then
          continue
        fi
      fi

      AFTER_CALLBACKS+=("${callback_name}:${lnum}")

    elif echo "$line" | grep -qE '^\s*around_action\s+:'; then
      callback_name=$(echo "$line" | sed 's/.*_action[[:space:]]*:\([a-z_!?]*\).*/\1/')

      if echo "$line" | grep -q 'only:'; then
        only_actions=$(echo "$line" | sed 's/.*only:[[:space:]]*\[\([^]]*\)\].*/\1/' | tr -d ' :')
        if ! echo ",$only_actions," | grep -q ",$action,"; then
          continue
        fi
      fi

      if echo "$line" | grep -q 'except:'; then
        except_actions=$(echo "$line" | sed 's/.*except:[[:space:]]*\[\([^]]*\)\].*/\1/' | tr -d ' :')
        if echo ",$except_actions," | grep -q ",$action,"; then
          continue
        fi
      fi

      AROUND_CALLBACKS+=("${callback_name}:${lnum}")
    fi
  done < <(grep -n '' "$file")
}

# ─── Resolve callback origin (parent/concern) ─────────────────
resolve_callback_origin() {
  local callback="$1"
  local file="$2"

  # Check if callback is defined in current file
  if rg -q "def ${callback}" "$file" 2>/dev/null; then
    echo ""  # Defined locally
    return
  fi

  # Check parent class
  local parent
  parent=$(rg -o 'class\s+\w+\s*<\s*(\w+)' "$file" 2>/dev/null | head -1 | sed 's/.*<[[:space:]]*//')

  if [[ -n "$parent" ]]; then
    local parent_file
    parent_file=$(find_controller_file "$parent")
    if [[ -n "$parent_file" && -f "$parent_file" ]]; then
      if rg -q "def ${callback}" "$parent_file" 2>/dev/null; then
        echo "[$parent]"
        return
      fi
    fi
  fi

  # Check included concerns
  local concerns
  concerns=$(rg -o 'include\s+(\w+)' "$file" 2>/dev/null | sed 's/include[[:space:]]*//')

  while read -r concern; do
    [[ -z "$concern" ]] && continue
    local concern_file
    concern_file=$(find "$ROOT" -path "*/concerns/*" -name "*.rb" 2>/dev/null | while read -r cf; do
      if rg -q "module ${concern}" "$cf" 2>/dev/null; then
        echo "$cf"
        break
      fi
    done)

    if [[ -n "$concern_file" && -f "$concern_file" ]]; then
      if rg -q "def ${callback}\|before_action :${callback}\|after_action :${callback}" "$concern_file" 2>/dev/null; then
        echo "[${concern}]"
        return
      fi
    fi
  done <<< "$concerns"

  echo ""  # Origin unknown
}

# ─── Parse action body with pygmentize highlighting ────────────
parse_action_body_highlighted() {
  local file="$1"
  local action="$2"
  local depth="$3"
  local prefix="$4"

  [[ ! -f "$file" ]] && return

  local raw_body
  raw_body=$(extract_method_body "$file" "$action")
  [[ -z "$raw_body" ]] && return

  # Get the starting line number of the method
  local start_line
  start_line=$(rg -n "^\s*def\s+(self\.)?${action}[\s(]?" "$file" 2>/dev/null | head -1 | cut -d: -f1)
  [[ -z "$start_line" ]] && start_line=0

  # Get method indent from first line (raw, before any processing)
  local method_indent
  method_indent=$(echo "$raw_body" | head -1 | sed 's/[^ \t].*//' | wc -c)
  method_indent=$((method_indent - 1))

  # Pre-process: for each line, compute indent metadata and strip to content.
  # Store: raw_indent|trimmed_line (one per line)
  # Then highlight all trimmed lines at once, and re-attach tree prefixes.
  local -a raw_indents=()
  local -a raw_trimmed=()
  local -a raw_linenrs=()
  local line_nr=$((start_line))

  while IFS= read -r raw_line; do
    local stripped
    stripped=$(echo "$raw_line" | sed 's/^[[:space:]]*//')

    # Measure raw indent
    local rindent
    rindent=$(echo "$raw_line" | sed 's/[^ \t].*//' | wc -c)
    rindent=$((rindent - 1))

    raw_indents+=("$rindent")
    raw_trimmed+=("$stripped")
    raw_linenrs+=("$line_nr")
    line_nr=$((line_nr + 1))
  done <<< "$raw_body"

  # Build a block of trimmed lines for batch highlighting
  local trimmed_block=""
  local idx
  for ((idx=0; idx<${#raw_trimmed[@]}; idx++)); do
    trimmed_block+="${raw_trimmed[$idx]}"$'\n'
  done

  # Highlight the entire trimmed block at once
  local highlighted
  highlighted=$(printf "%s" "$trimmed_block" | pygmentize -l ruby -f terminal -O style=gruvbox-dark 2>/dev/null) || highlighted="$trimmed_block"

  # Read highlighted lines back and pair with metadata
  local -a hl_lines=()
  while IFS= read -r hl_line; do
    hl_lines+=("$hl_line")
  done <<< "$highlighted"

  local is_first=true
  for ((idx=0; idx<${#hl_lines[@]}; idx++)); do
    local hl_line="${hl_lines[$idx]}"
    local raw_content="${raw_trimmed[$idx]}"
    local rindent="${raw_indents[$idx]}"
    local lnr="${raw_linenrs[$idx]}"

    # Skip empty lines, comments, and 'end' keywords
    [[ -z "$raw_content" ]] && continue
    [[ "$raw_content" == \#* ]] && continue
    [[ "$raw_content" == "end" ]] && continue

    # Calculate relative indent
    local rel_indent=$(( (rindent - method_indent - 2) / 2 ))
    [[ $rel_indent -lt 0 ]] && rel_indent=0

    # Strip trailing ANSI codes and whitespace that pygmentize adds
    hl_line=$(printf "%s" "$hl_line" | sed $'s/\033\\[[0-9;]*m[[:space:]]*$//; s/[[:space:]]*$//')

    if [[ "$is_first" == "true" ]]; then
      # First line is the def line
      printf "%s%s  ${DIM}:%s${RESET}\n" "${prefix}${TREE_BRANCH} " "$hl_line" "$lnr"
      is_first=false
    else
      # Body lines with tree indentation
      local tree_pfx="${prefix}    "
      local i
      for ((i=0; i<rel_indent; i++)); do
        tree_pfx+="${TREE_VERT}   "
      done
      tree_pfx+="${TREE_BRANCH} "
      printf "%s%s  ${DIM}:%s${RESET}\n" "$tree_pfx" "$hl_line" "$lnr"
    fi
  done
}

# ─── Parse action body and detect patterns ─────────────────────
parse_action_body() {
  local file="$1"
  local action="$2"
  local depth="$3"
  local prefix="$4"
  local show_all="${5:-false}"

  [[ ! -f "$file" ]] && return

  # Dispatch to highlighted version when --highlight is active
  if [[ "$HIGHLIGHT" == "true" ]] && command -v pygmentize &>/dev/null; then
    parse_action_body_highlighted "$file" "$action" "$depth" "$prefix"
    return
  fi

  # Find action method and extract body with awk
  awk -v action="$action" -v depth="$depth" -v prefix="$prefix" \
      -v show_all="$show_all" \
      -v green="$GREEN" -v yellow="$YELLOW" -v cyan="$CYAN" \
      -v magenta="$MAGENTA" -v dim="$DIM" -v reset="$RESET" \
      -v tree_vert="$TREE_VERT" -v tree_branch="$TREE_BRANCH" -v tree_last="$TREE_LAST" '
    BEGIN { in_method = 0; method_indent = -1; line_count = 0 }

    # Find method start - must match exactly "def action_name"
    {
      original_line = $0
      # Measure indent before any modifications
      match(original_line, /^[ \t]*/)
      curr_indent = RLENGTH
    }

    /^[ \t]*def (self\.)?[a-z_]+/ {
      if (in_method == 0) {
        # Extract method name (strip self. prefix for matching)
        method_name = original_line
        gsub(/^[ \t]*def[ \t]+/, "", method_name)
        # Preserve self. for display but match without it
        display_name = method_name
        gsub(/[ \t\(].*/, "", display_name)
        match_name = display_name
        gsub(/^self\./, "", match_name)

        if (match_name == action) {
          in_method = 1
          method_indent = curr_indent
          print prefix tree_branch " " cyan "def " display_name reset "  " dim ":" NR reset
          next
        }
      }
    }

    # Inside method - track and output
    in_method == 1 {
      # Check for method end (end at same or less indent as def)
      if (original_line ~ /^[ \t]*end[ \t]*$/ && curr_indent <= method_indent) {
        in_method = 0
        next
      }

      # Check for next method start (means current method ended without explicit end)
      if (original_line ~ /^[ \t]*def (self\.)?[a-z_]+/ && curr_indent <= method_indent) {
        in_method = 0
        next
      }

      line_count++
      trimmed = original_line
      gsub(/^[ \t]+/, "", trimmed)

      # Skip empty lines and comments
      if (trimmed == "" || trimmed ~ /^#/) next

      # Calculate relative indent for tree drawing
      rel_indent = int((curr_indent - method_indent - 2) / 2)
      if (rel_indent < 0) rel_indent = 0
      tree_prefix = prefix "    "
      for (i = 0; i < rel_indent; i++) {
        tree_prefix = tree_prefix tree_vert "   "
      }

      # Detect patterns
      if (trimmed ~ /^if[ \t]/) {
        cond = trimmed
        gsub(/^if[ \t]+/, "", cond)
        gsub(/[ \t]*then.*/, "", cond)
        if (length(cond) > 35) cond = substr(cond, 1, 32) "..."
        print tree_prefix tree_branch " " yellow "if " cond reset "  " dim ":" NR reset
      }
      else if (trimmed ~ /^unless[ \t]/) {
        cond = trimmed
        gsub(/^unless[ \t]+/, "", cond)
        if (length(cond) > 35) cond = substr(cond, 1, 32) "..."
        print tree_prefix tree_branch " " yellow "unless " cond reset "  " dim ":" NR reset
      }
      else if (trimmed ~ /^elsif[ \t]/) {
        cond = trimmed
        gsub(/^elsif[ \t]+/, "", cond)
        if (length(cond) > 35) cond = substr(cond, 1, 32) "..."
        print tree_prefix tree_branch " " yellow "elsif " cond reset "  " dim ":" NR reset
      }
      else if (trimmed ~ /^else[ \t]*$/) {
        print tree_prefix tree_branch " " yellow "else" reset "  " dim ":" NR reset
      }
      else if (trimmed ~ /^case[ \t]/) {
        print tree_prefix tree_branch " " yellow "case" reset "  " dim ":" NR reset
      }
      else if (trimmed ~ /^when[ \t]/) {
        cond = trimmed
        gsub(/^when[ \t]+/, "", cond)
        print tree_prefix tree_branch " " yellow "when " cond reset "  " dim ":" NR reset
      }
      # Service calls: ServiceClass.call(...) or ServiceClass.new.method
      else if (trimmed ~ /[A-Z][a-zA-Z0-9_]+(Service|Interactor|Command|Processor|Handler)\.(call|new|perform)/) {
        match(trimmed, /[A-Z][a-zA-Z0-9_]+(Service|Interactor|Command|Processor|Handler)/)
        svc = substr(trimmed, RSTART, RLENGTH)
        print tree_prefix tree_branch " " green "call: " svc reset "  " dim ":" NR reset
      }
      # Sidekiq jobs: JobClass.perform_async/perform_in/perform_at
      else if (trimmed ~ /[A-Z][a-zA-Z0-9_]+(Job|Worker)\.perform_(async|in|at)/) {
        match(trimmed, /[A-Z][a-zA-Z0-9_]+(Job|Worker)/)
        job = substr(trimmed, RSTART, RLENGTH)
        print tree_prefix tree_branch " " magenta "enqueue: " job reset "  " dim ":" NR " [async]" reset
      }
      # DelayedJob: object.delay.method
      else if (trimmed ~ /\.delay(\([^)]*\))?\./) {
        match(trimmed, /\.delay[^.]*\.([a-z_]+)/)
        print tree_prefix tree_branch " " magenta "delay: " trimmed reset "  " dim ":" NR " [async]" reset
      }
      # render calls
      else if (trimmed ~ /^render[ \t]/) {
        what = trimmed
        gsub(/^render[ \t]+/, "", what)
        if (length(what) > 40) what = substr(what, 1, 37) "..."
        print tree_prefix tree_branch " " dim "render: " what reset "  " dim ":" NR reset
      }
      # redirect calls
      else if (trimmed ~ /^redirect_to[ \t]/) {
        what = trimmed
        gsub(/^redirect_to[ \t]+/, "", what)
        if (length(what) > 40) what = substr(what, 1, 37) "..."
        print tree_prefix tree_branch " " dim "redirect: " what reset "  " dim ":" NR reset
      }
      # params access: params[:key], params["key"], params.fetch(:key), params.require(:key)
      else if (trimmed ~ /params\[:[a-z_]+\]/ || trimmed ~ /params\["[a-z_]+"\]/ || trimmed ~ /params\.fetch\(:[a-z_]+/ || trimmed ~ /params\.require\(:[a-z_]+/) {
        # Extract all param keys from the line
        param_line = trimmed
        param_keys = ""
        # Match params[:key] pattern
        while (match(param_line, /params\[:([a-z_]+)\]/)) {
          key = substr(param_line, RSTART + 8, RLENGTH - 9)
          if (param_keys != "") param_keys = param_keys ", "
          param_keys = param_keys ":" key
          param_line = substr(param_line, RSTART + RLENGTH)
        }
        # Match params["key"] pattern
        param_line = trimmed
        while (match(param_line, /params\["([a-z_]+)"\]/)) {
          key = substr(param_line, RSTART + 8, RLENGTH - 10)
          if (param_keys != "") param_keys = param_keys ", "
          param_keys = param_keys ":" key
          param_line = substr(param_line, RSTART + RLENGTH)
        }
        # Match params.fetch(:key) or params.require(:key)
        param_line = trimmed
        while (match(param_line, /params\.(fetch|require)\(:([a-z_]+)/)) {
          start = RSTART
          len = RLENGTH
          tmp = substr(param_line, start, len)
          gsub(/params\.(fetch|require)\(:/, "", tmp)
          if (param_keys != "") param_keys = param_keys ", "
          param_keys = param_keys ":" tmp
          param_line = substr(param_line, start + len)
        }
        if (param_keys != "") {
          print tree_prefix tree_branch " " cyan "params: " param_keys reset "  " dim ":" NR " [query]" reset
        }
        # Also check for .permit on the same line
        if (trimmed ~ /\.permit\(/) {
          permit_str = trimmed
          gsub(/.*\.permit\(/, "", permit_str)
          gsub(/\).*/, "", permit_str)
          if (length(permit_str) > 40) permit_str = substr(permit_str, 1, 37) "..."
          print tree_prefix tree_branch " " cyan "permit: " permit_str reset "  " dim ":" NR " [query]" reset
        }
      }
      # params.permit only (no require/fetch on same line)
      else if (trimmed ~ /\.permit\(/) {
        permit_str = trimmed
        gsub(/.*\.permit\(/, "", permit_str)
        gsub(/\).*/, "", permit_str)
        if (length(permit_str) > 40) permit_str = substr(permit_str, 1, 37) "..."
        print tree_prefix tree_branch " " cyan "permit: " permit_str reset "  " dim ":" NR " [query]" reset
      }
      # Fallback: show unrecognized lines in dim (useful for model methods)
      else if (show_all == "true") {
        line_text = trimmed
        if (length(line_text) > 60) line_text = substr(line_text, 1, 57) "..."
        print tree_prefix tree_branch " " dim line_text reset "  " dim ":" NR reset
      }
    }
  ' "$file"
}

# ─── Get parent class from controller file ────────────────────
get_parent_class() {
  local file="$1"
  local result
  result=$(rg -o 'class\s+\w+\s*<\s*(\w+)' "$file" 2>/dev/null | head -1 | sed 's/.*<[[:space:]]*//' || true)
  echo "$result"
}

# ─── Get included concerns from controller file ───────────────
get_included_concerns() {
  local file="$1"
  local result
  result=$(rg -o 'include\s+(\w+)' "$file" 2>/dev/null | sed 's/include[[:space:]]*//' || true)
  echo "$result"
}

# ─── Main route tracing function ───────────────────────────────
trace_route() {
  # Parse input
  if [[ -n "$ROUTE_INPUT" ]]; then
    if ! parse_route_input "$ROUTE_INPUT"; then
      warn "Failed to parse route: $ROUTE_INPUT"
      return 1
    fi
    banner "ROUTE TRACE: $ROUTE_INPUT"

    # Show route mapping
    local routes_file="$ROOT/config/routes.rb"
    if [[ -f "$routes_file" ]]; then
      local route_line
      route_line=$(rg -n "$ACTION" "$routes_file" 2>/dev/null | head -1 | cut -d: -f1)
      if [[ -n "$route_line" ]]; then
        info "routes.rb:${route_line} → ${CONTROLLER}#${ACTION}"
      else
        info "→ ${CONTROLLER}#${ACTION}"
      fi
    fi
  elif [[ -n "$ACTION_INPUT" ]]; then
    if ! parse_action_input "$ACTION_INPUT"; then
      warn "Invalid action format. Use: Controller#action"
      return 1
    fi
    banner "ACTION TRACE: $ACTION_INPUT"
  else
    warn "No --route or --action specified"
    return 1
  fi

  # Find controller file
  CONTROLLER_FILE=$(find_controller_file "$CONTROLLER")
  if [[ -z "$CONTROLLER_FILE" || ! -f "$CONTROLLER_FILE" ]]; then
    warn "Controller not found: $CONTROLLER"
    return 1
  fi

  # Verify action exists
  if ! rg -q "^\s*def ${ACTION}(\s|\(|$)" "$CONTROLLER_FILE" 2>/dev/null; then
    warn "Action not found: ${ACTION} in ${CONTROLLER}"
    return 1
  fi

  # Output controller header
  local rel_path="${CONTROLLER_FILE#$ROOT/}"
  section "${CONTROLLER} (${rel_path})"

  # Show curl-extracted params if present
  if [[ -n "$CURL_QUERY_PARAMS" || -n "$CURL_BODY_PARAMS" ]]; then
    echo -e "${DIM}Expected params from curl:${RESET}"
    [[ -n "$CURL_QUERY_PARAMS" ]] && echo -e "  ${CYAN}query:${RESET} ${CURL_QUERY_PARAMS}"
    [[ -n "$CURL_BODY_PARAMS" ]] && echo -e "  ${CYAN}body:${RESET} ${CURL_BODY_PARAMS}"
    echo ""
  fi

  # Parse callbacks from current controller
  parse_callbacks "$CONTROLLER_FILE" "$ACTION"
  local ctrl_before=("${BEFORE_CALLBACKS[@]}")
  local ctrl_after=("${AFTER_CALLBACKS[@]}")
  local ctrl_around=("${AROUND_CALLBACKS[@]}")

  # Parse parent controller callbacks
  local parent_class parent_file
  parent_class=$(get_parent_class "$CONTROLLER_FILE")
  local parent_before=()
  local parent_after=()
  if [[ -n "$parent_class" ]]; then
    parent_file=$(find_controller_file "$parent_class")
    if [[ -n "$parent_file" && -f "$parent_file" ]]; then
      parse_callbacks "$parent_file" "$ACTION"
      parent_before=("${BEFORE_CALLBACKS[@]}")
      parent_after=("${AFTER_CALLBACKS[@]}")
    fi
  fi

  # Parse concern callbacks
  local concern_before=()
  local concern_after=()
  local concerns
  concerns=$(get_included_concerns "$CONTROLLER_FILE")
  while read -r concern; do
    [[ -z "$concern" ]] && continue
    local concern_file
    concern_file=$(find "$ROOT" -path "*/concerns/*" -name "*.rb" 2>/dev/null | while read -r cf; do
      if rg -q "module ${concern}" "$cf" 2>/dev/null; then
        echo "$cf"
        break
      fi
    done)
    if [[ -n "$concern_file" && -f "$concern_file" ]]; then
      parse_callbacks "$concern_file" "$ACTION"
      concern_before+=("${BEFORE_CALLBACKS[@]}")
      concern_after+=("${AFTER_CALLBACKS[@]}")
    fi
  done <<< "$concerns"

  # Merge callbacks: parent + concern + controller (order matters for before_action)
  BEFORE_CALLBACKS=("${parent_before[@]}" "${concern_before[@]}" "${ctrl_before[@]}")
  AFTER_CALLBACKS=("${ctrl_after[@]}" "${concern_after[@]}" "${parent_after[@]}")
  AROUND_CALLBACKS=("${ctrl_around[@]}")

  # Count total items for is_last calculation
  local total_items=$(( ${#BEFORE_CALLBACKS[@]} + 1 + ${#AFTER_CALLBACKS[@]} ))
  local current_item=0

  # Output before_action callbacks
  local cb cb_name cb_line origin
  for cb in "${BEFORE_CALLBACKS[@]}"; do
    current_item=$((current_item + 1))
    cb_name="${cb%%:*}"
    cb_line="${cb##*:}"
    origin=$(resolve_callback_origin "$cb_name" "$CONTROLLER_FILE")

    local is_last="false"
    [[ $current_item -eq $total_items ]] && is_last="true"

    format_tree_line 1 "$is_last" "${YELLOW}before_action${RESET} :${cb_name}" "$cb_line" "$origin"
  done

  # Output around_action callbacks
  for cb in "${AROUND_CALLBACKS[@]}"; do
    current_item=$((current_item + 1))
    cb_name="${cb%%:*}"
    cb_line="${cb##*:}"
    origin=$(resolve_callback_origin "$cb_name" "$CONTROLLER_FILE")

    local is_last="false"
    [[ $current_item -eq $total_items ]] && is_last="true"

    format_tree_line 1 "$is_last" "${MAGENTA}around_action${RESET} :${cb_name}" "$cb_line" "$origin"
  done

  # Output action body
  current_item=$((current_item + 1))
  local action_is_last="false"
  [[ ${#AFTER_CALLBACKS[@]} -eq 0 ]] && action_is_last="true"

  parse_action_body "$CONTROLLER_FILE" "$ACTION" 1 ""

  # Follow cross-class calls from the action
  TRACE_VISITED="${CONTROLLER}#${ACTION}"
  trace_call_chain "$CONTROLLER_FILE" "$ACTION" 1 "$ROUTE_DEPTH" 1

  # Output after_action callbacks
  local after_count=${#AFTER_CALLBACKS[@]}
  local after_idx=0
  for cb in "${AFTER_CALLBACKS[@]}"; do
    after_idx=$((after_idx + 1))
    cb_name="${cb%%:*}"
    cb_line="${cb##*:}"
    origin=$(resolve_callback_origin "$cb_name" "$CONTROLLER_FILE")

    local is_last="false"
    [[ $after_idx -eq $after_count ]] && is_last="true"

    format_tree_line 1 "$is_last" "${CYAN}after_action${RESET} :${cb_name}" "$cb_line" "$origin"
  done
}

# ═══════════════════════════════════════════════════════════════
#  HEADER
# ═══════════════════════════════════════════════════════════════
if [[ "$MODE" == "route" ]]; then
  echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║      codetracer  ·  route trace                    ║${RESET}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════╝${RESET}"
  _hl_label=""
  [[ "$HIGHLIGHT" == "true" ]] && _hl_label="  ${DIM}highlight:${RESET} on"
  echo -e "  ${DIM}root:${RESET} $ROOT  ${DIM}depth:${RESET} $ROUTE_DEPTH  ${DIM}async:${RESET} $ASYNC_MODE${_hl_label}"
elif [[ "$MODE" == "model" ]]; then
  echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║      codetracer  ·  model trace                    ║${RESET}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════╝${RESET}"
  _hl_label=""
  [[ "$HIGHLIGHT" == "true" ]] && _hl_label="  ${DIM}highlight:${RESET} on"
  echo -e "  ${DIM}root:${RESET} $ROOT  ${DIM}depth:${RESET} $MODEL_DEPTH${_hl_label}"
else
  echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║      codetracer  ·  $WORD$(printf '%*s' $((20 - ${#WORD})) '')║${RESET}"
  echo -e "${BOLD}${CYAN}╚════════════════════════════════════╝${RESET}"
  echo -e "  ${DIM}root:${RESET} $ROOT  ${DIM}lang:${RESET} $LANG  ${DIM}mode:${RESET} $MODE  ${DIM}ctx:${RESET} ±$CTX"
fi

# ═══════════════════════════════════════════════════════════════
#  DISPATCH
# ═══════════════════════════════════════════════════════════════
if $INTERACTIVE; then
  interactive_mode
  exit 0
fi

case "$MODE" in
  def)
    find_definitions
    $USE_CTAGS && ctags_lookup
    ;;
  call)
    find_calls
    $SHOW_SCOPE && show_enclosing_scope
    ;;
  flow)
    find_definitions
    find_flow
    $SHOW_SCOPE && show_enclosing_scope
    ;;
  file)
    find_files
    ;;
  full)
    find_definitions
    $USE_CTAGS && ctags_lookup
    find_calls
    find_flow
    find_files
    $SHOW_SCOPE && show_enclosing_scope
    ;;
  route)
    trace_route
    ;;
  model)
    trace_model
    ;;
  *)
    warn "Unknown mode: $MODE"; usage
    ;;
esac

echo -e "\n${DIM}━━━ done ━━━${RESET}\n"
