# kotlin.test executable runner

Compile tests with `kswiftc --test tests.kt more-tests.kt -o tests`, then run
`./tests`. `-generate-test-runner` is an alias. The driver API accepts the
`generate-test-runner` frontend flag. Test mode requires executable emission.
It works with bundled stdlib sources and a prebuilt stdlib `.kklib`.

The compiler resolves `kotlin.test.Test`, `Ignore`, `BeforeTest`, `AfterTest`,
`BeforeClass`, and `AfterClass` annotations after semantic analysis, including import aliases. An unrelated
annotation named `Test` does not register a test. Discovery covers the specified
user source files; bundled stdlib and imported libraries are not test suites.
It collects top-level functions by file, concrete classes (including tests and
hooks inherited from user-source superclasses), and singleton objects. Abstract
classes contribute inherited tests without becoming standalone suites. Interface
annotations do not contribute tests, as in Kotlin/Native 2.3.10.

The compiler preserves the user's `main` and selects a separate generated entry
point. Wrappers are added to an in-memory copy of each input in its original
lexical scope. Input files are never rewritten, and no generated file is left
beside them. Test compilation disables the incremental cache for those overlays.
Tests within each suite execute in qualified-name order, with source path and
declaration position as ties. Suites execute in the order of their first case
under that ordering, and all cases of a suite run together. Top-level test names
include their file suite.

Each class test gets a fresh instance through an accessible constructor callable
without arguments, including default arguments or a secondary constructor.
Object tests share the singleton. Top-level hooks apply only to their own file.
`BeforeTest` hooks execute in declaration order, with superclass hooks preceding
subclass hooks. A failed before hook stops remaining setup and the test body.
All `AfterTest` hooks are attempted in reverse order, including after a before/test
failure. This cleanup policy extends Native's registration-order cleanup, which
stops at the first cleanup failure. The first failure remains the case's primary
failure; subsequent cleanup failures are reported with an `AFTER` line.
Constructor failure fails the case without running instance hooks.

`BeforeClass` and `AfterClass` run once before and after the suite's cases.
For a class, put these hooks in its companion object; for a singleton, put them
in the object itself. Top-level class hooks apply to the file's top-level tests.
Private hook methods and import aliases work in all three placements. A private or protected
companion object retains its visibility: a generated accessor stays inside its
containing class, and class hooks do not construct a test instance:

```kotlin
import kotlin.test.*

class Example {
    companion object {
        @BeforeClass private fun startSuite() { println("suite starts") }
        @AfterClass private fun finishSuite() { println("suite ends") }
    }
    @BeforeTest fun setUp() { println("test starts") }
    @Test fun first() { assertTrue(true) }
    @Test fun second() { assertTrue(true) }
    @AfterTest fun tearDown() { println("test ends") }
}
```

A superclass's companion hooks are not inherited by subclass suites. Hooks
inherited by an object (including a companion) from user-source classes are
resolved through their overrides, even when the override has no annotation.
Private superclass class hooks and interface annotations are not inherited.
Declared class hooks run in declaration order, followed by inherited hooks in
name order, for both setup and cleanup. `Ignore` on a hook alone has no effect.
A class hook on an ordinary instance method emits `KSWIFTK-TEST-0002` and is not
registered. Signatures are still validated.

These rules follow the Kotlin/Native 2.3.10
[annotation processor](https://github.com/JetBrains/kotlin/blob/v2.3.10/kotlin-native/backend.native/compiler/ir/backend.native/src/org/jetbrains/kotlin/backend/konan/lower/TestProcessor.kt),
[suite implementation](https://github.com/JetBrains/kotlin/blob/v2.3.10/kotlin-native/runtime/src/main/kotlin/kotlin/native/internal/test/TestSuite.kt),
and [runner](https://github.com/JetBrains/kotlin/blob/v2.3.10/kotlin-native/runtime/src/main/kotlin/kotlin/native/internal/test/TestRunner.kt).
Unlike per-test cleanup's recovery policy above, a class-hook exception escapes
and aborts the executable, as in Native. A failing `BeforeClass` prevents the
suite's tests and `AfterClass` from running; a failing `AfterClass` stops the
remaining class cleanup hooks. No final totals are printed after such an abort.
A test-body failure is reported normally and does not prevent `AfterClass`.

An ignored class or test prints `SKIP` without constructing an instance or
invoking per-test hooks. Class hooks are not invoked for an ignored suite, a
suite whose tests are all ignored, or a suite without tests. In a partially
ignored suite, class hooks still surround the complete sequence of cases,
including their `SKIP` reports. For an overridden test, the nearest declaration
carrying `Test` supplies its `Ignore` flag. An explicit `Test` on the override
replaces the inherited flag; `Ignore` alone on an override does not change it.
Annotated function signatures are checked even for ignored tests. A test or hook must be a
non-suspend, non-generic `Unit` function with no value parameters, extension
receiver, or context receivers. Active generic or inner concrete suites, inaccessible
nested suites, and classes without a usable constructor receive a diagnostic at
the original declaration.

Each case prints `PASS`, `FAIL`, or `SKIP`, followed by a total:

```text
PASS examples.MyTests.success
FAIL examples.MyTests.failure: expected message
SKIP examples.MyTests.pending
Tests: 1 passed, 1 failed, 1 skipped
```

Failures include assertion failures and other `Throwable` instances. Later
tests continue after a failure. Failure lines report `Throwable.message`;
tests can use `printStackTrace()` for additional diagnostic output.
The executable exits with status 1 when any case
fails and 0 otherwise, including an empty suite. Names beginning with
`__kswiftk_test_` and package `kswiftk.generated.tests` are reserved in test mode.
