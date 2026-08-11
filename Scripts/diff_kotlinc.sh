#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
KOTLINC="${KOTLINC:-kotlinc}"
KOTLINC_CLASSPATH="${KOTLINC_CLASSPATH:-${KOTLINC_CP:-}}"
JAVA_BIN="${JAVA_BIN:-java}"
KOTLINC_STDLIB_JAR="${KOTLINC_STDLIB_JAR:-}"
KOTLINC_REFLECT_JAR="${KOTLINC_REFLECT_JAR:-}"
KOTLINC_COROUTINES_VERSION="${KOTLINC_COROUTINES_VERSION:-${KOTLINX_COROUTINES_VERSION:-1.10.2}}"
KOTLINC_COROUTINES_SHA256="${KOTLINC_COROUTINES_SHA256:-}"
KOTLINC_DEP_DIR="${KOTLINC_DEP_DIR:-$ROOT_DIR/.runtime-build/deps}"
KOTLINC_COROUTINES_JAR="${KOTLINC_COROUTINES_JAR:-$KOTLINC_DEP_DIR/kotlinx-coroutines-core-jvm-$KOTLINC_COROUTINES_VERSION.jar}"
# Reference jars are cached across runs by default. Set to empty
# (KOTLINC_REF_CACHE_DIR=) to disable; `${VAR-...}` (no colon) keeps an
# explicitly empty value as "disabled" instead of re-applying the default.
KOTLINC_REF_CACHE_DIR="${KOTLINC_REF_CACHE_DIR-$ROOT_DIR/.runtime-build/kotlinc-ref-cache}"
KOTLINC_REF_CACHE_FINGERPRINT=""
# JVM options prepended to JAVA_OPTS for kotlinc invocations (the kotlinc
# launcher script honors JAVA_OPTS; the plain `java` reference runs do not).
# C1-only JIT (-XX:TieredStopAtLevel=1) cuts ~15-20% off each short-lived
# kotlinc process. Set to empty to disable. Prepended so caller-provided
# JAVA_OPTS flags win on conflict (the JVM uses the last occurrence).
DIFF_KOTLINC_JAVA_OPTS="${DIFF_KOTLINC_JAVA_OPTS--XX:TieredStopAtLevel=1}"
KEEP_TEMP=0
REPORT_PATH=""
DIFF_PARALLEL="${DIFF_PARALLEL:-1}"
DIFF_WORKERS="${DIFF_WORKERS:-}"
# Distributed sharding: run only every Nth case (interleaved) so multiple CI
# runners can split the case set. SHARD_INDEX is 0-based, SHARD_COUNT total.
DIFF_SHARD_INDEX="${DIFF_SHARD_INDEX:-0}"
DIFF_SHARD_COUNT="${DIFF_SHARD_COUNT:-1}"
# Set to 0 in CI to omit "PASS <file>" lines (keeps FAIL/SKIP/CASE and summary).
DIFF_LOG_PASS="${DIFF_LOG_PASS:-1}"
LAST_ARTIFACT_DIR=""
ARTIFACT_ROOT="${DIFF_ARTIFACT_ROOT:-$ROOT_DIR/.artifacts/diff_kotlinc}"
DIFF_STDLIB_LIBRARY="${DIFF_STDLIB_LIBRARY:-}"
FORCE_RUN_SKIPPED=0
CLEAN_RUNTIME_CACHE=0
COMPILE_TIMEOUT="${DIFF_COMPILE_TIMEOUT:-120}"
RUN_TIMEOUT="${DIFF_RUN_TIMEOUT:-10}"
# kotlinc -script bundles JVM startup + compilation + execution into a single
# process, so it belongs on the COMPILE_TIMEOUT scale, not RUN_TIMEOUT (which
# assumes a fast pre-compiled binary). Resolved after arg parsing so it can
# default to the final COMPILE_TIMEOUT (post --compile-timeout override).
SCRIPT_TIMEOUT="${DIFF_SCRIPT_TIMEOUT:-}"
TIMEOUT_CMD="${TIMEOUT:-timeout}"
LLDB_BIN="${LLDB_BIN:-lldb}"
# Set to 0 to skip the JDK >= 21 requirement check (reference outputs differ on
# older JDKs; see the check below).
DIFF_REQUIRE_JDK21="${DIFF_REQUIRE_JDK21:-1}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <file-or-dir>

Options:
  --kswiftc <path>   Path to kswiftc binary (default: .build/debug/kswiftc)
  --kotlinc <path>   Path to kotlinc command (default: kotlinc)
  --kotlinc-classpath <path>
                     Additional classpath for kotlinc and java (default: \$KOTLINC_CLASSPATH)
  --java <path>      Path to java command (default: java)
  --parallel         Enable parallel execution (default)
  --no-parallel      Disable parallel execution (run cases serially)
  --jobs <n>         Number of parallel workers (0 = serial;
                     default: env DIFF_WORKERS, else CPU count)
  --shard-index <n>  0-based shard index for distributed runs (default: \$DIFF_SHARD_INDEX or 0)
  --shard-count <n>  Total number of shards; case i runs when i % count == index
                     (default: \$DIFF_SHARD_COUNT or 1 = no sharding)
  --compile-timeout <seconds>
                     Per-compiler timeout (default: \$DIFF_COMPILE_TIMEOUT or 120)
  --run-timeout <seconds>
                     Per-program timeout (default: \$DIFF_RUN_TIMEOUT or 10)
  --script-timeout <seconds>
                     Timeout for script-style (script_*.kt) reference cases,
                     which bundle kotlinc JVM startup + compile + run into one
                     process (default: \$DIFF_SCRIPT_TIMEOUT, else --compile-timeout)
  --keep-temp        Keep per-test temporary directories
  --report <path>    Write TSV report (case, status, artifact_dir)
  --artifact-root <path>
                     Persist failing case artifacts under this directory
                     (default: \$DIFF_ARTIFACT_ROOT or .artifacts/diff_kotlinc)
  --stdlib-library <path>
                     Use an existing KSwiftKStdlib.kklib instead of building one
  --force-run-skipped
                     Run cases marked with // SKIP-DIFF or // KSWIFTK_DIFF_IGNORE
  --clean-runtime-cache
                     Remove .runtime-build before running diff cases
  -h, --help         Show this help

Environment:
  DIFF_PARALLEL      1 = parallel (default), 0 = serial. Values > 1 are
                     deprecated and treated as DIFF_WORKERS
  DIFF_WORKERS       Number of parallel workers (0 = serial); same as --jobs
  DIFF_LOG_PASS      If 0 or false, omit PASS lines (FAIL/SKIP/CASE unchanged; default: 1)
  DIFF_SHARD_INDEX / DIFF_SHARD_COUNT
                     Run only every Nth case (interleaved) so N runners can split
                     the case set; counts/summary reflect this shard only
  KOTLINC_STDLIB_JAR Path to kotlin-stdlib.jar, put on the classpath instead of
                     using -include-runtime to compile reference cases (default:
                     auto-discovered next to \$KOTLINC; empty disables and falls
                     back to -include-runtime)
  KOTLINC_REFLECT_JAR
                     Same idea as KOTLINC_STDLIB_JAR but for kotlin-reflect.jar,
                     needed by cases that use kotlin.reflect (default:
                     auto-discovered next to \$KOTLINC)
  KOTLINC_TEST_JAR   Same idea as KOTLINC_STDLIB_JAR but for kotlin-test.jar,
                     needed by cases that use kotlin.test (default:
                     auto-discovered next to \$KOTLINC)
  KOTLINC_REF_CACHE_DIR
                     Reuse successful non-script reference jars from this
                     directory (default: .runtime-build/kotlinc-ref-cache;
                     set to empty to disable the cache)
  DIFF_KOTLINC_JAVA_OPTS
                     JVM options prepended to JAVA_OPTS for kotlinc
                     invocations (default: -XX:TieredStopAtLevel=1;
                     set to empty to disable)
  DIFF_STDLIB_LIBRARY
                     Path to an existing KSwiftKStdlib.kklib to reuse; if unset,
                     the runner builds one under DIFF_ARTIFACT_ROOT

Examples:
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases
  bash Scripts/diff_kotlinc.sh path/to/program.kt
  DIFF_SHARD_INDEX=0 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
USAGE
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kswiftc)
      shift
      KSWIFTC="$1"
      ;;
    --kotlinc)
      shift
      KOTLINC="$1"
      ;;
    --kotlinc-classpath)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Missing value for --kotlinc-classpath" >&2
        exit 1
      fi
      KOTLINC_CLASSPATH="$1"
      ;;
    --kotlinc-classpath=*)
      KOTLINC_CLASSPATH="${1#*=}"
      ;;
    --java)
      shift
      JAVA_BIN="$1"
      ;;
    --parallel)
      DIFF_PARALLEL=1
      ;;
    --no-parallel)
      DIFF_PARALLEL=0
      ;;
    --jobs)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--jobs requires an argument" >&2
        exit 1
      fi
      DIFF_WORKERS="$1"
      ;;
    --jobs=*)
      DIFF_WORKERS="${1#*=}"
      ;;
    --shard-index)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--shard-index requires an argument" >&2
        exit 1
      fi
      DIFF_SHARD_INDEX="$1"
      ;;
    --shard-index=*)
      DIFF_SHARD_INDEX="${1#*=}"
      ;;
    --shard-count)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--shard-count requires an argument" >&2
        exit 1
      fi
      DIFF_SHARD_COUNT="$1"
      ;;
    --shard-count=*)
      DIFF_SHARD_COUNT="${1#*=}"
      ;;
    --compile-timeout)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--compile-timeout requires an argument" >&2
        exit 1
      fi
      COMPILE_TIMEOUT="$1"
      ;;
    --run-timeout)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--run-timeout requires an argument" >&2
        exit 1
      fi
      RUN_TIMEOUT="$1"
      ;;
    --script-timeout)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--script-timeout requires an argument" >&2
        exit 1
      fi
      SCRIPT_TIMEOUT="$1"
      ;;
    --keep-temp)
      KEEP_TEMP=1
      ;;
    --report)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--report requires an argument" >&2
        exit 1
      fi
      REPORT_PATH="$1"
      ;;
    --artifact-root)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--artifact-root requires an argument" >&2
        exit 1
      fi
      ARTIFACT_ROOT="$1"
      ;;
    --stdlib-library)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--stdlib-library requires an argument" >&2
        exit 1
      fi
      DIFF_STDLIB_LIBRARY="$1"
      ;;
    --stdlib-library=*)
      DIFF_STDLIB_LIBRARY="${1#*=}"
      ;;
    --force-run-skipped)
      FORCE_RUN_SKIPPED=1
      ;;
    --clean-runtime-cache)
      CLEAN_RUNTIME_CACHE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo "Only one file-or-dir argument is supported." >&2
        exit 1
      fi
      TARGET="$1"
      ;;
  esac
  shift
done

requires_kotlinx_coroutines() {
  local target="$1"
  # Plain grep (POSIX ERE) + find, not rg: this must keep working on hosts/CI
  # jobs without ripgrep installed. A missing `rg` here previously made
  # `rg -q` exit non-zero for "command not found" the same way it does for
  # "no match", so this silently reported "does not need kotlinx.coroutines"
  # and skipped downloading the jar — the reference kotlinc then failed
  # every coroutines diff case with "unresolved reference 'kotlinx'".
  local import_pattern='import[[:space:]]+kotlinx\.coroutines'
  if [[ -f "$target" ]]; then
    grep -Eq "$import_pattern" "$target"
    return $?
  fi
  if [[ -d "$target" ]]; then
    local source_file
    while IFS= read -r -d '' source_file; do
      if grep -Eq "$import_pattern" "$source_file"; then
        return 0
      fi
    done < <(find "$target" -type f -name '*.kt' -print0)
    return 1
  fi
  return 1
}

# Known checksums per kotlinx-coroutines version. For other versions, set
# KOTLINC_COROUTINES_SHA256 explicitly — otherwise the download is refused
# rather than silently skipping verification.
known_coroutines_sha256() {
  case "$1" in
    1.10.2) printf '5ca175b38df331fd64155b35cd8cae1251fa9ee369709b36d42e0a288ccce3fd' ;;
    *) printf '' ;;
  esac
}

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    return 1
  fi
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    return 1
  fi
}

# Resolves a jar next to $KOTLINC (../lib/<name> relative to .../bin/kotlinc,
# the layout CI unzips kotlin-compiler-*.zip into) so run_case() can compile
# with -classpath instead of -include-runtime, avoiding a multi-MB repackage
# into every case's jar (~14% faster compile per case, measured locally).
# Also tries ../libexec/lib/ for Homebrew's kotlin formula, which wraps the
# real distro under libexec/ and defeats readlink -f (bin/kotlinc there is a
# wrapper *script*, not a symlink). Empty/unresolvable leaves
# KOTLINC_CLASSPATH as-is and run_case() falls back to -include-runtime,
# same as before this existed.
#
# Used for kotlin-stdlib.jar, kotlin-reflect.jar, and kotlin-test.jar:
# -include-runtime bundles stdlib/reflect but not kotlin-test, so cases
# importing kotlin.test fail to compile against the reference with a plain
# -include-runtime jar (confirmed via kotlin.test.* unresolved-reference
# failures on kotlin-test-only cases). kotlin.reflect.full/jvm APIs -
# KClass.isAbstract/isOpen, KType.toString(), etc. - throw
# KotlinReflectionNotSupportedError or fall back to plain-Java rendering
# without kotlin-reflect on the classpath; confirmed via CI failures on
# kclass_basic.kt/type_reflection.kt when only kotlin-stdlib.jar was added).
resolve_kotlinc_lib_jar() {
  local jar_name="$1" kotlinc_bin resolved_bin bin_dir candidate
  kotlinc_bin="$(command -v "$KOTLINC" 2>/dev/null || true)"
  [[ -z "$kotlinc_bin" ]] && return 0
  resolved_bin="$(readlink -f "$kotlinc_bin" 2>/dev/null || echo "$kotlinc_bin")"
  bin_dir="$(dirname "$resolved_bin")"
  for candidate in "$bin_dir/../lib/$jar_name" "$bin_dir/../libexec/lib/$jar_name"; do
    if [[ -f "$candidate" ]]; then
      echo "$(cd "$(dirname "$candidate")" && pwd)/$jar_name"
      return 0
    fi
  done
}

ensure_kotlinc_classpath() {
  if [[ -n "$KOTLINC_CLASSPATH" ]]; then
    return 0
  fi

  if ! requires_kotlinx_coroutines "$TARGET"; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download kotlinx-coroutines dependency" >&2
    return 1
  fi

  mkdir -p "$KOTLINC_DEP_DIR"

  local expected_sha256="$KOTLINC_COROUTINES_SHA256"
  if [[ -z "$expected_sha256" ]]; then
    expected_sha256="$(known_coroutines_sha256 "$KOTLINC_COROUTINES_VERSION")"
  fi
  if [[ -z "$expected_sha256" ]]; then
    echo "No known checksum for kotlinx-coroutines-core-jvm ${KOTLINC_COROUTINES_VERSION}." >&2
    echo "Set KOTLINC_COROUTINES_SHA256 to the expected SHA-256 of the jar." >&2
    return 1
  fi

  if [[ ! -s "$KOTLINC_COROUTINES_JAR" ]]; then
    local download_url
    download_url="https://repo1.maven.org/maven2/org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/${KOTLINC_COROUTINES_VERSION}/kotlinx-coroutines-core-jvm-${KOTLINC_COROUTINES_VERSION}.jar"
    echo "Downloading kotlinx-coroutines-core-jvm ${KOTLINC_COROUTINES_VERSION}..."
    curl -fSL -o "$KOTLINC_COROUTINES_JAR" "$download_url"
  fi

  local actual_sha256
  if ! actual_sha256="$(sha256_file "$KOTLINC_COROUTINES_JAR")"; then
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

  KOTLINC_CLASSPATH="$KOTLINC_COROUTINES_JAR"
}

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

if [[ $CLEAN_RUNTIME_CACHE -eq 1 ]]; then
  rm -rf "$ROOT_DIR/.runtime-build"
fi

# Exported before the first kotlinc invocation (configure_kotlinc_ref_cache /
# warm_kotlinc / run_case all inherit it). JIT flags do not affect compiler
# output, so this is deliberately absent from the reference-cache fingerprint.
if [[ -n "$DIFF_KOTLINC_JAVA_OPTS" ]]; then
  export JAVA_OPTS="$DIFF_KOTLINC_JAVA_OPTS${JAVA_OPTS:+ $JAVA_OPTS}"
fi

ensure_kotlinc_classpath

# Runs after ensure_kotlinc_classpath (which may have just populated
# KOTLINC_CLASSPATH with a downloaded coroutines jar) and after arg parsing
# (which may have set KOTLINC/KOTLINC_CLASSPATH via --kotlinc/
# --kotlinc-classpath), so it sees final values for both instead of racing
# either. Prepending here, not at KOTLINC_STDLIB_JAR's declaration above,
# is what keeps a user- or coroutines-supplied classpath intact.
KOTLINC_STDLIB_JAR="${KOTLINC_STDLIB_JAR:-$(resolve_kotlinc_lib_jar kotlin-stdlib.jar || true)}"
KOTLINC_REFLECT_JAR="${KOTLINC_REFLECT_JAR:-$(resolve_kotlinc_lib_jar kotlin-reflect.jar || true)}"
KOTLINC_TEST_JAR="${KOTLINC_TEST_JAR:-$(resolve_kotlinc_lib_jar kotlin-test.jar || true)}"
for runtime_jar in "$KOTLINC_REFLECT_JAR" "$KOTLINC_STDLIB_JAR" "$KOTLINC_TEST_JAR"; do
  if [[ -n "$runtime_jar" ]]; then
    if [[ -n "$KOTLINC_CLASSPATH" ]]; then
      KOTLINC_CLASSPATH="$runtime_jar:$KOTLINC_CLASSPATH"
    else
      KOTLINC_CLASSPATH="$runtime_jar"
    fi
  fi
done

# DIFF_PARALLEL is a boolean toggle: 0 = serial, 1 = parallel (default).
# Worker count comes from DIFF_WORKERS / --jobs. Values >= 2 are deprecated
# and treated as a DIFF_WORKERS fallback for backward compatibility.
if ! [[ "$DIFF_PARALLEL" =~ ^[0-9]+$ ]]; then
  echo "DIFF_PARALLEL must be 0 or 1: $DIFF_PARALLEL" >&2
  exit 1
fi

if (( DIFF_PARALLEL > 1 )); then
  echo "warning: DIFF_PARALLEL=$DIFF_PARALLEL (values > 1) is deprecated; use DIFF_WORKERS=$DIFF_PARALLEL or --jobs $DIFF_PARALLEL instead" >&2
  if [[ -z "$DIFF_WORKERS" ]]; then
    DIFF_WORKERS="$DIFF_PARALLEL"
  fi
  DIFF_PARALLEL=1
fi

if [[ -n "$DIFF_WORKERS" ]] && ! [[ "$DIFF_WORKERS" =~ ^(0|[1-9][0-9]*)$ ]]; then
  echo "DIFF_WORKERS must be a non-negative integer (0 = serial): $DIFF_WORKERS" >&2
  exit 1
fi

# --jobs 0 / DIFF_WORKERS=0 means serial execution.
if [[ "$DIFF_WORKERS" == "0" ]]; then
  DIFF_PARALLEL=0
  DIFF_WORKERS=""
fi

if ! [[ "$DIFF_SHARD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "DIFF_SHARD_COUNT must be a positive integer: $DIFF_SHARD_COUNT" >&2
  exit 1
fi

if ! [[ "$DIFF_SHARD_INDEX" =~ ^(0|[1-9][0-9]*)$ ]]; then
  echo "DIFF_SHARD_INDEX must be a non-negative integer: $DIFF_SHARD_INDEX" >&2
  exit 1
fi

if (( DIFF_SHARD_INDEX >= DIFF_SHARD_COUNT )); then
  echo "DIFF_SHARD_INDEX ($DIFF_SHARD_INDEX) must be < DIFF_SHARD_COUNT ($DIFF_SHARD_COUNT)" >&2
  exit 1
fi

if ! [[ "$COMPILE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "compile timeout must be a positive integer: $COMPILE_TIMEOUT" >&2
  exit 1
fi

if ! [[ "$RUN_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "run timeout must be a positive integer: $RUN_TIMEOUT" >&2
  exit 1
fi

# Default to the (possibly --compile-timeout-overridden) COMPILE_TIMEOUT, since
# script mode's dominant cost is JVM startup + compilation, not execution.
SCRIPT_TIMEOUT="${SCRIPT_TIMEOUT:-$COMPILE_TIMEOUT}"

if ! [[ "$SCRIPT_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "script timeout must be a positive integer: $SCRIPT_TIMEOUT" >&2
  exit 1
fi

if [[ -n "$REPORT_PATH" ]]; then
  : >"$REPORT_PATH"
fi

if ! [[ -x "$KSWIFTC" ]]; then
  echo "kswiftc not found or not executable: $KSWIFTC" >&2
  exit 1
fi

if ! command -v "$KOTLINC" >/dev/null 2>&1; then
  echo "kotlinc command not found: $KOTLINC" >&2
  exit 1
fi

if ! command -v "$JAVA_BIN" >/dev/null 2>&1; then
  echo "java command not found: $JAVA_BIN" >&2
  exit 1
fi

# The reference outputs depend on the JDK version: Double/Float.toString()
# only emits the shortest round-trip form from JDK 19 onwards (JDK-4511638).
# Older JDKs print extra digits (e.g. 1.23456792E8 instead of 1.2345679E8),
# which produces spurious FAILs against kswiftc. CI pins java-version 21.
java_major="$("$JAVA_BIN" -version 2>&1 \
  | awk -F'"' '/version/ { print $2; exit }' \
  | awk -F'[.]' '{ print ($1 == "1") ? $2 : $1 }')"
if [[ "$DIFF_REQUIRE_JDK21" != "0" ]]; then
  if [[ ! "$java_major" =~ ^[0-9]+$ ]] || (( java_major < 21 )); then
    echo "java is too old for the diff gate: $JAVA_BIN reports major version '${java_major:-unknown}', need >= 21." >&2
    echo "CI uses JDK 21; older JDKs format Double/Float.toString() differently and cause false FAILs." >&2
    echo "Set JAVA_BIN/JAVA_HOME to a JDK 21+, or DIFF_REQUIRE_JDK21=0 to bypass." >&2
    exit 1
  fi
fi

if [[ -n "$KOTLINC_CLASSPATH" ]] && ! command -v unzip >/dev/null 2>&1; then
  echo "unzip command not found: unzip" >&2
  exit 1
fi

if ! command -v "$TIMEOUT_CMD" >/dev/null 2>&1; then
  echo "timeout command not found: $TIMEOUT_CMD (on macOS: brew install coreutils, or set TIMEOUT)" >&2
  exit 1
fi

warm_kotlinc() {
  local warm_timeout
  warm_timeout=$(( COMPILE_TIMEOUT > 10 ? COMPILE_TIMEOUT : 10 ))
  "$TIMEOUT_CMD" "$warm_timeout" "$KOTLINC" -version >/dev/null 2>&1 || true
}

jar_main_class() {
  local jar_path="$1"
  unzip -p "$jar_path" META-INF/MANIFEST.MF 2>/dev/null \
    | tr -d '\r' \
    | awk -F': ' '/^Main-Class:/ { print $2; exit }'
}

fingerprint_kotlinc_classpath() {
  local -a classpath_entries=()
  local entry entry_index=0 classpath_file relative_path file_hash

  IFS=':' read -r -a classpath_entries <<<"$KOTLINC_CLASSPATH"
  {
    for entry in "${classpath_entries[@]}"; do
      printf 'entry:%s\n' "$entry_index"
      entry_index=$((entry_index + 1))
      if [[ -f "$entry" ]]; then
        file_hash="$(sha256_file "$entry")" || return 1
        printf 'file:%s:%s\n' "$(basename "$entry")" "$file_hash"
      elif [[ -d "$entry" ]]; then
        while IFS= read -r classpath_file; do
          relative_path="${classpath_file#"$entry"/}"
          file_hash="$(sha256_file "$classpath_file")" || return 1
          printf 'directory-file:%s:%s\n' "$relative_path" "$file_hash"
        done < <(find "$entry" -type f | LC_ALL=C sort)
      else
        printf 'missing:%s\n' "$entry"
      fi
    done
  } | sha256_stream
}

configure_kotlinc_ref_cache() {
  if [[ -z "$KOTLINC_REF_CACHE_DIR" ]]; then
    return 0
  fi

  # Without an external runtime classpath, kotlinc embeds the multi-megabyte
  # runtime in every jar. Do not accidentally turn that fallback into a large
  # persistent cache.
  if [[ -z "$KOTLINC_CLASSPATH" ]]; then
    echo "Warning: disabling kotlinc reference cache because no runtime classpath was resolved." >&2
    KOTLINC_REF_CACHE_DIR=""
    return 0
  fi

  if ! command -v shasum >/dev/null 2>&1 && ! command -v sha256sum >/dev/null 2>&1; then
    echo "Warning: disabling kotlinc reference cache because SHA-256 is unavailable." >&2
    KOTLINC_REF_CACHE_DIR=""
    return 0
  fi

  if ! mkdir -p "$KOTLINC_REF_CACHE_DIR"; then
    echo "Warning: disabling kotlinc reference cache because the directory cannot be created: $KOTLINC_REF_CACHE_DIR" >&2
    KOTLINC_REF_CACHE_DIR=""
    return 0
  fi
  KOTLINC_REF_CACHE_DIR="$(cd "$KOTLINC_REF_CACHE_DIR" && pwd)"

  local compiler_version java_version classpath_fingerprint
  if ! compiler_version="$("$KOTLINC" -version 2>&1)"; then
    echo "Warning: disabling kotlinc reference cache because the compiler version could not be read." >&2
    KOTLINC_REF_CACHE_DIR=""
    return 0
  fi
  java_version="$("$JAVA_BIN" -version 2>&1)"
  if ! classpath_fingerprint="$(fingerprint_kotlinc_classpath)"; then
    echo "Warning: disabling kotlinc reference cache because the classpath could not be fingerprinted." >&2
    KOTLINC_REF_CACHE_DIR=""
    return 0
  fi

  if ! KOTLINC_REF_CACHE_FINGERPRINT="$({
    printf 'format:v1\n'
    printf 'compiler:%s\n' "$compiler_version"
    printf 'classpath:%s\n' "$classpath_fingerprint"
    printf 'java:%s\n' "$java_version"
    printf 'compiler-flags:-Xcontext-parameters\n'
  } | sha256_stream)"; then
    echo "Warning: disabling kotlinc reference cache because its fingerprint could not be computed." >&2
    KOTLINC_REF_CACHE_DIR=""
    return 0
  fi
}

kotlinc_ref_cache_path() {
  local kt_file="$1"
  local kotlinc_extra_flags="$2"
  local source_bytes cache_key
  source_bytes="$(wc -c <"$kt_file" | tr -d '[:space:]')"
  cache_key="$({
    printf 'toolchain:%s\n' "$KOTLINC_REF_CACHE_FINGERPRINT"
    printf 'source-name:%s\n' "$(basename "$kt_file")"
    printf 'extra-flags:%s\n' "$kotlinc_extra_flags"
    printf 'source-bytes:%s\n' "$source_bytes"
    cat "$kt_file"
  } | sha256_stream)" || return 1
  printf '%s/%s.jar\n' "$KOTLINC_REF_CACHE_DIR" "$cache_key"
}

store_kotlinc_ref_cache() {
  local source="$1"
  local destination="$2"
  local temporary

  temporary="$(mktemp "${destination}.tmp.XXXXXX")" || return 0

  if cp "$source" "$temporary"; then
    mv -f "$temporary" "$destination" || rm -f "$temporary"
  else
    rm -f "$temporary"
  fi
}

configure_kotlinc_ref_cache

# Worker count: serial when disabled, else explicit DIFF_WORKERS / --jobs,
# else auto-detected CPU count (fallback 4).
if [[ "$DIFF_PARALLEL" -eq 0 ]]; then
  WORKER_COUNT=1
elif [[ -n "$DIFF_WORKERS" ]]; then
  WORKER_COUNT="$DIFF_WORKERS"
else
  WORKER_COUNT="$(detect_workers)"
  [[ -z "$WORKER_COUNT" ]] && WORKER_COUNT=4
fi

if [[ "$WORKER_COUNT" -lt 1 ]]; then
  WORKER_COUNT=1
fi

# The parallel scheduler below relies on `wait -n` (bash >= 4.3). macOS's
# stock bash 3.2 would fail mid-run, so fall back to serial execution there.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  if [[ "$DIFF_PARALLEL" -ne 0 && "$WORKER_COUNT" -gt 1 ]]; then
    echo "bash $BASH_VERSION lacks 'wait -n'; running serially (install bash >= 4.3 for parallel mode)." >&2
  fi
  WORKER_COUNT=1
fi

stdlib_manifest_hash() {
  local artifact_dir="$1"
  local manifest_path="$artifact_dir/manifest.json"
  if [[ ! -f "$manifest_path" ]]; then
    echo "unknown"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("stdlibManifestHash",""))' "$manifest_path" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

build_stdlib_artifact() {
  if [[ -n "$DIFF_STDLIB_LIBRARY" ]]; then
    if [[ ! -d "$DIFF_STDLIB_LIBRARY" || ! -f "$DIFF_STDLIB_LIBRARY/manifest.json" ]]; then
      echo "Stdlib library does not exist or is missing manifest.json: $DIFF_STDLIB_LIBRARY" >&2
      return 1
    fi
    STDLIB_ARTIFACT="$DIFF_STDLIB_LIBRARY"
    return 0
  fi

  mkdir -p "$ARTIFACT_ROOT"
  STDLIB_ARTIFACT="$ARTIFACT_ROOT/KSwiftKStdlib.kklib"
  local stdlib_build_stdout="$ARTIFACT_ROOT/stdlib_build.stdout"
  local stdlib_build_stderr="$ARTIFACT_ROOT/stdlib_build.stderr"

  echo "Building stdlib artifact: $STDLIB_ARTIFACT"
  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --stdlib-only --emit library -o "$STDLIB_ARTIFACT" \
    >"$stdlib_build_stdout" 2>"$stdlib_build_stderr" || {
      echo "Failed to build stdlib artifact" >&2
      if [[ -s "$stdlib_build_stderr" ]]; then
        cat "$stdlib_build_stderr" >&2
      fi
      return 1
    }

  local stdlib_manifest_hash
  stdlib_manifest_hash="$(stdlib_manifest_hash "$STDLIB_ARTIFACT")"
  echo "Stdlib artifact manifest hash: $stdlib_manifest_hash"
}

echo "=== diff_kotlinc Configuration ==="
echo "Workers: $WORKER_COUNT"
if (( DIFF_SHARD_COUNT > 1 )); then
  echo "Shard: $DIFF_SHARD_INDEX/$DIFF_SHARD_COUNT (interleaved)"
fi
echo "Compile timeout: ${COMPILE_TIMEOUT}s"
echo "Run timeout: ${RUN_TIMEOUT}s"
echo "Script timeout: ${SCRIPT_TIMEOUT}s"
echo "Force run skipped: $FORCE_RUN_SKIPPED"
echo "Clean runtime cache: $CLEAN_RUNTIME_CACHE"
if [[ -n "$KOTLINC_REF_CACHE_FINGERPRINT" ]]; then
  echo "Kotlinc reference cache: $KOTLINC_REF_CACHE_DIR"
else
  echo "Kotlinc reference cache: disabled"
fi
echo "Kotlinc JAVA_OPTS: ${JAVA_OPTS:-}"
if [[ -n "$DIFF_STDLIB_LIBRARY" ]]; then
  echo "Stdlib artifact: $DIFF_STDLIB_LIBRARY (provided)"
else
  echo "Stdlib artifact: pending build under $ARTIFACT_ROOT"
fi
echo "Target: $TARGET"
echo "=================================="

# Warm up the JVM/daemon once so per-case compile timeouts measure compilation,
# not the first kotlinc startup cost.
warm_kotlinc

# Build or resolve the precompiled stdlib artifact once per shard. Each candidate
# compile below will reference it with --stdlib-library instead of recompiling
# bundled stdlib sources.
build_stdlib_artifact || exit 1
echo "Stdlib artifact: $STDLIB_ARTIFACT"
echo "Stdlib artifact manifest hash: $(stdlib_manifest_hash "$STDLIB_ARTIFACT")"

# Emits this shard's cases (interleaved sharding via lib/common.sh;
# DIFF_SHARD_COUNT == 1 emits everything).
collect_cases() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path" | shard_interleave "$DIFF_SHARD_INDEX" "$DIFF_SHARD_COUNT"
  elif [[ -d "$path" ]]; then
    find "$path" -type f -name '*.kt' | sort \
      | shard_interleave "$DIFF_SHARD_INDEX" "$DIFF_SHARD_COUNT"
  else
    echo "Target does not exist: $path" >&2
    exit 1
  fi
}

# Number of cases in the target *before* sharding, so an empty shard can be
# distinguished from a genuinely empty target.
count_target_cases() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '1'
  elif [[ -d "$path" ]]; then
    find "$path" -type f -name '*.kt' | wc -l | tr -d '[:space:]'
  else
    printf '0'
  fi
}

# Decide what an empty case set means. A genuinely empty target is an error, but
# an empty shard (sharding on, with every case assigned to other shards) is a
# normal no-op that must exit 0 so the aggregate gate stays green.
handle_empty_cases() {
  if (( DIFF_SHARD_COUNT > 1 )) && (( $(count_target_cases "$TARGET") > 0 )); then
    echo "No cases assigned to shard ${DIFF_SHARD_INDEX}/${DIFF_SHARD_COUNT}; nothing to do."
    echo "Summary: total=0 failed=0 passed=0 skipped=0"
    exit 0
  fi
  echo "No .kt files found." >&2
  exit 1
}

normalize_text() {
  tr -d '\r'
}

safe_diff_to_file() {
  local left="$1"
  local right="$2"
  local output="$3"
  if [[ ! -f "$left" || ! -f "$right" ]]; then
    rm -f "$output"
    return 0
  fi
  if ! diff -u "$left" "$right" >"$output"; then
    return 0
  fi
  rm -f "$output"
}

save_runtime_backtrace() {
  local candidate_bin="$1"
  local output="$2"

  if ! command -v "$LLDB_BIN" >/dev/null 2>&1; then
    return 0
  fi

  "$LLDB_BIN" -b -o run -o bt -- "$candidate_bin" >"$output" 2>&1 || true
}

persist_artifacts() {
  local case_path="$1"
  local tmp_dir="$2"
  local result_label="$3"
  local ref_compile_exit="$4"
  local cand_compile_exit="$5"
  local ref_run_exit="$6"
  local cand_run_exit="$7"

  mkdir -p "$ARTIFACT_ROOT"

  local case_name
  case_name="$(sanitize_case_name "$case_path")"
  local destination="$ARTIFACT_ROOT/${case_name}"
  local suffix=1
  while [[ -e "$destination" ]]; do
    destination="$ARTIFACT_ROOT/${case_name}_$suffix"
    suffix=$((suffix + 1))
  done

  mv "$tmp_dir" "$destination"

  cp "$case_path" "$destination/input.kt"

  if [[ $cand_compile_exit -eq 0 ]]; then
    "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --no-stdlib --stdlib-library "$STDLIB_ARTIFACT" --emit kir "$case_path" -o "$destination/candidate.kir" \
      >"$destination/candidate_kir.stdout" \
      2>"$destination/candidate_kir.stderr" || true
  fi
  if [[ $cand_compile_exit -eq 0 && $cand_run_exit -ge 128 ]]; then
    save_runtime_backtrace "$destination/candidate.out" "$destination/backtrace.txt"
  fi

  cat >"$destination/summary.txt" <<EOF
case: $case_path
result: $result_label
artifact_dir: $destination
compile_timeout_seconds: $COMPILE_TIMEOUT
run_timeout_seconds: $RUN_TIMEOUT
script_timeout_seconds: $SCRIPT_TIMEOUT
ref_compile_exit: $ref_compile_exit
candidate_compile_exit: $cand_compile_exit
ref_run_exit: $ref_run_exit
candidate_run_exit: $cand_run_exit
stdlib_artifact: $STDLIB_ARTIFACT
stdlib_manifest_hash: $(stdlib_manifest_hash "$STDLIB_ARTIFACT")
kswiftc: $KSWIFTC
kotlinc: $KOTLINC
java: $JAVA_BIN
force_run_skipped: $FORCE_RUN_SKIPPED
clean_runtime_cache: $CLEAN_RUNTIME_CACHE
EOF

  cat >"$destination/repro.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT_DIR"
DIFF_STDLIB_LIBRARY="$STDLIB_ARTIFACT" DIFF_ARTIFACT_ROOT="$ARTIFACT_ROOT" bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped --artifact-root "$ARTIFACT_ROOT" "$case_path"
EOF
  chmod +x "$destination/repro.sh"

  safe_diff_to_file "$destination/ref_compile_stderr.norm" "$destination/cand_compile_stderr.norm" "$destination/compile_stderr.diff"
  safe_diff_to_file "$destination/ref_run_stdout.norm" "$destination/cand_run_stdout.norm" "$destination/stdout.diff"
  safe_diff_to_file "$destination/ref_run.stderr" "$destination/cand_run.stderr" "$destination/stderr.diff"

  LAST_ARTIFACT_DIR="$destination"
}

should_skip_case() {
  local kt_file="$1"
  if [[ $FORCE_RUN_SKIPPED -eq 1 ]]; then
    return 1
  fi
  grep -Eq '^[[:space:]]*//[[:space:]]*(KSWIFTK_DIFF_IGNORE|SKIP-DIFF)\b' "$kt_file"
}

# Cases that need stdin=EOF (e.g. readLine() returning null)
needs_stdin_eof() {
  local kt_file="$1"
  grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_STDIN_EOF\b' "$kt_file"
}

# Extract DIFF_LINE_PATTERN regex for lines that may differ (e.g. object identity hash)
# Format: // DIFF_LINE_PATTERN: <regex>
get_diff_line_pattern() {
  local kt_file="$1"
  grep -E '^[[:space:]]*//[[:space:]]*DIFF_LINE_PATTERN:' "$kt_file" 2>/dev/null | head -1 | sed 's/.*DIFF_LINE_PATTERN:[[:space:]]*//'
}

# Extract extra kotlinc flags from // KOTLINC_FLAGS: directives in the test file
# Format: // KOTLINC_FLAGS: <flags>
get_kotlinc_extra_flags() {
  local kt_file="$1"
  grep -E '^[[:space:]]*//[[:space:]]*KOTLINC_FLAGS:' "$kt_file" 2>/dev/null | sed 's/.*KOTLINC_FLAGS:[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Extract extra JVM flags (e.g. -ea) from // JAVA_FLAGS: directives in the test
# file. These are passed to the `java` invocation that runs the reference jar,
# before -cp/-jar so they are parsed as JVM options rather than program args.
# Format: // JAVA_FLAGS: <flags>
get_java_extra_flags() {
  local kt_file="$1"
  grep -E '^[[:space:]]*//[[:space:]]*JAVA_FLAGS:' "$kt_file" 2>/dev/null | sed 's/.*JAVA_FLAGS:[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Normalize stdout: replace lines matching pattern with placeholder for diff.
# The pattern is passed through the environment (not awk -v) so backslashes in
# the regex are not mangled by awk's escape-sequence processing.
normalize_stdout_for_diff() {
  local file="$1"
  local pattern="$2"
  if [[ -z "$pattern" ]]; then
    cat "$file"
  else
    DIFF_LINE_PATTERN_RE="$pattern" awk '
      $0 ~ ENVIRON["DIFF_LINE_PATTERN_RE"] { print "__DIFF_PATTERN_MATCH__"; next }
      { print }
    ' "$file"
  fi
}

run_case() {
  local kt_file="$1"
  local artifact_file="${2:-}"
  local tmp_dir
  tmp_dir="$(mktemp -d -t kswiftk-diff-XXXXXX)"
  LAST_ARTIFACT_DIR="$tmp_dir"

  local ref_jar="$tmp_dir/ref.jar"
  local ref_compile_stdout="$tmp_dir/ref_compile.stdout"
  local ref_compile_stderr="$tmp_dir/ref_compile.stderr"
  local ref_run_stdout="$tmp_dir/ref_run.stdout"
  local ref_run_stderr="$tmp_dir/ref_run.stderr"

  local cand_bin="$tmp_dir/candidate.out"
  local cand_compile_stdout="$tmp_dir/cand_compile.stdout"
  local cand_compile_stderr="$tmp_dir/cand_compile.stderr"
  local cand_run_stdout="$tmp_dir/cand_run.stdout"
  local cand_run_stderr="$tmp_dir/cand_run.stderr"

  : >"$ref_compile_stdout"
  : >"$ref_compile_stderr"
  : >"$ref_run_stdout"
  : >"$ref_run_stderr"
  : >"$cand_run_stdout"
  : >"$cand_run_stderr"

  local ref_compile_exit=0
  local ref_run_exit=0
  local cand_compile_exit=0
  local cand_run_exit=0

  local basename
  basename="$(basename "$kt_file")"
  local is_script=0
  if [[ "$basename" == script_* ]]; then
    is_script=1
  fi

  local kotlinc_extra_flags
  kotlinc_extra_flags="$(get_kotlinc_extra_flags "$kt_file")"

  local java_extra_flags
  java_extra_flags="$(get_java_extra_flags "$kt_file")"

  if [[ $is_script -eq 1 ]]; then
    local kts_tmp="$tmp_dir/${basename%.kt}.kts"
    cp "$kt_file" "$kts_tmp"
    local script_exit=0
    if [[ -n "$KOTLINC_CLASSPATH" ]]; then
      # shellcheck disable=SC2086
      "$TIMEOUT_CMD" "$SCRIPT_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags -classpath "$KOTLINC_CLASSPATH" -script "$kts_tmp" >"$ref_run_stdout" 2>"$ref_run_stderr" || script_exit=$?
    else
      # shellcheck disable=SC2086
      "$TIMEOUT_CMD" "$SCRIPT_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags -script "$kts_tmp" >"$ref_run_stdout" 2>"$ref_run_stderr" || script_exit=$?
    fi
    if [[ $script_exit -eq 124 ]]; then
      # Timeout in script mode is a runtime timeout, not a compile timeout
      ref_run_exit=124
    elif [[ $script_exit -ne 0 ]] && [[ ! -s "$ref_run_stdout" ]]; then
      ref_compile_exit=$script_exit
    else
      ref_run_exit=$script_exit
    fi
  else
    local cached_ref_jar=""
    local ref_cache_hit=0
    if [[ -n "$KOTLINC_REF_CACHE_FINGERPRINT" ]]; then
      cached_ref_jar="$(kotlinc_ref_cache_path "$kt_file" "$kotlinc_extra_flags")"
      if [[ -s "$cached_ref_jar" ]] && cp "$cached_ref_jar" "$ref_jar"; then
        ref_cache_hit=1
      fi
    fi

    if [[ $ref_cache_hit -eq 0 ]]; then
      if [[ -n "$KOTLINC_CLASSPATH" ]]; then
        # No -include-runtime: KOTLINC_CLASSPATH includes the stdlib/reflect
        # jars (see resolve_kotlinc_lib_jar above) whenever they could be
        # resolved, so the runtime classes needed by ref_run below are
        # already on the classpath without repackaging them into ref_jar.
        # shellcheck disable=SC2086
        "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags -classpath "$KOTLINC_CLASSPATH" "$kt_file" -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
      else
        # shellcheck disable=SC2086
        "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags "$kt_file" -include-runtime -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
      fi
      if [[ $ref_compile_exit -eq 0 && -n "$cached_ref_jar" && -s "$ref_jar" ]]; then
        store_kotlinc_ref_cache "$ref_jar" "$cached_ref_jar"
      fi
    fi
    if [[ $ref_compile_exit -eq 0 ]]; then
      if [[ -n "$KOTLINC_CLASSPATH" ]]; then
        local main_class
        main_class="$(jar_main_class "$ref_jar")"
        if [[ -z "$main_class" ]]; then
          ref_run_exit=1
          echo "Missing Main-Class in reference jar manifest." >"$ref_run_stderr"
        else
          if needs_stdin_eof "$kt_file"; then
            # shellcheck disable=SC2086
            "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $java_extra_flags -cp "$ref_jar:$KOTLINC_CLASSPATH" "$main_class" < /dev/null >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
          else
            # shellcheck disable=SC2086
            "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $java_extra_flags -cp "$ref_jar:$KOTLINC_CLASSPATH" "$main_class" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
          fi
        fi
      else
        if needs_stdin_eof "$kt_file"; then
          # shellcheck disable=SC2086
          "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $java_extra_flags -jar "$ref_jar" < /dev/null >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
        else
          # shellcheck disable=SC2086
          "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $java_extra_flags -jar "$ref_jar" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
        fi
      fi
    fi
  fi

  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --no-stdlib --stdlib-library "$STDLIB_ARTIFACT" "$kt_file" -o "$cand_bin" >"$cand_compile_stdout" 2>"$cand_compile_stderr" || cand_compile_exit=$?
  if [[ $cand_compile_exit -eq 0 ]]; then
    if needs_stdin_eof "$kt_file"; then
      "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$cand_bin" < /dev/null >"$cand_run_stdout" 2>"$cand_run_stderr" || cand_run_exit=$?
    else
      "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$cand_bin" >"$cand_run_stdout" 2>"$cand_run_stderr" || cand_run_exit=$?
    fi
  fi

  normalize_text <"$ref_compile_stderr" >"$tmp_dir/ref_compile_stderr.norm"
  normalize_text <"$cand_compile_stderr" >"$tmp_dir/cand_compile_stderr.norm"
  normalize_text <"$ref_run_stdout" >"$tmp_dir/ref_run_stdout.norm" || true
  normalize_text <"$cand_run_stdout" >"$tmp_dir/cand_run_stdout.norm" || true
  normalize_text <"$ref_run_stderr" >"$tmp_dir/ref_run_stderr.norm" || true
  normalize_text <"$cand_run_stderr" >"$tmp_dir/cand_run_stderr.norm" || true

  local ok=1

  if [[ $ref_compile_exit -ne $cand_compile_exit ]]; then
    ok=0
    echo "  compile exit mismatch: ref=$ref_compile_exit candidate=$cand_compile_exit"
  fi
  if [[ $ref_compile_exit -eq 124 ]]; then
    ok=0
    echo "  ref compile timed out after ${COMPILE_TIMEOUT}s"
  fi
  if [[ $cand_compile_exit -eq 124 ]]; then
    ok=0
    echo "  candidate compile timed out after ${COMPILE_TIMEOUT}s"
  fi

  # Matching non-zero compile exits short-circuit the run/stdout comparison
  # below, so this "passes" without either side ever executing. The match is
  # necessary but not sufficient evidence of equivalent behavior — both
  # compilers reject their own input for possibly unrelated reasons (stderr is
  # not diffed). Flag it so a green run isn't mistaken for verified parity.
  if [[ $ref_compile_exit -ne 0 && $ref_compile_exit -eq $cand_compile_exit && $ref_compile_exit -ne 124 ]]; then
    echo "  note: both sides failed to compile with exit=$ref_compile_exit; matching exit codes do not imply matching failure reasons (stderr is not diffed) — this PASS is inconclusive, not verified parity"
  fi

  if [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
    if [[ $ref_run_exit -ne $cand_run_exit ]]; then
      ok=0
      echo "  run exit mismatch: ref=$ref_run_exit candidate=$cand_run_exit"
    fi
    if [[ $ref_run_exit -eq 124 ]]; then
      ok=0
      if [[ $is_script -eq 1 ]]; then
        echo "  ref script (compile+run) timed out after ${SCRIPT_TIMEOUT}s"
      else
        echo "  ref run timed out after ${RUN_TIMEOUT}s"
      fi
    fi
    if [[ $cand_run_exit -eq 124 ]]; then
      ok=0
      echo "  candidate run timed out after ${RUN_TIMEOUT}s"
    fi
    line_pattern=$(get_diff_line_pattern "$kt_file")
    if [[ -n "$line_pattern" ]]; then
      normalize_stdout_for_diff "$tmp_dir/ref_run_stdout.norm" "$line_pattern" > "$tmp_dir/ref_run_stdout.pat"
      normalize_stdout_for_diff "$tmp_dir/cand_run_stdout.norm" "$line_pattern" > "$tmp_dir/cand_run_stdout.pat"
      if ! diff -u "$tmp_dir/ref_run_stdout.pat" "$tmp_dir/cand_run_stdout.pat" >/dev/null; then
        ok=0
        echo "  stdout mismatch:"
        diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" || true
      fi
    else
      if ! diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" >/dev/null; then
        ok=0
        echo "  stdout mismatch:"
        diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" || true
      fi
    fi
  elif [[ $ref_compile_exit -ne 0 && $cand_compile_exit -ne 0 && $ref_compile_exit -eq $cand_compile_exit ]]; then
    # Matching non-zero exit codes do not imply the same failure reason: ref
    # and candidate may be erroring out for entirely unrelated causes. Treat
    # this as unverified rather than silently passing (compile stderr for
    # both sides is included in the FAIL output/artifacts below).
    ok=0
    echo "  both compile failed with exit=$ref_compile_exit (matching exit code alone does not verify parity; compile stderr not compared)"
  fi

  if [[ $ok -eq 1 ]]; then
    if [[ "$DIFF_LOG_PASS" != "0" && "$DIFF_LOG_PASS" != "false" ]]; then
      echo "PASS $kt_file"
    fi
  else
    echo "FAIL $kt_file"
    echo "  ref compile stderr:"
    sed -n '1,120p' "$tmp_dir/ref_compile_stderr.norm"
    echo "  candidate compile stderr:"
    sed -n '1,120p' "$tmp_dir/cand_compile_stderr.norm"
    if [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
      echo "  ref run stderr:"
      sed -n '1,120p' "$ref_run_stderr"
      echo "  candidate run stderr:"
      sed -n '1,120p' "$cand_run_stderr"
    fi
  fi

  if [[ $ok -eq 0 ]]; then
    persist_artifacts \
      "$kt_file" \
      "$tmp_dir" \
      "FAIL" \
      "$ref_compile_exit" \
      "$cand_compile_exit" \
      "$ref_run_exit" \
      "$cand_run_exit"
    echo "  artifacts: $LAST_ARTIFACT_DIR"
  elif [[ $KEEP_TEMP -eq 0 ]]; then
    rm -rf "$tmp_dir"
    LAST_ARTIFACT_DIR=""
  else
    echo "  artifacts: $tmp_dir"
  fi

  if [[ -n "$artifact_file" ]]; then
    printf '%s\n' "$LAST_ARTIFACT_DIR" >"$artifact_file"
  fi

  return $((1 - ok))
}

run_case_worker() {
  local kt_file="$1"
  local log_path="$2"
  local status_path="$3"
  local artifact_file="$4"

  local case_exit=0
  local status="PASS"
  local artifact=""

  run_case "$kt_file" "$artifact_file" >"$log_path" 2>&1 || case_exit=$?

  if [[ $case_exit -ne 0 ]]; then
    status="FAIL"
  fi

  artifact="$(cat "$artifact_file" 2>/dev/null || true)"
  printf '%s\t%s\n' "$status" "$artifact" >"$status_path"
}

TOTAL=0
FAILED=0
SKIPPED=0
if [[ "$DIFF_PARALLEL" -eq 0 || "$WORKER_COUNT" -le 1 ]]; then
  while IFS= read -r test_case; do
    [[ -z "$test_case" ]] && continue
    if should_skip_case "$test_case"; then
      echo "SKIP $test_case (// SKIP-DIFF)"
      SKIPPED=$((SKIPPED + 1))
      if [[ -n "$REPORT_PATH" ]]; then
        printf '%s\tSKIP\t\n' "$test_case" >>"$REPORT_PATH"
      fi
      continue
    fi
    TOTAL=$((TOTAL + 1))
    echo "CASE $TOTAL: $test_case"
    status="PASS"
    if ! run_case "$test_case"; then
      FAILED=$((FAILED + 1))
      status="FAIL"
    fi
    if [[ -n "$REPORT_PATH" ]]; then
      printf '%s\t%s\t%s\n' "$test_case" "$status" "$LAST_ARTIFACT_DIR" >>"$REPORT_PATH"
    fi
  done < <(collect_cases "$TARGET")
else
  declare -a TEST_CASES=()
  declare -a CASE_KIND=()
  declare -a CASE_NUM=()
  declare -a RUN_INPUT_INDEXES=()
  while IFS= read -r test_case; do
    [[ -z "$test_case" ]] && continue
    TEST_CASES+=("$test_case")
  done < <(collect_cases "$TARGET")

  if [[ ${#TEST_CASES[@]} -eq 0 ]]; then
    handle_empty_cases
  fi
  for i in "${!TEST_CASES[@]}"; do
    test_case="${TEST_CASES[$i]}"
    if should_skip_case "$test_case"; then
      CASE_KIND[$i]="SKIP"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    TOTAL=$((TOTAL + 1))
    CASE_KIND[$i]="RUN"
    CASE_NUM[$i]="$TOTAL"
    RUN_INPUT_INDEXES+=("$i")
  done

  RUN_DIR="$(mktemp -d -t kswiftk-diff-run-XXXXXX)"
  declare -a RUNNING_PIDS=()

  if (( ${#RUN_INPUT_INDEXES[@]} > 0 )); then
    for input_index in "${RUN_INPUT_INDEXES[@]}"; do
      test_case="${TEST_CASES[$input_index]}"
      log_path="$RUN_DIR/case_${input_index}.log"
      status_path="$RUN_DIR/case_${input_index}.status"
      artifact_path="$RUN_DIR/case_${input_index}.artifact"

      run_case_worker "$test_case" "$log_path" "$status_path" "$artifact_path" &
      RUNNING_PIDS+=("$!")

      if (( ${#RUNNING_PIDS[@]} >= WORKER_COUNT )); then
        wait -n
        NEW_PIDS=()
        for pid in "${RUNNING_PIDS[@]}"; do
          if kill -0 "$pid" 2>/dev/null; then
            NEW_PIDS+=("$pid")
          fi
        done
        RUNNING_PIDS=("${NEW_PIDS[@]}")
      fi
    done

    wait
  fi

  for i in "${!TEST_CASES[@]}"; do
    test_case="${TEST_CASES[$i]}"
    if [[ "${CASE_KIND[$i]:-}" == "SKIP" ]]; then
      echo "SKIP $test_case (// SKIP-DIFF)"
      if [[ -n "$REPORT_PATH" ]]; then
        printf '%s\tSKIP\t\n' "$test_case" >>"$REPORT_PATH"
      fi
      continue
    fi
    case_number="${CASE_NUM[$i]:-0}"
    log_path="$RUN_DIR/case_${i}.log"
    status_path="$RUN_DIR/case_${i}.status"
    status="FAIL"
    artifact_dir=""

    if [[ -f "$status_path" ]]; then
      IFS=$'\t' read -r status artifact_dir < "$status_path" || true
    fi

    if [[ "$status" != "PASS" && "$status" != "FAIL" ]]; then
      status="FAIL"
    fi

    echo "CASE $case_number: $test_case"
    if [[ -f "$log_path" ]]; then
      cat "$log_path"
    else
      echo "FAIL $test_case"
      echo "  parallel worker output missing: $log_path"
      status="FAIL"
    fi

    if [[ "$status" == "FAIL" ]]; then
      FAILED=$((FAILED + 1))
    fi

    if [[ -n "$REPORT_PATH" ]]; then
      printf '%s\t%s\t%s\n' "$test_case" "$status" "$artifact_dir" >>"$REPORT_PATH"
    fi
  done

  rm -rf "$RUN_DIR"
fi

if [[ $TOTAL -eq 0 && $SKIPPED -eq 0 ]]; then
  handle_empty_cases
fi

echo "Summary: total=$TOTAL failed=$FAILED passed=$((TOTAL - FAILED)) skipped=$SKIPPED"
if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
