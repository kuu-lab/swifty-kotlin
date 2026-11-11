# Kotlin/Native 2.4.21 vararg spread fixture

`varargspread.klib` was compiled from `VarargSpread.kt` with the official
Kotlin/Native 2.4.21 compiler for `macos_arm64` (ABI 2.4.0).
The library serializes `SPREAD_ELEMENT` inside `VARARG` expressions for
`IntArray` and reference arrays.

Regenerate from the repository root.

```sh
KOTLIN_NATIVE_DIR=/path/to/kotlin-native-prebuilt-macos-aarch64-2.4.21
fixture=Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/VarargSpread
"$KOTLIN_NATIVE_DIR/bin/konanc" "$fixture/VarargSpread.kt" \
  -produce library -module-name klibvarargspread \
  -Xklib-relative-path-base="$fixture" -o "$fixture/varargspread"
```

The compiler distribution checksum is in the [parent README](../README.md).
The fixture SHA-256 is `fd7b5d58b01d00a70381c3dd2fba484d9ddfa197db66fef67a9e5ec8f2117f1b`.

`KlibVarargSpreadExecutionTests` links `Consumer.kt` against the fixture at O0
and O2. The expected output comes from compiling both Kotlin files with
Kotlin/JVM 2.4.21.
