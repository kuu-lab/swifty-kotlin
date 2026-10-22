# KUU-2041 assertion-status fixture

`commonMain/commonFunctions.kt` and `jvmMain/commonFunctions.kt` are unmodified
files from Kotlin/kotlinx.collections.immutable at commit
`9f961e4dd419dff58ffea164dd41ebba68acc8d6`:

- https://github.com/Kotlin/kotlinx.collections.immutable/blob/9f961e4dd419dff58ffea164dd41ebba68acc8d6/core/commonMain/src/internal/commonFunctions.kt
- https://github.com/Kotlin/kotlinx.collections.immutable/blob/9f961e4dd419dff58ffea164dd41ebba68acc8d6/core/jvmMain/src/internal/commonFunctions.kt

The upstream Apache 2.0 license is included as `LICENSE.txt`.

SHA-256:

- commonMain: `38f3e2f8e50b6790d0152dd13838b2f46ff4b1cd4fe36015c58b3c8d2871a977`
- jvmMain: `76bb81206e3264c54e03fc53e6ff63f6b3b014a3ebc661bafda4170e09a2cff5`

`minimal.kt` preserves the issue's exact reproducer. `Main.kt` is a local test
driver for the original assertion closure, class-literal and captured KClass java
views, typed/star-projected Class values, object javaClass, kotlin.assert, and the
issue's function-expression control. The fixture covers this assertion closure;
it does not establish compatibility for the full immutable module.

Reference (Kotlin/JVM 2.3.10):

```sh
cd Tests/CompilerBackendTests/Fixtures/KUU-2041
kotlinc -Xmulti-platform -Xexpect-actual-classes \
  -Xjdk-release=17 \
  -Xcommon-sources=commonMain/commonFunctions.kt \
  commonMain/commonFunctions.kt jvmMain/commonFunctions.kt Main.kt \
  -include-runtime -d reference.jar
java -ea -jar reference.jar
java -da -jar reference.jar
```

Native defaults to disabled assertions (`java -da` output, KUU-2751). Run with
`KK_ASSERTIONS_ENABLED=1` to compare against `java -ea` output. The backend test
runs both source and fresh artifact routes at O0/O2 with isolated environments.
