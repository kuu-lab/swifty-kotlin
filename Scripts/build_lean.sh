#!/usr/bin/env bash
set -euo pipefail
unset CDPATH

if command -v sha256sum >/dev/null 2>&1; then
    hash=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    hash=(shasum -a 256)
else
    echo 'error: Install sha256sum or shasum to build and verify the Lean parser.' >&2
    exit 1
fi

lean_bin=${LEAN:-lean}
case "$lean_bin" in
    /*) ;;
    */*) lean_bin="$PWD/$lean_bin" ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source_dir=Sources/LeanParser
case "$(uname -s)" in
    Darwin)
        library=liblean_parser.dylib
        libraries=("$library")
        platform_flags=(-dynamiclib -mmacosx-version-min=12.0 '-Wl,-install_name,@rpath/liblean_parser.dylib' -lc++)
        ;;
    Linux)
        library=liblean_parser.so
        libraries=("$library" libleanshared.so)
        platform_flags=(-shared -lstdc++ '-Wl,-z,defs' -lm -ldl -pthread)
        ;;
    *) echo 'The Lean parser build supports macOS and Linux.' >&2; exit 1 ;;
esac

resource_dir=Sources/CompilerCore/LeanParserResources
fingerprint_file="$resource_dir/.lean-parser-fingerprint"
build_id="$resource_dir/.build-id"
swift_identity=Sources/CompilerCore/Parser/LeanParserBuildIdentity.swift

swift_identity_source() {
    printf 'enum LeanParserBuildIdentity {\n    static let fingerprint = "%s"\n}\n' "$1"
}

source_fingerprint() {
    {
        uname -sm
        "${hash[@]}" Scripts/build_lean.sh "$source_dir/Bridge.c" "$source_dir/lakefile.toml" \
            "$source_dir/lake-manifest.json" "$source_dir/lean-toolchain" || return
        find "$source_dir/ParserProofs" -type f -name '*.lean' | LC_ALL=C sort |
            while IFS= read -r module; do "${hash[@]}" "$module" || exit 1; done
    } | "${hash[@]}" | cut -d ' ' -f 1
}

library_fingerprints() (
    cd "$1" && "${hash[@]}" "${libraries[@]}"
)

if [[ ${1:-} == --verify ]]; then
    for artifact in "${libraries[@]}"; do
        if [[ ! -s "$resource_dir/$artifact" ]]; then
            echo "error: Missing Lean parser resource $resource_dir/$artifact. Run bash Scripts/build_lean.sh." >&2
            exit 1
        fi
    done
    current_sources=$(source_fingerprint)
    current_libraries=$(library_fingerprints "$resource_dir")
    if [[ ! -s "$fingerprint_file" || $(<"$fingerprint_file") != "$current_sources"$'\n'"$current_libraries" ]]; then
        echo 'error: Stale Lean parser resources. Run bash Scripts/build_lean.sh to regenerate them.' >&2
        exit 1
    fi
    current_id=$("${hash[@]}" < "$fingerprint_file" | cut -d ' ' -f 1)
    if [[ ! -s "$build_id" || $(<"$build_id") != "$current_id" ||
          ! -s "$swift_identity" || $(<"$swift_identity") != "$(swift_identity_source "$current_id")" ]]; then
        echo 'error: Stale Lean parser build identity. Run bash Scripts/build_lean.sh.' >&2
        exit 1
    fi
    exit 0
fi

lean_prefix=$(cd "$source_dir" && "$lean_bin" --print-prefix)
version=$(cd "$source_dir" && "$lean_bin" --version)
toolchain=$(<"$source_dir/lean-toolchain")
if [[ "$version" != "Lean (version ${toolchain##*:v},"* ]]; then
    echo "Expected $toolchain, found $version" >&2
    exit 1
fi

lean_lib="$lean_prefix/lib/lean"
if [[ "$library" == *.dylib ]]; then
    runtime_link=("$lean_lib/libInit.a" "$lean_lib/libleanrt.a" "$lean_prefix/lib/libgmp.a" "$lean_prefix/lib/libuv.a")
else
    runtime_link=(-L "$lean_lib" -lleanshared "-Wl,-rpath,\$ORIGIN")
fi

compiled_sources=$(source_fingerprint)
build_dir=$(mktemp -d "$resource_dir/.build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

(cd "$source_dir" && "$lean_prefix/bin/lake" build)
generated=()
for module in "$source_dir"/ParserProofs/*.lean "$source_dir"/ParserProofs/Runtime/*.lean; do
    relative=${module#"$source_dir"/}
    generated+=("$source_dir/.lake/build/ir/${relative%.lean}.c")
done
"${CC:-cc}" -fPIC -O2 -I "$lean_prefix/include" "$source_dir/Bridge.c" "${generated[@]}" \
    "${runtime_link[@]}" "${platform_flags[@]}" -o "$build_dir/$library"
if [[ "$library" == *.so ]]; then
    cp "$lean_lib/libleanshared.so" "$build_dir/"
fi
cp "$lean_prefix/LICENSE" "$resource_dir/Lean-LICENSE"
cp "$lean_prefix/LICENSES" "$resource_dir/Lean-LICENSES"
if [[ $(source_fingerprint) != "$compiled_sources" ]]; then
    echo 'Lean parser sources changed during the build. Run bash Scripts/build_lean.sh again.' >&2
    exit 1
fi
{
    printf '%s\n' "$compiled_sources"
    library_fingerprints "$build_dir"
} > "$build_dir/fingerprint"
compiled_id=$("${hash[@]}" < "$build_dir/fingerprint" | cut -d ' ' -f 1)
for artifact in "${libraries[@]}"; do
    mv "$build_dir/$artifact" "$resource_dir/$artifact"
done
printf '%s\n' "$compiled_id" > "$build_dir/build-id"
swift_identity_source "$compiled_id" > "$build_dir/LeanParserBuildIdentity.swift"
if ! cmp -s "$build_dir/LeanParserBuildIdentity.swift" "$swift_identity"; then
    mv "$build_dir/LeanParserBuildIdentity.swift" "$swift_identity"
fi
mv "$build_dir/build-id" "$build_id"
mv "$build_dir/fingerprint" "$fingerprint_file"
