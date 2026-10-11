# kotlinc/JDK setup helpers for Scripts/diff_kotlinc.sh: JVM warm-up, reference-jar
# caching, and the shared stdlib artifact build.
# Sourced by diff_kotlinc.sh (split for readability); not executed directly.

[[ -n "${_KSWIFTK_DIFF_KOTLINC_TOOLCHAIN_SH:-}" ]] && return 0
_KSWIFTK_DIFF_KOTLINC_TOOLCHAIN_SH=1

_DIFF_KOTLINC_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_DIFF_KOTLINC_HELPER_DIR/lib/common.sh"

warm_kotlinc() {
  local warm_timeout
  warm_timeout=$(( COMPILE_TIMEOUT > 10 ? COMPILE_TIMEOUT : 10 ))
  "$TIMEOUT_CMD" "$warm_timeout" "$KOTLINC" -version >/dev/null 2>&1 || true
}

jar_main_class() {
  local jar_path="$1"
  unzip -p "$jar_path" META-INF/MANIFEST.MF 2>/dev/null \
    | tr -d '\r' \
    | awk '
      function emit_main_class() {
        if (reading_main_class && !emitted_main_class) {
          print main_class
          emitted_main_class = 1
        }
      }
      /^Main-Class: / {
        emit_main_class()
        main_class = substr($0, 13)
        reading_main_class = 1
        next
      }
      reading_main_class && /^ / {
        main_class = main_class substr($0, 2)
        next
      }
      reading_main_class {
        emit_main_class()
        reading_main_class = 0
      }
      END { emit_main_class() }
    '
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
