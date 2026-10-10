# kotlin.test executable runner

Compile tests with `kswiftc --test tests.kt more-tests.kt -o tests`, then run
`./tests`. `-generate-test-runner` is an alias. The driver API accepts the
`generate-test-runner` frontend flag. Test mode requires executable emission.
It works with bundled stdlib sources and a prebuilt stdlib `.kklib`.

The compiler resolves `kotlin.test.Test`, `Ignore`, `BeforeTest`, and `AfterTest`
annotations after semantic analysis, including import aliases. An unrelated
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
Tests execute in qualified-name order, with source path and declaration position
as ties. Top-level test names include their file suite.

Each class test gets a fresh instance through an accessible constructor callable
without arguments, including default arguments or a secondary constructor.
Object tests share the singleton. Top-level hooks apply only to their own file.
Before hooks execute in declaration order, with superclass hooks preceding
subclass hooks. A failed before hook stops remaining setup and the test body.
All after hooks are attempted in reverse order, including after a before/test
failure. This cleanup policy extends Native's registration-order cleanup, which
stops at the first cleanup failure. The first failure remains the case's primary
failure; subsequent cleanup failures are reported with an `AFTER` line.
Constructor failure fails the case without running instance hooks.

An ignored class or test prints `SKIP` without constructing the suite or invoking
any hooks. `Ignore` on a hook alone does not remove that hook. Annotated function
signatures are checked even for ignored tests. A test or hook must be a
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
