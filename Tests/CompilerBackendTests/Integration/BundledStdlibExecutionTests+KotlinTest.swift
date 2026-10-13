import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKotlinTestAnnotations(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.test.Test
            import kotlin.test.Ignore
            import kotlin.test.BeforeTest
            import kotlin.test.AfterTest
            import kotlin.test.ExperimentalKotlinTestApi

            class Example {
                @BeforeTest fun setUp() { println("before") }
                @Test fun test() { println("test") }
                @AfterTest fun tearDown() { println("after") }
                @Ignore @Test fun ignored() { println("ignored") }
            }
            @Ignore class IgnoredSuite

            @ExperimentalKotlinTestApi
            fun experimental() { println("opted in") }

            @OptIn(ExperimentalKotlinTestApi::class)
            fun main() {
                val example = Example()
                example.setUp()
                example.test()
                example.tearDown()
                experimental()
            }
            """,
            expectedOutput: "before\ntest\nafter\nopted in\n",
            moduleName: "KUU1693KotlinTestAnnotations",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKotlinTestAsserter(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("kotlin_test_asserter.kt", file: #filePath),
            expectedOutput: """
            true
            true
            0
            lazy failure
            1
            false value
            Expected <1>, actual <2>.
            numbers. Expected <1>, actual <2>.
            . Expected <null>, actual <2>.
            different. Illegal value: <2>.
            Expected <token>, actual <token> is not same.
            Expected not same as <token>.
            Expected value to be null, but was: <value>.
            present. Expected value to be not null.
            null
            with cause
            true
            null
            true

            """,
            moduleName: "KUU1693KotlinTestAsserter",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKotlinTestUtilities(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
            import kotlin.test.*

            object CustomAsserter : Asserter {
                override fun fail(message: String?): Nothing {
                    throw AssertionError("custom: " + message)
                }
                override fun fail(message: String?, cause: Throwable?): Nothing {
                    throw AssertionError("custom: " + message, cause)
                }
            }

            fun main() {
                println(messagePrefix(null) == "")
                println(messagePrefix("") == ". ")
                println(messagePrefix("prefix") == "prefix. ")
                println(formatResultMessage(Unit))
                println(formatResultMessage(null))
                println(formatResultMessage(42))
                println(lookupAsserter() === DefaultAsserter)
                val previous = overrideAsserter(CustomAsserter)
                println(previous == null)
                println(asserter === CustomAsserter)
                println(lookupAsserter() === DefaultAsserter)
                try {
                    asserter.assertEquals(null, 1, 2)
                } catch (e: AssertionError) {
                    println(e.message)
                }
                println(overrideAsserter(previous) === CustomAsserter)
                println(asserter === DefaultAsserter)
                val cause = IllegalStateException("cause")
                val error = AssertionErrorWithCause("failure", cause)
                println(error.message)
                println(error.cause === cause)
            }
            """,
            expectedOutput: """
            true
            true
            true
            but was completed successfully.
            but was completed successfully with the result: <null>.
            but was completed successfully with the result: <42>.
            true
            true
            true
            true
            custom: Expected <1>, actual <2>.
            true
            true
            failure
            true

            """,
            moduleName: "KUU1693KotlinTestUtilities",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
