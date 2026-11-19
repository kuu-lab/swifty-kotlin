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
    wasm-ok) if [[ "\$*" == *wasm32-wasi* ]]; then printf 'wasm\n' >"\$out.wasm"; else printf 'artifact\n' >"\$out"; fi ;;
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

# Rejected pair: leaf-most build-config labels win over ambiguous parent names.
write_compiler "$TEST_DIR/ambiguous/release/base/.build/debug/kswiftc" ok
write_compiler "$TEST_DIR/ambiguous/release/candidate/.build/release/kswiftc" ok
expect_failure 'build config mismatch' \
    --base-compiler "$TEST_DIR/ambiguous/release/base/.build/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/ambiguous/release/candidate/.build/release/kswiftc" \
    --emit kir

# Accepted executable probe: the generated source has an entry point.
write_compiler "$TEST_DIR/probe-exe/base/debug/kswiftc" ok
write_compiler "$TEST_DIR/probe-exe/candidate/debug/kswiftc" ok
run_preflight \
    --base-compiler "$TEST_DIR/probe-exe/base/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/probe-exe/candidate/debug/kswiftc" \
    --emit executable \
    --work-dir "$TEST_DIR/probe-executable" >/"$TEST_DIR/probe-executable.stdout"
grep -q 'fun main' "$TEST_DIR/probe-executable/benchmark-preflight.kt"
test -s "$TEST_DIR/probe-executable/base-output"

# Accepted wasm executable: kswiftc appends .wasm to an extensionless -o path.
write_compiler "$TEST_DIR/wasm/base/debug/kswiftc" wasm-ok
write_compiler "$TEST_DIR/wasm/candidate/debug/kswiftc" wasm-ok
run_preflight \
    --base-compiler "$TEST_DIR/wasm/base/debug/kswiftc" \
    --candidate-compiler "$TEST_DIR/wasm/candidate/debug/kswiftc" \
    --emit executable \
    --compiler-arg=--target=wasm32-wasi >/"$TEST_DIR/wasm.stdout"
grep -q 'benchmark preflight passed: config=debug emit=executable' "$TEST_DIR/wasm.stdout"

echo 'PASS: benchmark preflight rejects invalid pairs and accepts valid pairs'
