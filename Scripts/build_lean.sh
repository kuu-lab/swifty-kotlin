#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
lean_bin=${LEAN:-lean}
lean_prefix=$("$lean_bin" --print-prefix)
version=$("$lean_bin" --version)
toolchain=$(<Sources/LeanParser/lean-toolchain)
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

source_dir=Sources/LeanParser
resource_dir=Sources/CompilerCore/LeanParserResources
build_dir=$(mktemp -d "$resource_dir/.build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

(cd "$source_dir" && "$lean_prefix/bin/lake" build)
generated=()
while IFS= read -r -d '' module; do
    relative=${module#"$source_dir"/}
    generated+=("$source_dir/.lake/build/ir/${relative%.lean}.c")
done < <(find "$source_dir/ParserProofs" -name '*.lean' -type f -print0)
"${CC:-cc}" -fPIC -O2 -I "$lean_prefix/include" "$source_dir/Bridge.c" "${generated[@]}" \
    "${runtime_link[@]}" "${platform_flags[@]}" -o "$build_dir/$library"
if [[ "$library" == *.so ]]; then
    cp "$lean_lib/libleanshared.so" "$resource_dir/"
fi
cp "$lean_prefix/LICENSE" "$resource_dir/Lean-LICENSE"
cp "$lean_prefix/LICENSES" "$resource_dir/Lean-LICENSES"
mv "$build_dir/$library" "$resource_dir/$library"
