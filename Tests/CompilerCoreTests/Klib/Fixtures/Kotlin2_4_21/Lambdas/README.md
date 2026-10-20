# Kotlin/Native 2.4.21 lambda fixture

`lambdas.klib` is compiled from `Lambdas.kt` using the official Kotlin/Native
2.4.21 compiler for `macos_arm64` (ABI 2.4.0). It covers non-capturing and
capturing lambdas, nested captures, shared mutable state, receiver capture,
String and generic values, and function-value invocation inside the KLIB.

Regenerate from the repository root:

```sh
KOTLIN_NATIVE_DIR=/path/to/kotlin-native-prebuilt-macos-aarch64-2.4.21
"$KOTLIN_NATIVE_DIR/bin/konanc" \
  Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/Lambdas/Lambdas.kt \
  -produce library -module-name kliblambdas \
  -Xklib-relative-path-base=Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/Lambdas \
  -o Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/Lambdas/lambdas
```

Distribution checksum is recorded in the parent README.
Fixture SHA-256: `b6ffd58b4f7936d196cb1837dff47f257f3c0d41367144a22bf9dfab2872f8c9`.

`KlibLambdaExecutionTests` compiles the same consumer with producer source and
with this Native KLIB at O0 and O2. The expected output is also checked against
Kotlin/JVM 2.4.21.
