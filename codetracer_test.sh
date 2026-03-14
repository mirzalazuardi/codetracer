#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  codetracer_test.sh — full test suite                       ║
# ║  Usage: bash codetracer_test.sh                             ║
# ║         zsh  codetracer_test.sh                             ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ─── Shell compat ─────────────────────────────────────────────
[ -n "${ZSH_VERSION:-}" ] && setopt SH_WORD_SPLIT KSH_ARRAYS 2>/dev/null || true

# ─── Resolve paths ────────────────────────────────────────────
# ${BASH_SOURCE[0]:-$0} : BASH_SOURCE[0] in bash, $0 in zsh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FIXTURES="$SCRIPT_DIR/tests/fixtures"
CT="$SCRIPT_DIR/codetracer.sh"

if [[ ! -f "$CT" ]]; then
  echo "ERROR: codetracer.sh not found at $CT"
  echo "Run from repo root: bash codetracer_test.sh"
  exit 1
fi

chmod +x "$CT"

# ─── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ─── Counters ─────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0
FAILURES=()

# ─── Helpers ──────────────────────────────────────────────────
suite() { echo -e "\n${BOLD}${CYAN}━━━ $1 ━━━${RESET}"; }

pass() {
  PASS=$(( PASS + 1 ))
  echo -e "  ${GREEN}✔${RESET}  $1"
}

fail() {
  FAIL=$(( FAIL + 1 ))
  echo -e "  ${RED}✘${RESET}  $1"
  [[ -n "${2:-}" ]] && echo -e "     ${DIM}Expected : $2${RESET}"
  [[ -n "${3:-}" ]] && echo -e "     ${DIM}Got      : $3${RESET}"
  FAILURES+=("$1")
}

skip() {
  SKIP=$(( SKIP + 1 ))
  echo -e "  ${YELLOW}⊘${RESET}  $1 ${DIM}(skipped — $2)${RESET}"
}

# Run codetracer, capture stdout+stderr, strip all ANSI color codes
run() {
  bash "$CT" "$@" 2>&1 \
    | sed 's/\x1b\[[0-9;]*[mGKHF]//g' \
    || true
}

# Assert output contains pattern (ANSI already stripped by run())
assert_contains() {
  local label="$1" pattern="$2" output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    pass "$label"
  else
    fail "$label" "$pattern" "(not found in output)"
  fi
}

# Assert output does NOT contain pattern
assert_not_contains() {
  local label="$1" pattern="$2" output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    fail "$label" "(should be absent)" "$pattern"
  else
    pass "$label"
  fi
}

# Assert minimum number of output lines
assert_min_lines() {
  local label="$1" min="$2" output="$3"
  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  if [[ "$count" -ge "$min" ]]; then
    pass "$label"
  else
    fail "$label" ">= $min lines" "$count lines"
  fi
}

# ─── Prerequisite: rg ─────────────────────────────────────────
RG_AVAILABLE=true
if ! command -v rg &>/dev/null; then
  RG_AVAILABLE=false
  echo -e "\n${YELLOW}⚠  ripgrep (rg) not found — install with:${RESET}"
  echo -e "   macOS : ${BOLD}brew install ripgrep${RESET}"
  echo -e "   Ubuntu: ${BOLD}sudo apt install ripgrep${RESET}"
  echo -e "   Arch  : ${BOLD}sudo pacman -S ripgrep${RESET}"
  echo -e "   Suites 2–10 and 13 require rg and will be skipped.\n"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 1 — CASE-VARIANT EXPANSION
#  Tests build_variants() via the variant table printed every run.
#  This suite runs without rg (uses --mode file which still prints
#  the variant table before rg is called).
# ══════════════════════════════════════════════════════════════
suite "1 · Case-Variant Expansion"

V=$(run process_payment "$FIXTURES" --mode file --lang ruby 2>/dev/null || true)

assert_contains "snake_case variant printed"        "process_payment"        "$V"
assert_contains "SCREAMING_SNAKE variant printed"   "PROCESS_PAYMENT"        "$V"
assert_contains "camelCase variant printed"         "processPayment"         "$V"
assert_contains "PascalCase variant printed"        "ProcessPayment"         "$V"
assert_contains "kebab-case variant printed"        "process-payment"        "$V"
assert_contains "Title Case variant printed"        "Process Payment"        "$V"

V2=$(run processPayment "$FIXTURES" --mode file --lang js 2>/dev/null || true)
assert_contains "camelCase input → snake_case"      "process_payment"        "$V2"
assert_contains "camelCase input → PascalCase"      "ProcessPayment"         "$V2"

V3=$(run ProcessPayment "$FIXTURES" --mode file --lang js 2>/dev/null || true)
assert_contains "PascalCase input → camelCase"      "processPayment"         "$V3"
assert_contains "PascalCase input → snake_case"     "process_payment"        "$V3"

V4=$(run process-payment "$FIXTURES" --mode file --lang ruby 2>/dev/null || true)
assert_contains "kebab input → snake_case"          "process_payment"        "$V4"
assert_contains "kebab input → PascalCase"          "ProcessPayment"         "$V4"

V5=$(run PROCESS_PAYMENT "$FIXTURES" --mode file --lang ruby 2>/dev/null || true)
assert_contains "SCREAMING_SNAKE input → snake_case" "process_payment"       "$V5"
assert_contains "SCREAMING_SNAKE input → camelCase"  "processPayment"        "$V5"

VSINGLE=$(run refund "$FIXTURES" --mode file 2>/dev/null || true)
assert_not_contains "Single word: no spurious underscore" "^_refund|refund_$" "$VSINGLE"

# ══════════════════════════════════════════════════════════════
#  SUITE 2 — MODE: DEF  (Ruby)
# ══════════════════════════════════════════════════════════════
suite "2 · Mode: def — Ruby"

if ! $RG_AVAILABLE; then
  for t in "def process_payment" "def self.process_payment" "module Billing" \
            "class PaymentService" "lambda def" "proc def" \
            "Definitions banner" "JS absent with --lang ruby"; do
    skip "$t" "rg not installed"
  done
else
  D=$(run process_payment "$FIXTURES" --lang ruby --mode def)

  assert_contains "def process_payment found"           "def process_payment"         "$D"
  assert_contains "def self.process_payment found"      "def self.process_payment"    "$D"
  assert_contains "module Billing detected"             "module Billing"              "$D"
  assert_contains "class PaymentService detected"       "class PaymentService"        "$D"
  assert_contains "lambda definition found"             "process_payment_logger"      "$D"
  assert_contains "proc definition found"               "process_payment_hook"        "$D"
  assert_contains "Definitions banner shown"            "DEFINITIONS"                 "$D"
  assert_not_contains "JS defs absent with --lang ruby" "function processPayment"     "$D"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 3 — MODE: DEF  (JS / TS)
# ══════════════════════════════════════════════════════════════
suite "3 · Mode: def — JS/TS"

if ! $RG_AVAILABLE; then
  for t in "function" "async function" "const arrow" "export function" \
            "export default" "class method" "TypeScript file" "Ruby absent"; do
    skip "$t" "rg not installed"
  done
else
  D=$(run processPayment "$FIXTURES" --lang js --mode def)

  assert_contains "function processPayment found"           "function processPayment"     "$D"
  assert_contains "async function found"                    "processPaymentWithRetry"     "$D"
  assert_contains "const arrow function found"              "processPaymentHandler"       "$D"
  assert_contains "export function found"                   "processPaymentExport"        "$D"
  assert_contains "export default function found"           "processPaymentDefault"       "$D"
  assert_contains "class method found"                      "class PaymentService"        "$D"
  assert_contains "TypeScript .ts file included"            "fixture_paymentService.ts"           "$D"
  assert_not_contains "Ruby defs absent with --lang js"     "def process_payment"         "$D"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 4 — MODE: DEF  (lang: all)
# ══════════════════════════════════════════════════════════════
suite "4 · Mode: def — lang: all (cross-language)"

if ! $RG_AVAILABLE; then
  skip "cross-lang def" "rg not installed"
else
  D=$(run process_payment "$FIXTURES" --lang all --mode def)

  assert_contains "Ruby def found in all-lang"    "def process_payment"      "$D"
  assert_contains "JS function found in all-lang" "function processPayment"  "$D"
  assert_contains "Ruby section header"           "Ruby Definitions"         "$D"
  assert_contains "JS section header"             "JS/TS Definitions"        "$D"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 5 — MODE: CALL
# ══════════════════════════════════════════════════════════════
suite "5 · Mode: call"

if ! $RG_AVAILABLE; then
  skip "call sites — Ruby" "rg not installed"
  skip "call sites — JS"   "rg not installed"
else
  CR=$(run process_payment "$FIXTURES" --lang ruby --mode call)
  assert_contains "Ruby: call in retry method"    "retry_process_payment"    "$CR"
  assert_contains "Ruby: call in batch_process"   "batch_process"            "$CR"
  assert_contains "Ruby: call in OrderController" "OrderController"          "$CR"
  assert_contains "Call sites banner shown"       "CALL SITES"               "$CR"

  CJ=$(run processPayment "$FIXTURES" --lang js --mode call)
  assert_contains "JS: call in checkout"          "checkout"                 "$CJ"
  assert_contains "JS: call in handleSubmit"      "handleSubmit"             "$CJ"
  assert_contains "JS: call in runBatch"          "runBatch"                 "$CJ"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 6 — MODE: FLOW
# ══════════════════════════════════════════════════════════════
suite "6 · Mode: flow"

if ! $RG_AVAILABLE; then
  skip "data flow — Ruby" "rg not installed"
  skip "data flow — JS"   "rg not installed"
else
  FR=$(run process_payment "$FIXTURES" --lang ruby --mode flow)
  assert_contains "Flow: Assignments section header"    "Assignments"               "$FR"
  assert_contains "Flow: As argument section header"    "As argument"               "$FR"
  assert_contains "Flow: Returned section header"       "Returned"                  "$FR"
  assert_contains "Flow: Mutations section header"      "Mutations"                 "$FR"
  assert_contains "Ruby assignment found"               "process_payment_retries"   "$FR"
  assert_contains "Ruby return found"                   "return process_payment"    "$FR"
  assert_contains "Ruby mutation (push) found"          "push"                      "$FR"

  FJ=$(run processPayment "$FIXTURES" --lang js --mode flow)
  assert_contains "JS assignment: processPaymentFn"    "processPaymentFn"          "$FJ"
  assert_contains "JS return: return processPayment"   "return processPayment"     "$FJ"
  assert_contains "JS mutation: paymentQueue.push"     "paymentQueue.push"         "$FJ"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 7 — MODE: FILE
# ══════════════════════════════════════════════════════════════
suite "7 · Mode: file"

if ! $RG_AVAILABLE; then
  skip "file map" "rg not installed"
else
  FM=$(run process_payment "$FIXTURES" --mode file)
  assert_contains "payment_service.rb listed"         "fixture_payment_service.rb"    "$FM"
  assert_contains "paymentService.js listed"          "fixture_paymentService.js"     "$FM"
  assert_contains "paymentService.ts listed"          "fixture_paymentService.ts"     "$FM"
  assert_not_contains "refund_service.rb NOT listed"  "fixture_refund_service.rb"     "$FM"
  assert_contains "Hit count shown"                   "[0-9]+ hits"           "$FM"
  assert_contains "Total file count shown"            "Total"                 "$FM"
  assert_contains "FILE MAP banner shown"             "FILE MAP"              "$FM"

  FRB=$(run process_payment "$FIXTURES" --mode file --lang ruby)
  assert_contains     "Ruby file listed under --lang ruby" "fixture_payment_service.rb"  "$FRB"
  assert_not_contains "JS file absent under --lang ruby"   "fixture_paymentService.js"   "$FRB"

  FJS=$(run processPayment "$FIXTURES" --mode file --lang js)
  assert_contains     "JS file listed under --lang js"     "fixture_paymentService.js"   "$FJS"
  assert_not_contains "Ruby file absent under --lang js"   "fixture_payment_service.rb"  "$FJS"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 8 — MODE: FULL
# ══════════════════════════════════════════════════════════════
suite "8 · Mode: full"

if ! $RG_AVAILABLE; then
  skip "full mode — all sections" "rg not installed"
else
  FL=$(run process_payment "$FIXTURES" --mode full)
  assert_contains "DEFINITIONS section present" "DEFINITIONS"  "$FL"
  assert_contains "CALL SITES section present"  "CALL SITES"   "$FL"
  assert_contains "DATA FLOW section present"   "DATA FLOW"    "$FL"
  assert_contains "FILE MAP section present"    "FILE MAP"     "$FL"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 9 — FLAG: --ctx
# ══════════════════════════════════════════════════════════════
suite "9 · Flag: --ctx (context lines)"

if ! $RG_AVAILABLE; then
  skip "--ctx comparison" "rg not installed"
else
  C1=$(run process_payment "$FIXTURES" --mode call --lang ruby --ctx 1)
  C6=$(run process_payment "$FIXTURES" --mode call --lang ruby --ctx 6)
  L1=$(echo "$C1" | wc -l | tr -d ' ')
  L6=$(echo "$C6" | wc -l | tr -d ' ')

  if [[ "$L6" -gt "$L1" ]]; then
    pass "--ctx 6 produces more output than --ctx 1 ($L6 > $L1 lines)"
  else
    fail "--ctx 6 should produce more output than --ctx 1" "> $L1 lines" "$L6 lines"
  fi
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 10 — FLAG: --scope
# ══════════════════════════════════════════════════════════════
suite "10 · Flag: --scope"

if ! $RG_AVAILABLE; then
  skip "--scope output" "rg not installed"
else
  SC=$(run process_payment "$FIXTURES" --mode call --lang ruby --scope)
  assert_contains "scope → label present"          "scope ->"          "$SC"
  assert_contains "ENCLOSING SCOPE banner shown"   "ENCLOSING SCOPE"   "$SC"
  assert_contains "enclosing def detected"         "def "              "$SC"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 11 — FLAG: --help
#  Tests both -h and --help as FIRST argument (the bug that was fixed)
# ══════════════════════════════════════════════════════════════
suite "11 · Flag: --help"

HELP=$(bash "$CT" --help 2>&1 | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)
HELPH=$(bash "$CT" -h      2>&1 | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)

assert_contains "SYNOPSIS present"                "SYNOPSIS"              "$HELP"
assert_contains "OPTIONS present"                 "OPTIONS"               "$HELP"
assert_contains "EXAMPLES present"                "EXAMPLES"              "$HELP"
assert_contains "--mode documented"               "[-][-]mode"             "$HELP"
assert_contains "--lang documented"               "[-][-]lang"             "$HELP"
assert_contains "--scope documented"             "[-][-]scope"            "$HELP"
assert_contains "--ctags documented"             "[-][-]ctags"            "$HELP"
assert_contains "--inter documented"             "[-][-]inter"            "$HELP"
assert_contains "--ctx documented"               "[-][-]ctx"              "$HELP"
assert_contains "def mode documented"             "def"                   "$HELP"
assert_contains "call mode documented"            "call"                  "$HELP"
assert_contains "flow mode documented"            "flow"                  "$HELP"
assert_contains "file mode documented"            "file"                  "$HELP"
assert_contains "full mode documented"            "full"                  "$HELP"
assert_contains "ruby lang documented"            "ruby"                  "$HELP"
assert_contains "js lang documented"              "\bjs\b"                "$HELP"
assert_contains "codetracer name in help"          "codetracer"             "$HELP"
assert_min_lines "help output >= 50 lines"        50                      "$HELP"
assert_contains "-h shorthand also works"         "SYNOPSIS"              "$HELPH"

# ══════════════════════════════════════════════════════════════
#  SUITE 12 — EDGE CASES
# ══════════════════════════════════════════════════════════════
suite "12 · Edge Cases"

# No args → shows usage
NO_ARGS=$(bash "$CT" 2>&1 | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)
assert_contains "No args shows SYNOPSIS"          "SYNOPSIS"              "$NO_ARGS"

# Unknown lang → warns but does not crash
BAD_LANG=$(run process_payment "$FIXTURES" --lang python 2>&1 || true)
assert_contains "Unknown lang warns gracefully"   "Unknown lang"          "$BAD_LANG"

# Unknown mode → warns + shows usage
BAD_MODE=$(run process_payment "$FIXTURES" --mode nonexistent 2>&1 || true)
assert_contains "Unknown mode warns gracefully"   "Unknown mode|SYNOPSIS" "$BAD_MODE"

# --ctx 0 → runs without crash
CTX0=$(run process_payment "$FIXTURES" --mode call --lang ruby --ctx 0 2>&1 || true)
assert_contains "--ctx 0 does not crash"          "CALL SITES"            "$CTX0"

# Header always present
HD=$(run process_payment "$FIXTURES" --mode file)
assert_contains "Header: codetracer banner shown" "codetracer"            "$HD"
assert_contains "Header: root path shown"         "root:"                 "$HD"
assert_contains "Header: lang shown"              "lang:"                 "$HD"
assert_contains "Header: mode shown"              "mode:"                 "$HD"

# Done banner always at end
assert_contains "Done banner at end of run"       "done"                  "$HD"

# ══════════════════════════════════════════════════════════════
#  SUITE 13 — FALSE POSITIVE GUARD
# ══════════════════════════════════════════════════════════════
suite "13 · False Positive Guard"

if ! $RG_AVAILABLE; then
  skip "false positive checks" "rg not installed"
else
  FP=$(run process_payment "$FIXTURES" --mode file 2>&1 || true)
  assert_not_contains "refund_service.rb absent from file map"    "fixture_refund_service.rb"    "$FP"

  FPD=$(run process_payment "$FIXTURES" --mode def --lang ruby 2>&1 || true)
  assert_not_contains "issue_refund absent in process_payment def" \
    "def issue_refund|def full_refund|def partial_refund"          "$FPD"

  FPL=$(run processPayment "$FIXTURES" --mode def --lang js 2>&1 || true)
  assert_not_contains "Ruby defs absent under --lang js"          "def process_payment\b" "$FPL"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 14 — BUG REGRESSIONS
#  Documents specific bugs that were found and fixed.
# ══════════════════════════════════════════════════════════════
suite "14 · Bug Regressions"

# BUG: --help as first argument was consumed as WORD (treated as a symbol)
# FIX: added early exit before WORD="$1" in arg parse
HELP_FIRST=$(bash "$CT" --help 2>&1 | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)
assert_contains     "BUG#1: --help first arg shows help, not search"  "SYNOPSIS"         "$HELP_FIRST"
assert_not_contains "BUG#1: --help does not treat '--help' as symbol" "Case variants"    "$HELP_FIRST"

# BUG: -h shorthand also affected
HELPH_FIRST=$(bash "$CT" -h 2>&1 | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)
assert_contains     "BUG#1: -h first arg shows help, not search"      "SYNOPSIS"         "$HELPH_FIRST"

# BUG: ANSI codes in output could confuse downstream grep pipelines
# The run() helper now strips ANSI — verify that the stripped output is clean
ANSI_TEST=$(run process_payment "$FIXTURES" --mode file 2>&1 || true)
assert_not_contains "ANSI codes stripped from run() output" $'\x1b\[' "$ANSI_TEST"

# ══════════════════════════════════════════════════════════════
#  SUITE 15 — OPTIONAL: ctags
# ══════════════════════════════════════════════════════════════
suite "15 · Optional: ctags"

if ! $RG_AVAILABLE; then
  skip "ctags lookup" "rg not installed (required alongside ctags)"
elif command -v ctags &>/dev/null; then
  rm -f "$FIXTURES/tags"
  CT_OUT=$(run process_payment "$FIXTURES" --mode def --ctags --lang ruby)
  assert_contains "ctags: CTAGS LOOKUP section shown"  "CTAGS LOOKUP"     "$CT_OUT"
  assert_contains "ctags: symbol found in index"       "process_payment"  "$CT_OUT"
  if [[ -f "$FIXTURES/tags" ]]; then
    pass "ctags: tags file created at fixtures/tags"
  else
    fail "ctags: tags file not created"
  fi
  rm -f "$FIXTURES/tags"
else
  skip "ctags lookup"        "ctags not installed (brew install universal-ctags)"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 16 — OPTIONAL: fzf
# ══════════════════════════════════════════════════════════════
suite "16 · Optional: fzf / interactive"

if ! $RG_AVAILABLE; then
  skip "interactive mode" "rg not installed"
elif command -v fzf &>/dev/null; then
  INTER=$(timeout 10 bash -c 'echo "" | bash "'"$CT"'" process_payment "'"$FIXTURES"'" --inter 2>&1' \
    | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)
  assert_contains "Interactive mode banner shown" "INTERACTIVE MODE" "$INTER"
else
  skip "interactive mode (--inter)" "fzf not installed (brew install fzf)"
fi


# ══════════════════════════════════════════════════════════════
#  SUITE 17 — ZSH COMPATIBILITY
#  Runs the script under `zsh` and verifies it produces the
#  same core output as bash. Skipped if zsh is not installed.
# ══════════════════════════════════════════════════════════════
suite "17 · zsh Compatibility"

ZSH_BIN=""
for z in zsh /bin/zsh /usr/bin/zsh /usr/local/bin/zsh /opt/homebrew/bin/zsh; do
  command -v "$z" &>/dev/null && { ZSH_BIN="$z"; break; }
done

if [[ -z "$ZSH_BIN" ]]; then
  skip "all zsh tests" "zsh not installed (brew install zsh)"
else
  # Helper: run codetracer via zsh, strip ANSI
  run_zsh() {
    "$ZSH_BIN" "$CT" "$@" 2>&1 \
      | sed 's/\x1b\[[0-9;]*[mGKHF]//g' \
      || true
  }

  # ── 17a: shell detection + options ───────────────────────
  ZSH_INIT=$(run_zsh process_payment "$FIXTURES" --mode file 2>&1 || true)
  assert_not_contains "zsh: no 'unsupported shell' error"     "unsupported shell"      "$ZSH_INIT"
  assert_not_contains "zsh: no bash version error"            "requires bash"          "$ZSH_INIT"
  assert_not_contains "zsh: no bad substitution error"        "bad substitution"       "$ZSH_INIT"
  assert_contains     "zsh: header banner shown"              "codetracer"             "$ZSH_INIT"
  assert_contains     "zsh: done banner shown"                "done"                   "$ZSH_INIT"

  # ── 17b: variant expansion (core algorithm) ──────────────
  ZSH_VAR=$(run_zsh process_payment "$FIXTURES" --mode file 2>&1 || true)
  assert_contains "zsh: snake_case variant"                   "process_payment"        "$ZSH_VAR"
  assert_contains "zsh: camelCase variant"                    "processPayment"         "$ZSH_VAR"
  assert_contains "zsh: PascalCase variant"                   "ProcessPayment"         "$ZSH_VAR"
  assert_contains "zsh: SCREAMING_SNAKE variant"              "PROCESS_PAYMENT"        "$ZSH_VAR"
  assert_contains "zsh: kebab-case variant"                   "process-payment"        "$ZSH_VAR"

  # camelCase input in zsh
  ZSH_CAM=$(run_zsh processPayment "$FIXTURES" --mode file 2>&1 || true)
  assert_contains "zsh: camelCase input → snake_case"         "process_payment"        "$ZSH_CAM"
  assert_contains "zsh: camelCase input → PascalCase"         "ProcessPayment"         "$ZSH_CAM"

  # ── 17c: --help works under zsh ──────────────────────────
  ZSH_HELP=$(run_zsh --help 2>&1 || true)
  assert_contains     "zsh: --help shows SYNOPSIS"            "SYNOPSIS"               "$ZSH_HELP"
  assert_not_contains "zsh: --help not treated as WORD"       "Case variants"          "$ZSH_HELP"

  # ── 17d: rg-dependent modes under zsh ────────────────────
  if ! $RG_AVAILABLE; then
    skip "zsh: rg-dependent mode tests" "rg not installed"
  else
    ZSH_DEF=$(run_zsh process_payment "$FIXTURES" --lang ruby --mode def 2>&1 || true)
    assert_contains "zsh: def mode finds Ruby method"         "def process_payment"    "$ZSH_DEF"
    assert_contains "zsh: Definitions banner shown"           "DEFINITIONS"            "$ZSH_DEF"

    ZSH_CALL=$(run_zsh process_payment "$FIXTURES" --lang ruby --mode call 2>&1 || true)
    assert_contains "zsh: call mode finds call site"          "CALL SITES"             "$ZSH_CALL"

    ZSH_FLOW=$(run_zsh process_payment "$FIXTURES" --lang ruby --mode flow 2>&1 || true)
    assert_contains "zsh: flow mode runs all subsections"     "Assignments"            "$ZSH_FLOW"
    assert_contains "zsh: flow mode finds return"             "return process_payment" "$ZSH_FLOW"

    ZSH_FILE=$(run_zsh process_payment "$FIXTURES" --mode file 2>&1 || true)
    assert_contains     "zsh: file mode lists rb file"        "fixture_payment_service.rb"     "$ZSH_FILE"
    assert_not_contains "zsh: file mode excludes refund file" "fixture_refund_service.rb"      "$ZSH_FILE"
  fi

  # ── 17e: output parity (bash vs zsh variant table) ───────
  BASH_V=$(bash "$CT" processPayment "$FIXTURES" --mode file 2>&1 \
    | sed 's/\x1b\[[0-9;]*[mGKHF]//g' || true)
  ZSH_V=$(run_zsh processPayment "$FIXTURES" --mode file 2>&1 || true)

  # Both should produce the same variant list
  for variant in process_payment PROCESS_PAYMENT processPayment ProcessPayment process-payment; do
    if echo "$BASH_V" | grep -q "$variant" && echo "$ZSH_V" | grep -q "$variant"; then
      pass "bash/zsh parity: $variant in both outputs"
    elif ! echo "$BASH_V" | grep -q "$variant" && ! echo "$ZSH_V" | grep -q "$variant"; then
      pass "bash/zsh parity: $variant absent in both (consistent)"
    else
      fail "bash/zsh parity: $variant differs between bash and zsh"
    fi
  done
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 18 — MODE: ROUTE (--action)
# ══════════════════════════════════════════════════════════════
suite "18 · Mode: route (--action)"

RAILS_FIXTURES="$SCRIPT_DIR/tests/fixtures/rails_app"

if ! $RG_AVAILABLE; then
  for t in "action parsing" "callback detection" "service detection" "async detection" "tree formatting"; do
    skip "$t" "rg not installed"
  done
elif [[ ! -d "$RAILS_FIXTURES" ]]; then
  for t in "action parsing" "callback detection" "service detection" "async detection" "tree formatting"; do
    skip "$t" "rails_app fixtures not found"
  done
else
  # Basic action trace
  RT=$(run --action "OrdersController#refund" "$RAILS_FIXTURES")

  assert_contains "controller found"                "OrdersController"                     "$RT"
  assert_contains "action trace banner"             "ACTION TRACE"                         "$RT"
  assert_contains "def refund shown"                "def refund"                           "$RT"

  # Callback detection
  assert_contains "before_action shown"             "before_action"                        "$RT"
  assert_contains "callback authenticate_user"      "authenticate_user"                    "$RT"
  assert_contains "callback set_order"              "set_order"                            "$RT"
  assert_contains "callback origin shown"           "ApplicationController"                "$RT"
  assert_contains "after_action shown"              "after_action"                         "$RT"
  assert_contains "around_action shown"             "around_action"                        "$RT"

  # Service call detection
  assert_contains "service call detected"           "call:.*RefundService"                 "$RT"

  # Async job detection
  assert_contains "sidekiq job detected"            "enqueue:.*RefundNotificationJob"      "$RT"
  assert_contains "async marker shown"              "\\[async\\]"                          "$RT"
  assert_contains "second job detected"             "AuditLogJob"                          "$RT"

  # Conditional detection
  assert_contains "if condition shown"              "if @order.refundable"                 "$RT"
  assert_contains "else branch shown"               "else"                                 "$RT"

  # Tree formatting
  assert_contains "tree branch char"                "├──"                                  "$RT"
  assert_contains "tree last char"                  "└──"                                  "$RT"
  assert_contains "line numbers shown"              ":[0-9]+"                              "$RT"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 19 — MODE: ROUTE (--route)
# ══════════════════════════════════════════════════════════════
suite "19 · Mode: route (--route)"

if ! $RG_AVAILABLE; then
  skip "route parsing" "rg not installed"
elif [[ ! -d "$RAILS_FIXTURES" ]]; then
  skip "route parsing" "rails_app fixtures not found"
else
  # Test route parsing with direct route (POST /checkout → checkout#create)
  # Note: CheckoutController doesn't exist, so we expect "Controller not found"
  RT=$(run --route "POST /checkout" "$RAILS_FIXTURES" 2>&1 || true)

  assert_contains "route trace banner"              "ROUTE TRACE"                          "$RT"
  assert_contains "resolves to CheckoutController"  "CheckoutController"                   "$RT"
  assert_contains "resolves to create action"       "create"                               "$RT"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 20 — NAMESPACED CONTROLLER
# ══════════════════════════════════════════════════════════════
suite "20 · Namespaced controller"

if ! $RG_AVAILABLE; then
  skip "namespaced controller" "rg not installed"
elif [[ ! -d "$RAILS_FIXTURES" ]]; then
  skip "namespaced controller" "rails_app fixtures not found"
else
  RT=$(run --action "Admin::OrdersController#force_refund" "$RAILS_FIXTURES")

  assert_contains "namespaced controller found"     "Admin::OrdersController"              "$RT"
  assert_contains "force_refund action shown"       "def force_refund"                     "$RT"
  assert_contains "admin service detected"          "AdminRefundService"                   "$RT"
  assert_contains "admin job detected"              "AdminNotificationJob"                 "$RT"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 21 — ERROR HANDLING
# ══════════════════════════════════════════════════════════════
suite "21 · Error handling"

if ! $RG_AVAILABLE; then
  skip "error handling" "rg not installed"
elif [[ ! -d "$RAILS_FIXTURES" ]]; then
  skip "error handling" "rails_app fixtures not found"
else
  # Non-existent controller
  RT_NO_CTRL=$(run --action "NonExistentController#index" "$RAILS_FIXTURES" 2>&1 || true)
  assert_contains "missing controller error"        "Controller not found"                 "$RT_NO_CTRL"

  # Non-existent action
  RT_NO_ACT=$(run --action "OrdersController#nonexistent" "$RAILS_FIXTURES" 2>&1 || true)
  assert_contains "missing action error"            "Action not found"                     "$RT_NO_ACT"

  # Invalid action format
  RT_BAD_FMT=$(run --action "InvalidFormat" "$RAILS_FIXTURES" 2>&1 || true)
  assert_contains "invalid format error"            "Invalid action format"                "$RT_BAD_FMT"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 22 — PARAMS DETECTION
# ══════════════════════════════════════════════════════════════
suite "22 · Params detection"

if ! $RG_AVAILABLE; then
  skip "params detection" "rg not installed"
elif [[ ! -d "$RAILS_FIXTURES" ]]; then
  skip "params detection" "rails_app fixtures not found"
else
  # Test params[:key] detection
  RT_SEARCH=$(run --action "OrdersController#search" "$RAILS_FIXTURES")

  assert_contains "params[:status] detected"        "params:.*:status"                     "$RT_SEARCH"
  assert_contains "params[:page] detected"          "params:.*:page"                       "$RT_SEARCH"
  assert_contains "params.fetch detected"           "params:.*:per_page"                   "$RT_SEARCH"
  assert_contains "query marker shown"              "\[query\]"                            "$RT_SEARCH"

  # Test params.require and .permit detection
  RT_BULK=$(run --action "OrdersController#bulk_update" "$RAILS_FIXTURES")

  assert_contains "params.require detected"         "params:.*:order"                      "$RT_BULK"
  assert_contains "permit detected"                 "permit:"                              "$RT_BULK"
  assert_contains "order_ids param detected"        "params:.*:order_ids"                  "$RT_BULK"
fi

# ══════════════════════════════════════════════════════════════
#  SUITE 23 — CURL FILE PARSING
# ══════════════════════════════════════════════════════════════
suite "23 · Curl file parsing"

if ! $RG_AVAILABLE; then
  skip "curl file parsing" "rg not installed"
elif [[ ! -d "$RAILS_FIXTURES" ]]; then
  skip "curl file parsing" "rails_app fixtures not found"
else
  CURL_DIR="$RAILS_FIXTURES/curls"

  # Test POST with query params and body
  RT_POST=$(run --route "$CURL_DIR/refund_order.sh" "$RAILS_FIXTURES")

  assert_contains "curl parsed correctly"           "Parsed curl: POST /orders/:id/refund" "$RT_POST"
  assert_contains "query params extracted"          "Query params:.*notify.*priority"      "$RT_POST"
  assert_contains "body params extracted"           "Body params:.*reason.*amount.*notes"  "$RT_POST"
  assert_contains "resolves to refund action"       "OrdersController#refund"              "$RT_POST"
  assert_contains "shows expected query params"     "query:.*notify.*priority"             "$RT_POST"
  assert_contains "shows expected body params"      "body:.*reason.*amount.*notes"         "$RT_POST"

  # Test GET with query params (no body)
  RT_GET=$(run --route "$CURL_DIR/search_orders.sh" "$RAILS_FIXTURES")

  assert_contains "GET curl parsed"                 "Parsed curl: GET /orders"             "$RT_GET"
  assert_contains "GET query params extracted"      "Query params:.*status.*page"          "$RT_GET"
  assert_contains "maps to index action"            "OrdersController#index"               "$RT_GET"
fi

# ══════════════════════════════════════════════════════════════
#  SUMMARY
# ══════════════════════════════════════════════════════════════
TOTAL=$(( PASS + FAIL + SKIP ))

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Results  ·  $TOTAL tests${RESET}"
echo -e "  ${GREEN}✔ Passed : $PASS${RESET}"
echo -e "  ${RED}✘ Failed : $FAIL${RESET}"
echo -e "  ${YELLOW}⊘ Skipped: $SKIP${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [[ "$FAIL" -gt 0 ]]; then
  echo -e "\n${BOLD}${RED}Failed tests:${RESET}"
  for f in "${FAILURES[@]}"; do
    echo -e "  ${RED}✘${RESET}  $f"
  done
  echo ""
  exit 1
fi

echo -e "\n${GREEN}${BOLD}All tests passed.${RESET}\n"
exit 0
