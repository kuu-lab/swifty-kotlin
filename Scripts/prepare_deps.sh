#!/usr/bin/env bash
set -euo pipefail

# Scripts/prepare_deps.sh - diff_kotlinc実行に必要な依存関係を事前準備するスクリプト

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEP_DIR="$ROOT_DIR/.runtime-build/deps"
KOTLINC_COROUTINES_VERSION="1.10.2"
KOTLINC_COROUTINES_JAR="$DEP_DIR/kotlinx-coroutines-core-jvm-$KOTLINC_COROUTINES_VERSION.jar"

echo "=== Preparing dependencies for diff_kotlinc ==="

# ディレクトリ作成
mkdir -p "$DEP_DIR"

# kotlinx-coroutinesのダウンロードと検証
download_coroutines() {
    if [[ -f "$KOTLINC_COROUTINES_JAR" && -s "$KOTLINC_COROUTINES_JAR" ]]; then
        echo "kotlinx-coroutines-core-jvm $KOTLINC_COROUTINES_VERSION already exists."
        return 0
    fi
    
    echo "Downloading kotlinx-coroutines-core-jvm $KOTLINC_COROUTINES_VERSION..."
    
    local download_url
    download_url="https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/${KOTLINC_COROUTINES_VERSION}/kotlinx-coroutines-core-jvm-${KOTLINC_COROUTINES_VERSION}.jar"
    
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required to download dependencies" >&2
        return 1
    fi
    
    # ダウンロード
    curl -fSL -o "$KOTLINC_COROUTINES_JAR" "$download_url"
    
    # SHA256チェックサム検証
    local expected_sha256="5ca175b38df331fd64155b35cd8cae1251fa9ee369709b36d42e0a288ccce3fd"
    local actual_sha256
    if command -v shasum >/dev/null 2>&1; then
        actual_sha256="$(shasum -a 256 "$KOTLINC_COROUTINES_JAR" | awk '{print $1}')"
    elif command -v sha256sum >/dev/null 2>&1; then
        actual_sha256="$(sha256sum "$KOTLINC_COROUTINES_JAR" | awk '{print $1}')"
    else
        echo "Warning: shasum or sha256sum not found, skipping checksum verification" >&2
        actual_sha256="$expected_sha256"
    fi
    
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        echo "Error: checksum mismatch for kotlinx-coroutines-core-jvm-${KOTLINC_COROUTINES_VERSION}.jar" >&2
        echo "Expected: $expected_sha256" >&2
        echo "Actual:   $actual_sha256" >&2
        rm -f "$KOTLINC_COROUTINES_JAR"
        return 1
    fi
    
    echo "✓ kotlinx-coroutines-core-jvm $KOTLINC_COROUTINES_VERSION downloaded and verified."
}

# kswiftcバイナリの存在確認
check_kswiftc() {
    local kswiftc_path="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
    
    if [[ -x "$kswiftc_path" ]]; then
        echo "✓ kswiftc found: $kswiftc_path"
    else
        echo "⚠ kswiftc not found or not executable: $kswiftc_path"
        echo "  Run 'swift build' to build kswiftc."
        return 1
    fi
}

# kotlincコマンドの存在確認
check_kotlinc() {
    local kotlinc_cmd="${KOTLINC:-kotlinc}"
    
    if command -v "$kotlinc_cmd" >/dev/null 2>&1; then
        echo "✓ kotlinc found: $(command -v "$kotlinc_cmd")"
    else
        echo "⚠ kotlinc command not found: $kotlinc_cmd"
        echo "  Install Kotlin compiler or set KOTLINC environment variable."
        return 1
    fi
}

# javaコマンドの存在確認
check_java() {
    local java_cmd="${JAVA_BIN:-java}"
    
    if command -v "$java_cmd" >/dev/null 2>&1; then
        echo "✓ java found: $(command -v "$java_cmd")"
    else
        echo "⚠ java command not found: $java_cmd"
        echo "  Install Java or set JAVA_BIN environment variable."
        return 1
    fi
}

# メイン処理
main() {
    echo "Dependency directory: $DEP_DIR"
    echo ""
    
    # 依存関係の準備
    download_coroutines
    check_kswiftc
    check_kotlinc
    check_java
    
    echo ""
    echo "=== Preparation complete ==="
    echo "You can now run diff_kotlinc with optimized settings:"
    echo "  bash Scripts/diff_kotlinc_fast.sh Scripts/diff_cases"
    echo ""
    echo "Or with custom settings:"
    echo "  DIFF_WORKERS=8 DIFF_COMPILE_TIMEOUT=30 DIFF_RUN_TIMEOUT=10 bash Scripts/diff_kotlinc.sh Scripts/diff_cases"
}

# ヘルプ表示
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $(basename "$0")

Prepare dependencies for diff_kotlinc execution:

This script:
- Downloads and verifies kotlinx-coroutines-core-jvm JAR
- Checks for required tools (kswiftc, kotlinc, java)
- Creates necessary directories

Run this script once before using diff_kotlinc for the first time,
or when dependencies need to be updated.

EOF
    exit 0
fi

main "$@"
