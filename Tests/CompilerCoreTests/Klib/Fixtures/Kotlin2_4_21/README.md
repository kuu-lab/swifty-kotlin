# Kotlin/Native 2.4.21 fixture

`basics.klib` is compiled from the three `.kt` files here with the official
Kotlin/Native 2.4.21 compiler for `macos_arm64`. It contains ABI 2.4.0, metadata
2.4.0, and IR signature versions 1 and 2.

The fixture covers dependent defaults, constructor/member/extension defaults,
empty and populated varargs, 31-parameter virtual defaults, explicit super calls, visibility,
generics, cross-file overloaded calls, and lossless UTF-16 string constants.
The Swift tests consume the checked-in binary; Kotlin/Native is not required
to run them.

The 50-line expected output in `KlibLatestBasicsExecutionTests` was also
compared with the official Kotlin/JVM 2.4.21 compiler, using these producer
sources and the consumer embedded in that test. KSwiftK's O0/O2 executions
consume the Native KLIB above.

Regenerate from the repository root:

```sh
KOTLIN_NATIVE_DIR=/path/to/kotlin-native-prebuilt-macos-aarch64-2.4.21
"$KOTLIN_NATIVE_DIR/bin/konanc" -version
"$KOTLIN_NATIVE_DIR/bin/konanc" \
  Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/Basics.kt \
  Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/CrossFile.kt \
  Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/ManyDefaults.kt \
  -produce library -module-name kliblatest \
  -Xklib-relative-path-base=Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21 \
  -o Tests/CompilerCoreTests/Klib/Fixtures/Kotlin2_4_21/basics
```

Compiler distribution: [Kotlin 2.4.21 release](https://github.com/JetBrains/kotlin/releases/tag/v2.4.21).
The downloaded `kotlin-native-prebuilt-macos-aarch64-2.4.21.tar.gz` was checked
against its published SHA-256:
`bf4edb526d91e17d0862102f69250525d788e79011f86c2c64362749adf260ae`.

Fixture SHA-256:
`7f3e2e68455a97f91bad7d555ae8bc397bbbc2dbde24c1557498d6caf30cd562`.
