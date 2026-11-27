#!/usr/bin/env bash
set -euo pipefail

lean_bin=${LEAN:-lean}
case "$lean_bin" in
    /*) ;;
    */*) lean_bin="$PWD/$lean_bin" ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source_dir=Sources/LeanParser
lean_prefix=$(cd "$source_dir" && "$lean_bin" --print-prefix)
version=$(cd "$source_dir" && "$lean_bin" --version)
toolchain=$(<"$source_dir/lean-toolchain")
if [[ "$version" != "Lean (version ${toolchain##*:v},"* ]]; then
    echo "Expected $toolchain, found $version" >&2
    exit 1
fi

lean_lib="$lean_prefix/lib/lean"
case "$(uname -s)" in
    Darwin)
        library=liblean_parser.dylib
        runtime_link=("$lean_lib/libInit.a" "$lean_lib/libleanrt.a" "$lean_prefix/lib/libgmp.a" "$lean_prefix/lib/libuv.a")
        platform_flags=(-dynamiclib -mmacosx-version-min=12.0 '-Wl,-install_name,@rpath/liblean_parser.dylib' -lc++)
        ;;
    Linux)
        library=liblean_parser.so
        runtime_link=(-L "$lean_lib" -lleanshared "-Wl,-rpath,\$ORIGIN")
        platform_flags=(-shared -lstdc++ '-Wl,-z,defs' -lm -ldl -pthread)
        ;;
    *) echo 'The Lean parser build supports macOS and Linux.' >&2; exit 1 ;;
esac

resource_dir=Sources/CompilerCore/LeanParserResources
build_dir=$(mktemp -d "$resource_dir/.build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

(cd "$source_dir" && "$lean_prefix/bin/lake" build)
modules=("$source_dir"/ParserProofs/*.lean "$source_dir"/ParserProofs/Runtime/*.lean)
generated=()
for module in "${modules[@]}"; do
    relative=${module#"$source_dir"/}
    generated+=("$source_dir/.lake/build/ir/${relative%.lean}.c")
done
"${CC:-cc}" -fPIC -O2 -I "$lean_prefix/include" "$source_dir/Bridge.c" "${generated[@]}" \
    "${runtime_link[@]}" "${platform_flags[@]}" -o "$build_dir/$library"
if [[ "$library" == *.so ]]; then
    cp "$lean_lib/libleanshared.so" "$resource_dir/"
fi
cp "$lean_prefix/LICENSE" "$resource_dir/Lean-LICENSE"
cp "$lean_prefix/LICENSES" "$resource_dir/Lean-LICENSES"
mv "$build_dir/$library" "$resource_dir/$library"

fingerprint=$(
    {
        printf '%s\n' "$version" "$lean_prefix" "${CC:-cc}" "$(uname -sm)"
        shasum -a 256 "${modules[@]}" "$source_dir/Bridge.c" Scripts/build_lean.sh
    } | shasum -a 256 | cut -d ' ' -f 1
)
printf 'enum LeanParserBuildIdentity {\n    static let fingerprint = "%s"\n}\n' \
    "$fingerprint" > "$build_dir/LeanParserBuildIdentity.swift"
printf '%s\n' "$fingerprint" > "$build_dir/stamp"
swift_identity=Sources/CompilerCore/Parser/LeanParserBuildIdentity.swift
if ! cmp -s "$build_dir/LeanParserBuildIdentity.swift" "$swift_identity"; then
    mv "$build_dir/LeanParserBuildIdentity.swift" "$swift_identity"
fi
mv "$build_dir/stamp" "$resource_dir/.build-id"
