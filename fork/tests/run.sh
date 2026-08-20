#!/bin/sh
# Minimal tests for fork/grok. Run from anywhere:
#   sh ~/repos/me/grok-build/fork/tests/run.sh

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FORK_DIR=$(CDPATH= cd -- "$TEST_DIR/.." && pwd)
LAUNCHER="$FORK_DIR/grok"

# Fixture revs — not Grok product versions or official binary hashes.
PIN_REV=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
NEWER_REV=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

passed=0
failed=0

fail() {
  failed=$((failed + 1))
  printf 'FAIL  %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    printf '      %s\n' "$2" >&2
  fi
}

pass() {
  passed=$((passed + 1))
  printf 'ok    %s\n' "$1"
}

assert_eq() {
  name=$1
  got=$2
  want=$3
  if [ "$got" = "$want" ]; then
    pass "$name"
  else
    fail "$name" "got '$got', want '$want'"
  fi
}

assert_contains() {
  name=$1
  haystack=$2
  needle=$3
  case $haystack in
    *"$needle"*) pass "$name" ;;
    *) fail "$name" "missing '$needle' in: $haystack" ;;
  esac
}

assert_status() {
  name=$1
  got=$2
  want=$3
  if [ "$got" -eq "$want" ]; then
    pass "$name"
  else
    fail "$name" "exit $got, want $want"
  fi
}

GROK_FORK_SOURCED=1
# shellcheck disable=SC1090
. "$LAUNCHER"

assert_eq "trim strips whitespace" "$(trim "  ${PIN_REV}  ")" "$PIN_REV"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

export GROK_HOME="$WORKDIR/home"
mkdir -p "$GROK_HOME"

printf '%s\n' "$PIN_REV" >"$WORKDIR/base-source-rev"
BASE_REV_FILE="$WORKDIR/base-source-rev"
assert_eq "read_base_source_rev" "$(read_base_source_rev)" "$PIN_REV"

printf '1.0.5\n' >"$WORKDIR/base-source-rev-bad"
BASE_REV_FILE="$WORKDIR/base-source-rev-bad"
if read_base_source_rev >/dev/null 2>&1; then
  fail "read_base_source_rev rejects cargo-version pin"
else
  pass "read_base_source_rev rejects cargo-version pin"
fi
BASE_REV_FILE="$WORKDIR/base-source-rev"

mkdir -p "$WORKDIR/src-same" "$WORKDIR/src-newer"
printf '%s\n' "$PIN_REV" >"$WORKDIR/src-same/SOURCE_REV"
printf '%s\n' "$NEWER_REV" >"$WORKDIR/src-newer/SOURCE_REV"

GIT_DIR="$WORKDIR/src-same"
assert_eq "read_local_source_rev same dump" "$(read_local_source_rev)" "$PIN_REV"
GIT_DIR="$WORKDIR/src-newer"
assert_eq "read_local_source_rev newer dump" "$(read_local_source_rev)" "$NEWER_REV"
GIT_DIR="$WORKDIR/not-a-repo"
assert_eq "read_local_source_rev missing file" "$(read_local_source_rev)" ""

PUBLIC_CACHE_FILE="$GROK_HOME/fork-public-source-rev"
CACHE_TTL_SECS=300
printf '%s\n%s\n' "$(date +%s)" "cccccccccccccccccccccccccccccccccccccccc" >"$PUBLIC_CACHE_FILE"
GIT_DIR="$WORKDIR/not-a-repo"
assert_eq "cached_public_source_rev uses fresh cache" "$(cached_public_source_rev)" "cccccccccccccccccccccccccccccccccccccccc"

printf '0\n%s\n' "$PIN_REV" >"$PUBLIC_CACHE_FILE"
GIT_DIR="$WORKDIR/not-a-repo"
GROK_FORK_SKIP_NETWORK=1
assert_eq "cached_public_source_rev returns stale cache without blocking" "$(cached_public_source_rev)" "$PIN_REV"

rm -f "$PUBLIC_CACHE_FILE"
GIT_DIR="$WORKDIR/src-newer"
GROK_FORK_SKIP_NETWORK=1
assert_eq "cached_public_source_rev falls back to local SOURCE_REV" "$(cached_public_source_rev)" "$NEWER_REV"

printf '%s\n1.0.5\n' "$(date +%s)" >"$PUBLIC_CACHE_FILE"
GIT_DIR="$WORKDIR/src-same"
GROK_FORK_SKIP_NETWORK=1
assert_eq "cached_public_source_rev ignores cargo-version cache" "$(cached_public_source_rev)" "$PIN_REV"

PUBLIC_CACHE_FILE="$GROK_HOME/blocked-dir/fork-public-source-rev"
printf 'x\n' >"$GROK_HOME/blocked-dir"
GIT_DIR="$WORKDIR/src-same"
GROK_FORK_SKIP_NETWORK=1
assert_eq "cached_public_source_rev survives cache mkdir failure" "$(cached_public_source_rev)" "$PIN_REV"
PUBLIC_CACHE_FILE="$GROK_HOME/fork-public-source-rev"
rm -f "$GROK_HOME/blocked-dir"

FAKE_BIN="$WORKDIR/fake-grok"
cat >"$FAKE_BIN" <<'EOF'
#!/bin/sh
printf 'fake-grok'
if [ "$#" -gt 0 ]; then
  printf ' %s' "$@"
fi
printf '\n'
exit 0
EOF
chmod +x "$FAKE_BIN"

run_launcher() {
  GROK_FORK_BIN="$FAKE_BIN" \
    GROK_FORK_BASE_REV_FILE="$WORKDIR/base-source-rev" \
    GROK_FORK_GIT_DIR="${GROK_FORK_GIT_DIR:-$WORKDIR/src-same}" \
    GROK_FORK_SKIP_NETWORK=1 \
    GROK_HOME="$GROK_HOME" \
    GROK_FORK_CHECK_TTL="${GROK_FORK_CHECK_TTL:-0}" \
    GROK_FORK_SKIP_UPDATE_CHECK="${GROK_FORK_SKIP_UPDATE_CHECK:-0}" \
    GROK_FORK_ASSUME_TTY="${GROK_FORK_ASSUME_TTY:-0}" \
    "$LAUNCHER" "$@"
}

printf '%s\n' "$PIN_REV" >"$WORKDIR/base-source-rev"
rm -f "$PUBLIC_CACHE_FILE"
out=$(run_launcher --version 2>"$WORKDIR/err") || status=$?
status=${status:-0}
assert_status "public source same as pin — runs" "$status" 0
assert_eq "public source same as pin — execs" "$out" "fake-grok --version"

rm -f "$PUBLIC_CACHE_FILE"
out=$(run_launcher -r sess-123 --continue 2>"$WORKDIR/err") || status=$?
status=${status:-0}
assert_status "forwards resume flags — runs" "$status" 0
assert_eq "forwards resume flags — args" "$out" "fake-grok -r sess-123 --continue"
if grep -q 'Public grok-build SOURCE_REV' "$WORKDIR/err"; then
  fail "public source same as pin — no prompt" "$(cat "$WORKDIR/err")"
else
  pass "public source same as pin — no prompt"
fi

printf '%s\n' "$PIN_REV" >"$WORKDIR/base-source-rev"
rm -f "$PUBLIC_CACHE_FILE"
out=$(GROK_FORK_GIT_DIR="$WORKDIR/src-newer" run_launcher --version 2>"$WORKDIR/err") || status=$?
status=${status:-0}
assert_status "public source newer non-tty still runs" "$status" 0
err=$(cat "$WORKDIR/err")
assert_contains "public source newer mentions public SOURCE_REV" "$err" "Public grok-build SOURCE_REV is ${NEWER_REV}"
assert_contains "public source newer mentions pin" "$err" "pinned to ${PIN_REV}"
assert_contains "public source newer says non-interactive" "$err" "Non-interactive"
if grep -q 'Official grok' "$WORKDIR/err"; then
  fail "prompt does not mention official binary" "$(cat "$WORKDIR/err")"
else
  pass "prompt does not mention official binary"
fi

rm -f "$PUBLIC_CACHE_FILE"
if printf 'n\n' | GROK_FORK_ASSUME_TTY=1 GROK_FORK_GIT_DIR="$WORKDIR/src-newer" \
  run_launcher hello >"$WORKDIR/out" 2>"$WORKDIR/err"; then
  fail "public source newer tty + n should stop" "exit 0, out=$(cat "$WORKDIR/out")"
else
  assert_status "public source newer tty + n stops" "$?" 1
fi
if grep -q 'Stopped' "$WORKDIR/err"; then
  pass "public source newer tty + n prints Stopped"
else
  fail "public source newer tty + n prints Stopped" "$(cat "$WORKDIR/err")"
fi
if grep -q fake-grok "$WORKDIR/out"; then
  fail "public source newer tty + n must not exec binary" "$(cat "$WORKDIR/out")"
else
  pass "public source newer tty + n does not exec binary"
fi

rm -f "$PUBLIC_CACHE_FILE"
if printf '\n' | GROK_FORK_ASSUME_TTY=1 GROK_FORK_GIT_DIR="$WORKDIR/src-newer" \
  run_launcher hello >"$WORKDIR/out" 2>"$WORKDIR/err"; then
  assert_eq "public source newer tty + enter runs fork" "$(cat "$WORKDIR/out")" "fake-grok hello"
else
  fail "public source newer tty + enter should run" "exit $?"
fi

rm -f "$PUBLIC_CACHE_FILE"
if printf 'Y\n' | GROK_FORK_ASSUME_TTY=1 GROK_FORK_GIT_DIR="$WORKDIR/src-newer" \
  run_launcher hello >"$WORKDIR/out" 2>/dev/null; then
  assert_eq "public source newer tty + Y runs fork" "$(cat "$WORKDIR/out")" "fake-grok hello"
else
  fail "public source newer tty + Y should run" "exit $?"
fi

printf '%s\n' "$PIN_REV" >"$WORKDIR/base-source-rev"
rm -f "$PUBLIC_CACHE_FILE"
out=$(GROK_FORK_GIT_DIR="$WORKDIR/missing-git" run_launcher ping 2>"$WORKDIR/err") || status=$?
status=${status:-0}
assert_status "missing local SOURCE_REV still runs" "$status" 0
if grep -q 'Public grok-build SOURCE_REV' "$WORKDIR/err"; then
  fail "missing local SOURCE_REV does not prompt" "$(cat "$WORKDIR/err")"
else
  pass "missing local SOURCE_REV does not prompt"
fi

printf '%s\n' "$PIN_REV" >"$WORKDIR/base-source-rev"
rm -f "$PUBLIC_CACHE_FILE"
out=$(GROK_FORK_SKIP_UPDATE_CHECK=1 GROK_FORK_GIT_DIR="$WORKDIR/src-newer" \
  run_launcher ping 2>"$WORKDIR/err") || status=$?
status=${status:-0}
assert_status "skip check ignores newer public source" "$status" 0
if grep -q 'Public grok-build SOURCE_REV' "$WORKDIR/err"; then
  fail "skip check ignores newer public source (no warn)" "$(cat "$WORKDIR/err")"
else
  pass "skip check ignores newer public source (no warn)"
fi

if GROK_FORK_BIN="$WORKDIR/missing" \
  GROK_FORK_BASE_REV_FILE="$WORKDIR/base-source-rev" \
  GROK_HOME="$GROK_HOME" \
  GROK_FORK_SKIP_UPDATE_CHECK=1 \
  "$LAUNCHER" --version >"$WORKDIR/out" 2>"$WORKDIR/err"; then
  fail "missing binary exits 127" "exit 0"
else
  assert_status "missing binary exits 127" "$?" 127
fi
assert_contains "missing binary mentions path" "$(cat "$WORKDIR/err")" "Fork binary is missing"

# Stale cache + exec: refresh must finish while the binary is running.
# A `( curl ) &` in the same session died on exec and left the cache
# forever equal to the pin, so later launches never warned.
printf '%s\n' "$NEWER_REV" >"$WORKDIR/public-SOURCE_REV"
printf '0\n%s\n' "$PIN_REV" >"$PUBLIC_CACHE_FILE"
cat >"$WORKDIR/fake-sleep" <<'EOF'
#!/bin/sh
sleep 1
printf 'fake-sleep\n'
EOF
chmod +x "$WORKDIR/fake-sleep"
_pub_url="file://$(CDPATH= cd -- "$WORKDIR" && pwd)/public-SOURCE_REV"
GROK_FORK_BIN="$WORKDIR/fake-sleep" \
  GROK_FORK_BASE_REV_FILE="$WORKDIR/base-source-rev" \
  GROK_FORK_GIT_DIR="$WORKDIR/src-same" \
  GROK_FORK_SKIP_NETWORK=0 \
  GROK_FORK_SOURCE_REV_URL="$_pub_url" \
  GROK_HOME="$GROK_HOME" \
  GROK_FORK_CHECK_TTL=0 \
  "$LAUNCHER" --version >"$WORKDIR/out" 2>"$WORKDIR/err" || true
_got_rev=$(trim "$(sed -n '2p' "$PUBLIC_CACHE_FILE" 2>/dev/null || true)")
assert_eq "stale-cache fetch survives exec and writes public SOURCE_REV" "$_got_rev" "$NEWER_REV"
if grep -q 'Public grok-build SOURCE_REV' "$WORKDIR/err"; then
  fail "first stale-cache launch does not wait on the network" "$(cat "$WORKDIR/err")"
else
  pass "first stale-cache launch does not wait on the network"
fi

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
