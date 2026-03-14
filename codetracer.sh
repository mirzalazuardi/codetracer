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

# ─── Arg Parse ────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

# Handle --help / -h before consuming the first positional arg as WORD
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

WORD="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--lang)    LANG="$2";        shift 2 ;;
    -m|--mode)    MODE="$2";        shift 2 ;;
    -c|--ctx)     CTX="$2";         shift 2 ;;
    -i|--inter)   INTERACTIVE=true; shift ;;
    -t|--ctags)   USE_CTAGS=true;   shift ;;
    -s|--scope)   SHOW_SCOPE=true;  shift ;;
    -h|--help)    usage ;;
    -*)           warn "Unknown option: $1"; shift ;;
    *)            ROOT="$1";        shift ;;
  esac
done

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
build_variants "$WORD"
echo -e "  ${DIM}regex: ${RESET}${CYAN}$WORD_REGEX${RESET}"

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
#  For each match, show the enclosing method/function name
# ═══════════════════════════════════════════════════════════════
show_enclosing_scope() {
  banner "ENCLOSING SCOPE for matches of: $WORD"
  info "Scanning for '$WORD' and resolving enclosing method/function..."

  # For each match file:line, walk back to find enclosing def/function
  local args=(--color=never --smart-case --line-number "$ROOT" -e "$WORD_REGEX")
  [[ "${#GLOBS[@]}" -gt 0 ]] && for g in "${GLOBS[@]}"; do args+=("--glob=$g"); done

  local scope
  rg "${args[@]}" 2>/dev/null | while IFS=: read -r file lineno rest; do
    # walk backward through the file to find nearest def/function
    scope=$(awk -v target="$lineno" '
      NR <= target {
        if (/^[ \t]*(def |function |const [A-Za-z_]+ = (async )?(\(|function)|async function )/) {
          scope = $0
          scope_line = NR
        }
      }
      END {
        if (scope != "") {
          gsub(/^[ \t]+/, "", scope)
          print scope_line ": " scope
        } else {
          print "? (top-level)"
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
#  HEADER
# ═══════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║      codetracer  ·  $WORD$(printf '%*s' $((20 - ${#WORD})) '')║${RESET}"
echo -e "${BOLD}${CYAN}╚════════════════════════════════════╝${RESET}"
echo -e "  ${DIM}root:${RESET} $ROOT  ${DIM}lang:${RESET} $LANG  ${DIM}mode:${RESET} $MODE  ${DIM}ctx:${RESET} ±$CTX"

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
  *)
    warn "Unknown mode: $MODE"; usage
    ;;
esac

echo -e "\n${DIM}━━━ done ━━━${RESET}\n"
