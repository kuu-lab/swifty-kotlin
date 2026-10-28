# Kotlin/Native 2.4.21 increment/decrement fixture

`incdec.klib` is compiled from `IncDec.kt` using the official Kotlin/Native
2.4.21 compiler for `macos_arm64` (ABI 2.4.0). Its functions apply `++`/`--`
to Byte, Short, UByte, UShort, Char, Int, Double and Float locals, which the
KLIB serializes as `inc()`/`dec()` calls lowered by `KlibBodyLowerer`.

Regenerate from the repository root:

```sh
KOTLIN_NATIVE_DIR=/path/to/kotlin-native-prebuilt-macos-aarch64-2.4.21
"$KOTLIN_NATIVE_DIR/bin/konanc" \
  Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/IncDec/IncDec.kt \
  -produce library -module-name klibincdec \
  -Xklib-relative-path-base=Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/IncDec \
  -o Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/IncDec/incdec
```

Distribution checksum is recorded in the parent README.
Fixture SHA-256: `b18f440c2309152dab4fba36795c96c5204bf16cf83eab5f3902c86b72a005d9`.

`KlibIncDecExecutionTests` compiles the same consumer with producer source and
with this Native KLIB at O0 and O2. The expected output is also checked against
Kotlin/JVM 2.4.21.
