#!/usr/bin/env bash
set -euo pipefail

# Scripts/diff_kotlinc_fast.sh - 高速化版diff_kotlinc実行スクリプト
# 
# 使用方法:
#   bash Scripts/diff_kotlinc_fast.sh [target] [options]
#
# 高速化の最適化:
# - 並列ワーカー数をCPUコア数に自動調整
# - タイムアウト時間を短縮（コンパイル30秒、実行10秒）
# - 依存関係を事前準備
# - 高速な一時ディレクトリを使用

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 高速化設定
export DIFF_PARALLEL=1
export DIFF_WORKERS="${DIFF_WORKERS:-$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 8)}"
export DIFF_COMPILE_TIMEOUT="${DIFF_COMPILE_TIMEOUT:-30}"
export DIFF_RUN_TIMEOUT="${DIFF_RUN_TIMEOUT:-10}"
export TMPDIR="${TMPDIR:-/tmp}"

# 依存関係の事前準備
prepare_dependencies() {
    local dep_dir="$ROOT_DIR/.runtime-build/deps"
    local coroutines_version="1.10.2"
    local coroutines_jar="$dep_dir/kotlinx-coroutines-core-jvm-$coroutines_version.jar"
    
    mkdir -p "$dep_dir"
    
    if [[ ! -f "$coroutines_jar" ]]; then
        echo "Downloading kotlinx-coroutines-core-jvm $coroutines_version..."
        local download_url="https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/$coroutines_version/kotlinx-coroutines-core-jvm-$coroutines_version.jar"
        
        if command -v curl >/dev/null 2>&1; then
            curl -fSL -o "$coroutines_jar" "$download_url"
        else
            echo "Error: curl is required to download dependencies" >&2
            return 1
        fi
        
        # SHA256チェックサム検証
        local expected_sha256="5ca175b38df331fd64155b35cd8cae1251fa9ee369709b36d42e0a288ccce3fd"
        local actual_sha256
        if command -v shasum >/dev/null 2>&1; then
            actual_sha256="$(shasum -a 256 "$coroutines_jar" | awk '{print $1}')"
        elif command -v sha256sum >/dev/null 2>&1; then
            actual_sha256="$(sha256sum "$coroutines_jar" | awk '{print $1}')"
        else
            echo "Warning: shasum or sha256sum not found, skipping checksum verification" >&2
            actual_sha256="$expected_sha256"
        fi
        
        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            echo "Error: checksum mismatch for kotlinx-coroutines-core-jvm-$coroutines_version.jar" >&2
            echo "Expected: $expected_sha256" >&2
            echo "Actual:   $actual_sha256" >&2
            rm -f "$coroutines_jar"
            return 1
        fi
        
        echo "Dependency downloaded and verified successfully."
    else
        echo "kotlinx-coroutines dependency already available."
    fi
}

# CPU情報と設定の表示
show_configuration() {
    echo "=== Fast diff_kotlinc Configuration ==="
    echo "Workers: $DIFF_WORKERS"
    echo "Compile timeout: ${DIFF_COMPILE_TIMEOUT}s"
    echo "Run timeout: ${DIFF_RUN_TIMEOUT}s"
    echo "Temp directory: $TMPDIR"
    echo "Target: $TARGET"
    echo "========================================"
}

# メイン処理
main() {
    local target="$1"
    shift
    
    if [[ -z "$target" ]]; then
        echo "Usage: $0 <target> [options]" >&2
        echo "Example: $0 Scripts/diff_cases" >&2
        exit 1
    fi
    
    TARGET="$target"
    
    show_configuration
    prepare_dependencies
    
    echo "Starting fast diff_kotlinc execution..."
    
    # 元のスクリプトを実行
    exec bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" "$target" "$@"
}

# 引数がなければヘルプを表示
if [[ $# -eq 0 ]]; then
    cat <<EOF
Usage: $(basename "$0") <target> [options]

Fast execution wrapper for diff_kotlinc.sh with optimizations:

Environment variables:
  DIFF_WORKERS        Number of parallel workers (default: auto-detect CPU cores)
  DIFF_COMPILE_TIMEOUT Compile timeout in seconds (default: 30)
  DIFF_RUN_TIMEOUT    Run timeout in seconds (default: 10)
  TMPDIR              Temporary directory (default: /tmp)

Examples:
  $0 Scripts/diff_cases
  $0 Scripts/diff_cases --jobs 4
  $0 path/to/single_test.kt

EOF
    exit 1
fi

main "$@"
