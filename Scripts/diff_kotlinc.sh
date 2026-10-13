#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Function groups split into sibling helpers by responsibility; resolved
# relative to this script's directory so the entry point works from any cwd.
# shellcheck source=diff_kotlinc_cases.sh
source "$SCRIPT_DIR/diff_kotlinc_cases.sh"
# shellcheck source=diff_kotlinc_toolchain.sh
source "$SCRIPT_DIR/diff_kotlinc_toolchain.sh"
# shellcheck source=diff_kotlinc_artifacts.sh
source "$SCRIPT_DIR/diff_kotlinc_artifacts.sh"
# shellcheck source=diff_kotlinc_candidate_only.sh
source "$SCRIPT_DIR/diff_kotlinc_candidate_only.sh"
# shellcheck source=diff_kotlinc_run_case.sh
source "$SCRIPT_DIR/diff_kotlinc_run_case.sh"

KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
# Space-separated arguments appended to each candidate compiler invocation.
# The shared stdlib artifact intentionally remains at the default optimization
# level so this lane measures optimization of the case under test.
DIFF_KSWIFTC_FLAGS="${DIFF_KSWIFTC_FLAGS:-}"
KSWIFTC_ARGS=()
if [[ -n "$DIFF_KSWIFTC_FLAGS" ]]; then
  read -r -a KSWIFTC_ARGS <<< "$DIFF_KSWIFTC_FLAGS"
fi
KOTLINC="${KOTLINC:-kotlinc}"
KOTLINC_CLASSPATH="${KOTLINC_CLASSPATH:-${KOTLINC_CP:-}}"
JAVA_BIN="${JAVA_BIN:-java}"
KOTLINC_STDLIB_JAR="${KOTLINC_STDLIB_JAR:-}"
KOTLINC_REFLECT_JAR="${KOTLINC_REFLECT_JAR:-}"
KOTLINC_COROUTINES_VERSION="${KOTLINC_COROUTINES_VERSION:-${KOTLINX_COROUTINES_VERSION:-1.10.2}}"
KOTLINC_COROUTINES_SHA256="${KOTLINC_COROUTINES_SHA256:-}"
KOTLINC_DEP_DIR="${KOTLINC_DEP_DIR:-$ROOT_DIR/.runtime-build/deps}"
KOTLINC_COROUTINES_JAR="${KOTLINC_COROUTINES_JAR:-$KOTLINC_DEP_DIR/kotlinx-coroutines-core-jvm-$KOTLINC_COROUTINES_VERSION.jar}"
KOTLINC_KOTLINX_IO_VERSION="${KOTLINC_KOTLINX_IO_VERSION:-${KOTLINX_IO_VERSION:-0.9.1}}"
KOTLINC_KOTLINX_IO_SHA256="${KOTLINC_KOTLINX_IO_SHA256:-}"
KOTLINC_KOTLINX_IO_JAR="${KOTLINC_KOTLINX_IO_JAR:-$KOTLINC_DEP_DIR/kotlinx-io-core-jvm-$KOTLINC_KOTLINX_IO_VERSION.jar}"
KOTLINC_KOTLINX_IO_BYTESTRING_SHA256="${KOTLINC_KOTLINX_IO_BYTESTRING_SHA256:-}"
KOTLINC_KOTLINX_IO_BYTESTRING_JAR="${KOTLINC_KOTLINX_IO_BYTESTRING_JAR:-$KOTLINC_DEP_DIR/kotlinx-io-bytestring-jvm-$KOTLINC_KOTLINX_IO_VERSION.jar}"
KOTLINC_ATOMICFU_VERSION="${KOTLINC_ATOMICFU_VERSION:-0.33.0}"
KOTLINC_ATOMICFU_SHA256="${KOTLINC_ATOMICFU_SHA256:-}"
KOTLINC_ATOMICFU_JAR="${KOTLINC_ATOMICFU_JAR:-$KOTLINC_DEP_DIR/atomicfu-jvm-$KOTLINC_ATOMICFU_VERSION.jar}"
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
# Disable HotSpot perf-data collection for short-lived reference JVMs. Under
# parallel CI load, a locked hsperfdata file can make HotSpot print a warning
# to stdout; that diagnostic is not program output and makes the diff flaky.
DIFF_REFERENCE_JAVA_FLAGS="${DIFF_REFERENCE_JAVA_FLAGS--XX:-UsePerfData}"
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
STDLIB_ARTIFACT=""
FORCE_RUN_SKIPPED=0
CANDIDATE_ONLY=0
EXPECTED_OUTPUT=""
CANDIDATE_ONLY_EXPECTED=0
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
  --candidate-only   Run one candidate-only case without a kotlinc reference
                     (source-only marker or expected-output sidecar)
  --expected-output <path>
                     Expected stdout for candidate-only mode
                     (default: <source-base>.expected)
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
  DIFF_REFERENCE_JAVA_FLAGS
                     JVM options passed to reference java runs (default:
                     -XX:-UsePerfData; set to empty to disable)
  DIFF_STDLIB_LIBRARY
                     Path to an existing KSwiftKStdlib.kklib to reuse; if unset,
                     the runner builds one under DIFF_ARTIFACT_ROOT
  DIFF_KSWIFTC_FLAGS
                     Space-separated arguments appended to the candidate
                     kswiftc invocation (default: empty)
  KOTLINC_ATOMICFU_VERSION / KOTLINC_ATOMICFU_SHA256 / KOTLINC_ATOMICFU_JAR
                     atomicfu-jvm reference dependency (default: pinned 0.33.0);
                     custom versions require an explicit SHA-256

Examples:
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases
  bash Scripts/diff_kotlinc.sh path/to/program.kt
  bash Scripts/diff_kotlinc.sh --candidate-only path/to/program.kt
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
    --candidate-only)
      CANDIDATE_ONLY=1
      ;;
    --expected-output)
      shift
      if [[ $# -eq 0 ]]; then
        echo "--expected-output requires an argument" >&2
        exit 1
      fi
      EXPECTED_OUTPUT="$1"
      ;;
    --expected-output=*)
      EXPECTED_OUTPUT="${1#*=}"
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

# Shared by dependency detection functions. Plain grep
# (POSIX ERE) + find, not rg: this must keep working on hosts/CI jobs without
# ripgrep installed. A missing `rg` here previously made `rg -q` exit
# non-zero for "command not found" the same way it does for "no match", so
# this silently reported "does not need <dependency>" and skipped
# downloading the jar — the reference kotlinc then failed every case for
# that dependency with "unresolved reference 'kotlinx'".
target_matches_import() {
  local target="$1" import_pattern="$2"
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

requires_kotlinx_coroutines() {
  target_matches_import "$1" 'import[[:space:]]+kotlinx\.coroutines'
}

# kotlinx-io-core's package is `kotlinx.io` (not a sub-package of
# kotlinx.coroutines), so this pattern does not overlap with the coroutines
# one above. A case needing both dependencies gets both jars (see
# ensure_kotlinc_classpath).
requires_kotlinx_io() {
  target_matches_import "$1" 'import[[:space:]]+kotlinx\.io'
}

requires_kotlinx_io_bytestring() {
  target_matches_import "$1" 'import[[:space:]]+kotlinx\.io\.bytestring'
}

requires_atomicfu() {
  target_matches_import "$1" '^[[:space:]]*import[[:space:]]+kotlinx\.atomicfu\.'
}

# Pin the real Maven artifact; unknown versions need an explicit checksum.
known_atomicfu_sha256() {
  case "$1" in
    0.33.0) printf 'cdc94bfe4f739a0121860e61977d5c1e6a3d53c21f2471493393ba9e900d394e' ;;
    *) printf '' ;;
  esac
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

# Known checksums per kotlinx-io-core version. For other versions, set
# KOTLINC_KOTLINX_IO_SHA256 explicitly — otherwise the download is refused
# rather than silently skipping verification.
known_kotlinx_io_sha256() {
  case "$1" in
    0.9.1) printf '765d8851d8ca694706931331b92386844800867e041b720f1f193dbda874d370' ;;
    *) printf '' ;;
  esac
}

known_kotlinx_io_bytestring_sha256() {
  case "$1" in
    0.9.1) printf '8589de0b7c476bfdd02a24641685f609ade72f5e595cf2909c168acdba7e6ba4' ;;
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

# Downloads and checksum-verifies a single jar from Maven Central into
# $jar_path, unless it is already present. $known_sha256_fn is the name of a
# `known_*_sha256 <version>` function (known_coroutines_sha256,
# known_kotlinx_io_sha256, ...) consulted when $override_sha256 is empty.
ensure_maven_jar() {
  local dep_label="$1" maven_path="$2" version="$3" jar_path="$4" override_sha256="$5" known_sha256_fn="$6"

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download $dep_label dependency" >&2
    return 1
  fi

  mkdir -p "$KOTLINC_DEP_DIR"

  local expected_sha256="$override_sha256"
  if [[ -z "$expected_sha256" ]]; then
    expected_sha256="$("$known_sha256_fn" "$version")"
  fi
  if [[ -z "$expected_sha256" ]]; then
    echo "No known checksum for $dep_label ${version}." >&2
    echo "Set the corresponding *_SHA256 override to the expected SHA-256 of the jar." >&2
    return 1
  fi

  if [[ ! -s "$jar_path" ]]; then
    local download_url
    local downloaded=false
    # Hosted runners can intermittently receive HTTP 403 from one Maven
    # Central hostname. Retry transient failures and try the alternate
    # canonical hostname before giving up, then verify the checksum below.
    local download_urls=(
      "https://repo.maven.apache.org/maven2/${maven_path}"
      "https://repo1.maven.org/maven2/${maven_path}"
    )
    for download_url in "${download_urls[@]}"; do
      echo "Downloading $dep_label ${version} from ${download_url}..."
      rm -f "$jar_path"
      if curl -fSL --retry 3 --retry-delay 2 --retry-max-time 120 \
        --connect-timeout 30 --max-time 120 \
        -o "$jar_path" "$download_url"; then
        downloaded=true
        break
      fi
      echo "Download failed from ${download_url}; trying the next Maven Central hostname." >&2
    done
    if [[ "$downloaded" != true ]]; then
      echo "Failed to download $dep_label ${version} from Maven Central." >&2
      return 1
    fi
  fi

  local actual_sha256
  if ! actual_sha256="$(sha256_file "$jar_path")"; then
    echo "Error: unable to verify checksum for $dep_label-${version}.jar" >&2
    echo "Install shasum or sha256sum and ensure the cached jar is readable." >&2
    return 1
  fi
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Error: checksum mismatch for $dep_label-${version}.jar" >&2
    echo "Expected: $expected_sha256" >&2
    echo "Actual:   $actual_sha256" >&2
    rm -f "$jar_path"
    return 1
  fi
}

ensure_coroutines_jar() {
  ensure_maven_jar \
    "kotlinx-coroutines-core-jvm" \
    "org/jetbrains/kotlinx/kotlinx-coroutines-core-jvm/${KOTLINC_COROUTINES_VERSION}/kotlinx-coroutines-core-jvm-${KOTLINC_COROUTINES_VERSION}.jar" \
    "$KOTLINC_COROUTINES_VERSION" "$KOTLINC_COROUTINES_JAR" "$KOTLINC_COROUTINES_SHA256" known_coroutines_sha256
}

ensure_kotlinx_io_jar() {
  ensure_maven_jar \
    "kotlinx-io-core-jvm" \
    "org/jetbrains/kotlinx/kotlinx-io-core-jvm/${KOTLINC_KOTLINX_IO_VERSION}/kotlinx-io-core-jvm-${KOTLINC_KOTLINX_IO_VERSION}.jar" \
    "$KOTLINC_KOTLINX_IO_VERSION" "$KOTLINC_KOTLINX_IO_JAR" "$KOTLINC_KOTLINX_IO_SHA256" known_kotlinx_io_sha256
}

ensure_kotlinx_io_bytestring_jar() {
  ensure_maven_jar \
    "kotlinx-io-bytestring-jvm" \
    "org/jetbrains/kotlinx/kotlinx-io-bytestring-jvm/${KOTLINC_KOTLINX_IO_VERSION}/kotlinx-io-bytestring-jvm-${KOTLINC_KOTLINX_IO_VERSION}.jar" \
    "$KOTLINC_KOTLINX_IO_VERSION" "$KOTLINC_KOTLINX_IO_BYTESTRING_JAR" "$KOTLINC_KOTLINX_IO_BYTESTRING_SHA256" known_kotlinx_io_bytestring_sha256
}

ensure_atomicfu_jar() {
  ensure_maven_jar \
    "atomicfu-jvm" \
    "org/jetbrains/kotlinx/atomicfu-jvm/${KOTLINC_ATOMICFU_VERSION}/atomicfu-jvm-${KOTLINC_ATOMICFU_VERSION}.jar" \
    "$KOTLINC_ATOMICFU_VERSION" "$KOTLINC_ATOMICFU_JAR" "$KOTLINC_ATOMICFU_SHA256" known_atomicfu_sha256
}

ensure_kotlinc_classpath() {
  if [[ -n "$KOTLINC_CLASSPATH" ]]; then
    return 0
  fi

  local jars=()

  if requires_kotlinx_coroutines "$TARGET"; then
    ensure_coroutines_jar || return 1
    jars+=("$KOTLINC_COROUTINES_JAR")
  fi

  if requires_kotlinx_io "$TARGET"; then
    ensure_kotlinx_io_jar || return 1
    jars+=("$KOTLINC_KOTLINX_IO_JAR")
  fi

  if requires_kotlinx_io_bytestring "$TARGET"; then
    ensure_kotlinx_io_bytestring_jar || return 1
    jars+=("$KOTLINC_KOTLINX_IO_BYTESTRING_JAR")
  fi

  if requires_atomicfu "$TARGET"; then
    ensure_atomicfu_jar || return 1
    jars+=("$KOTLINC_ATOMICFU_JAR")
  fi

  if [[ ${#jars[@]} -eq 0 ]]; then
    return 0
  fi

  local joined="" jar
  for jar in "${jars[@]}"; do
    if [[ -z "$joined" ]]; then
      joined="$jar"
    else
      joined="$joined:$jar"
    fi
  done
  KOTLINC_CLASSPATH="$joined"
}

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

if [[ "$CANDIDATE_ONLY" -eq 0 && -f "$TARGET" ]] \
  && is_pr_candidate_only_case "$TARGET" \
  && [[ "$(candidate_expected_stdout_directive_count "$TARGET")" -eq 0 ]]; then
  CANDIDATE_ONLY=1
fi

if [[ "$CANDIDATE_ONLY" -eq 1 ]]; then
  if [[ ! -f "$TARGET" || "$TARGET" != *.kt ]]; then
    echo "--candidate-only requires one .kt case file: $TARGET" >&2
    exit 1
  fi
  if is_candidate_only_from_source_case "$TARGET"; then
    if [[ -n "$DIFF_STDLIB_LIBRARY" ]]; then
      echo "--candidate-only source cases compile bundled stdlib sources and cannot use --stdlib-library." >&2
      exit 1
    fi
    if [[ -n "$EXPECTED_OUTPUT" ]]; then
      echo "--expected-output cannot be used with // DIFF_CANDIDATE_ONLY_FROM_SOURCE." >&2
      exit 1
    fi
  else
    CANDIDATE_ONLY_EXPECTED=1
    if [[ -z "$EXPECTED_OUTPUT" ]]; then
      if grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$TARGET"; then
        EXPECTED_OUTPUT="$(candidate_only_expected_output_file "$TARGET")" || {
          echo "Invalid DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT in $TARGET" >&2
          exit 1
        }
      else
        EXPECTED_OUTPUT="${TARGET%.kt}.expected"
      fi
    fi
    if [[ ! -f "$EXPECTED_OUTPUT" ]]; then
      echo "--candidate-only requires an existing expected-output file: $EXPECTED_OUTPUT" >&2
      exit 1
    fi
  fi
elif [[ -n "$EXPECTED_OUTPUT" ]]; then
  echo "--expected-output can only be used with --candidate-only" >&2
  exit 1
fi

if [[ $CLEAN_RUNTIME_CACHE -eq 1 ]]; then
  rm -rf "$ROOT_DIR/.runtime-build"
fi

# A single candidate-only target has no JVM reference by design. Delegate
# before kotlinc/JDK discovery, cache fingerprinting, and JVM warm-up so this
# path remains usable without any reference toolchain installed.
if [[ -f "$TARGET" ]] && is_master_candidate_only_case "$TARGET"; then
  export KSWIFTC DIFF_KSWIFTC_FLAGS
  export DIFF_COMPILE_TIMEOUT="$COMPILE_TIMEOUT"
  export DIFF_RUN_TIMEOUT="$RUN_TIMEOUT"
  export DIFF_ARTIFACT_ROOT="$ARTIFACT_ROOT"
  export DIFF_STDLIB_LIBRARY
  export DIFF_CANDIDATE_ONLY_KEEP_TEMP="$KEEP_TEMP"
  export TIMEOUT="$TIMEOUT_CMD"
  exec bash "$SCRIPT_DIR/run_candidate_only.sh" "$TARGET"
fi

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

if [[ ! -f "$TARGET" && ! -d "$TARGET" ]]; then
  echo "Target does not exist: $TARGET" >&2
  exit 1
fi

# Discover which toolchains and artifacts this shard needs before touching
# kotlinc or Java. Source-only and expected-output candidate cases have no JVM
# reference; canonical sidecar cases belong to run_candidate_only.sh.
REFERENCE_CASES_REQUIRED=0
STDLIB_ARTIFACT_REQUIRED=0
CANDIDATE_EXPECTED_OUTPUT_REQUIRED=0
while IFS= read -r test_case; do
  [[ -z "$test_case" ]] && continue
  if is_master_candidate_only_case "$test_case" || should_skip_diff_case "$test_case" "$FORCE_RUN_SKIPPED" || is_candidate_only_from_source_case "$test_case"; then
    continue
  fi
  if [[ "$CANDIDATE_ONLY_EXPECTED" -eq 1 ]] || is_pr_candidate_only_case "$test_case"; then
    CANDIDATE_EXPECTED_OUTPUT_REQUIRED=1
    STDLIB_ARTIFACT_REQUIRED=1
    continue
  fi
  if grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$test_case"; then
    CANDIDATE_EXPECTED_OUTPUT_REQUIRED=1
    STDLIB_ARTIFACT_REQUIRED=1
    continue
  fi
  REFERENCE_CASES_REQUIRED=1
  STDLIB_ARTIFACT_REQUIRED=1
  break
done < <(collect_cases "$TARGET")

if [[ "$REFERENCE_CASES_REQUIRED" -eq 1 ]]; then
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
fi

if [[ "$REFERENCE_CASES_REQUIRED" -eq 0 ]]; then
  if [[ ! -x "$KSWIFTC" ]] && ! command -v "$KSWIFTC" >/dev/null 2>&1; then
    echo "kswiftc not found or not executable: $KSWIFTC" >&2
    exit 1
  fi
  if ! command -v "$TIMEOUT_CMD" >/dev/null 2>&1; then
    echo "timeout command not found: $TIMEOUT_CMD (on macOS: brew install coreutils, or set TIMEOUT)" >&2
    exit 1
  fi
else
  if [[ -n "$KOTLINC_CLASSPATH" ]] && ! command -v unzip >/dev/null 2>&1; then
    echo "unzip command not found: unzip" >&2
    exit 1
  fi

  # The reference outputs depend on the JDK version: Double/Float.toString()
  # only emits the shortest round-trip form from JDK 19 onwards (JDK-4511638).
  # Older JDKs print extra digits (e.g. 1.23456792E8 instead of 1.2345679E8),
  # which produces spurious FAILs against kswiftc. CI pins java-version 21.
  require_diff_tooling "$KSWIFTC" "$KOTLINC" "$JAVA_BIN" "$TIMEOUT_CMD" "$DIFF_REQUIRE_JDK21" "diff gate" \
    "CI uses JDK 21; older JDKs format Double/Float.toString() differently and cause false FAILs."
fi

if [[ "$REFERENCE_CASES_REQUIRED" -eq 1 ]]; then
  configure_kotlinc_ref_cache
fi

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

echo "=== diff_kotlinc Configuration ==="
echo "Workers: $WORKER_COUNT"
if (( DIFF_SHARD_COUNT > 1 )); then
  echo "Shard: $DIFF_SHARD_INDEX/$DIFF_SHARD_COUNT (interleaved)"
fi
echo "Compile timeout: ${COMPILE_TIMEOUT}s"
echo "Run timeout: ${RUN_TIMEOUT}s"
echo "Script timeout: ${SCRIPT_TIMEOUT}s"
echo "Force run skipped: $FORCE_RUN_SKIPPED"
echo "Candidate-only: $CANDIDATE_ONLY"
echo "kswiftc flags: ${DIFF_KSWIFTC_FLAGS:-<none>}"
echo "Clean runtime cache: $CLEAN_RUNTIME_CACHE"
if [[ -n "$KOTLINC_REF_CACHE_FINGERPRINT" ]]; then
  echo "Kotlinc reference cache: $KOTLINC_REF_CACHE_DIR"
else
  echo "Kotlinc reference cache: disabled"
fi
echo "Kotlinc JAVA_OPTS: ${JAVA_OPTS:-}"
echo "Reference JAVA_FLAGS: ${DIFF_REFERENCE_JAVA_FLAGS:-<empty>}"
if [[ "$CANDIDATE_EXPECTED_OUTPUT_REQUIRED" -eq 1 ]]; then
  echo "Comparison mode: candidate-only expected output"
fi
if [[ -n "$DIFF_STDLIB_LIBRARY" ]]; then
  echo "Stdlib artifact: $DIFF_STDLIB_LIBRARY (provided)"
elif [[ "$STDLIB_ARTIFACT_REQUIRED" -eq 1 ]]; then
  echo "Stdlib artifact: pending build under $ARTIFACT_ROOT"
else
  echo "Stdlib artifact: not needed for skipped candidate-only cases"
fi
echo "Target: $TARGET"
echo "=================================="

# Warm up the JVM/daemon once so per-case compile timeouts measure compilation,
# not the first kotlinc startup cost. Candidate-only targets do not invoke the
# reference compiler or JVM at all.
if [[ "$REFERENCE_CASES_REQUIRED" -eq 1 ]]; then
  warm_kotlinc
fi

if [[ "$STDLIB_ARTIFACT_REQUIRED" -eq 1 ]]; then
  # Build or resolve the precompiled stdlib artifact once per shard. Each candidate
  # compile below will reference it with --stdlib-library instead of recompiling
  # bundled stdlib sources.
  build_stdlib_artifact || exit 1
  echo "Stdlib artifact: $STDLIB_ARTIFACT"
  echo "Stdlib artifact manifest hash: $(stdlib_manifest_hash "$STDLIB_ARTIFACT")"
fi

if [[ "$CANDIDATE_ONLY" -eq 1 ]]; then
  TOTAL=1
  FAILED=0
  echo "CASE 1: $TARGET"
  status="PASS"
  if ! run_case "$TARGET"; then
    FAILED=1
    status="FAIL"
  fi
  if [[ -n "$REPORT_PATH" ]]; then
    printf '%s\t%s\t%s\n' "$TARGET" "$status" "$LAST_ARTIFACT_DIR" >>"$REPORT_PATH"
  fi
  echo "Summary: total=$TOTAL failed=$FAILED passed=$((TOTAL - FAILED)) skipped=0"
  exit "$FAILED"
fi

TOTAL=0
FAILED=0
SKIPPED=0
if [[ "$DIFF_PARALLEL" -eq 0 || "$WORKER_COUNT" -le 1 ]]; then
  while IFS= read -r test_case; do
    [[ -z "$test_case" ]] && continue
    if is_master_candidate_only_case "$test_case"; then
      echo "SKIP $test_case (candidate-only; run Scripts/run_candidate_only.sh)"
      SKIPPED=$((SKIPPED + 1))
      if [[ -n "$REPORT_PATH" ]]; then
        printf '%s\tSKIP\t\n' "$test_case" >>"$REPORT_PATH"
      fi
      continue
    fi
    if should_skip_regular_diff_case "$test_case"; then
      print_skipped_case "$test_case"
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
    if is_master_candidate_only_case "$test_case"; then
      CASE_KIND[$i]="CANDIDATE-ONLY"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if should_skip_regular_diff_case "$test_case"; then
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
    if [[ "${CASE_KIND[$i]:-}" == "SKIP" || "${CASE_KIND[$i]:-}" == "CANDIDATE-ONLY" ]]; then
      if [[ "${CASE_KIND[$i]:-}" == "CANDIDATE-ONLY" ]]; then
        echo "SKIP $test_case (candidate-only; run Scripts/run_candidate_only.sh)"
      else
        print_skipped_case "$test_case"
      fi
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
