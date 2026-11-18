#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PREFLIGHT="$SCRIPT_DIR/benchmark_preflight.py"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-benchmark-preflight-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

write_compiler() {
    local path="$1" mode="$2"
    mkdir -p "$(dirname "$path")"
    cat >"$path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
out=""
while ((\$#)); do
    if [[ "\$1" == "-o" ]]; then out="\$2"; shift 2; else shift; fi
done
case "$mode" in
    ok) printf 'artifact\n' >"\$out" ;;
    empty) : >"\$out" ;;
    no-output) exit 0 ;;
    fail) echo 'fake compile failure' >&2; exit 1 ;;
esac
EOF
    chmod +x "$path"
}

run_preflight() {
    python3 "$PREFLIGHT" "$@"
}

expect_failure() {
    local needle="$1"
    shift
    local output status=0
    output="$(run_preflight "$@" 2>&1)" || status=$?
    if [[ "$status" -eq 0 ]]; then
        echo "expected preflight failure containing: $needle" >&2
        echo "$output" >&2
        exit 1
    fi
    if [[ "$output" != *"$needle"* ]]; then
        echo "expected failure to mention '$needle', got:" >&2
        echo "$output" >&2
        exit 1
    fi
}

# Accepted pair: two debug-built compilers with successful non-empty KIR output.
write_compiler "$TEST_DIR/valid/base/debug/kswiftc" ok
write_compiler "$TEST_DIR/valid/candidate/debug/kswiftc" ok
run_preflight \
    --base-compiler "$TEST_DIR/valid/base/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/valid/candidate/debug/kswiftc" \
    --emit kir >/"$TEST_DIR/valid.stdout"
grep -q 'benchmark preflight passed: config=debug emit=kir' "$TEST_DIR/valid.stdout"

# Rejected pair: inferred debug vs release build configs.
write_compiler "$TEST_DIR/mismatch/base/debug/kswiftc" ok
write_compiler "$TEST_DIR/mismatch/candidate/release/kswiftc" ok
expect_failure 'build config mismatch' \
    --base-compiler "$TEST_DIR/mismatch/base/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/mismatch/candidate/release/kswiftc" \
    --emit kir

# Rejected pair: declared configs disagree even when paths do not reveal them.
write_compiler "$TEST_DIR/declared/base/kswiftc" ok
write_compiler "$TEST_DIR/declared/candidate/kswiftc" ok
expect_failure 'build config mismatch' \
    --base-compiler "$TEST_DIR/declared/base/kswiftc" \
    --candidate-compiler "$TEST_DIR/declared/candidate/kswiftc" \
    --base-build-config debug \
    --candidate-build-config release \
    --emit kir

# Rejected compile: exit 0 with no output must not count as a timing success.
write_compiler "$TEST_DIR/no-output/base/debug/kswiftc" ok
write_compiler "$TEST_DIR/no-output/candidate/debug/kswiftc" no-output
expect_failure 'produced no usable output' \
    --base-compiler "$TEST_DIR/no-output/base/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/no-output/candidate/debug/kswiftc" \
    --emit kir

# Rejected compile: non-zero exit is also not a timing success.
write_compiler "$TEST_DIR/failed/base/debug/kswiftc" ok
write_compiler "$TEST_DIR/failed/candidate/debug/kswiftc" fail
expect_failure 'compile failed with exit 1' \
    --base-compiler "$TEST_DIR/failed/base/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/failed/candidate/debug/kswiftc" \
    --emit kir

# Rejected pair: unverifiable config fails closed.
expect_failure 'build config cannot be verified' \
    --base-compiler "$TEST_DIR/declared/base/kswiftc" \
    --candidate-compiler "$TEST_DIR/declared/candidate/kswiftc" \
    --emit kir

echo 'PASS: benchmark preflight rejects invalid pairs and accepts a valid pair'
