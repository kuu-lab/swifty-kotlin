import Testing

extension BundledStdlibExecutionTests {
    // JVM kotlinc requires friend access to this internal @PublishedApi helper.
    // #12056 deleted `throwIndexOverflow`/`throwCountOverflow` (throw.kt) and
    // `checkCountOverflow` as never-wired-up dead code, leaving
    // `checkIndexOverflow` — which the bundled sequences call sites actually
    // use — as the remaining internal @PublishedApi overflow guard in
    // kotlin.collections. Nothing accessible still throws "Count overflow has
    // happened." (the surviving sites need Int overflow at runtime), so the
    // count case is dropped.
    @Test(arguments: [true, false])
    func testCollectionsOverflowHelpersRunCandidateOnly(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            package kotlin.collections
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

            private fun indexOverflowMessage(): String = try {
                checkIndexOverflow(-1)
                "no throw"
            } catch (e: ArithmeticException) {
                e.message ?: "null"
            }

            fun main() {
                println(indexOverflowMessage())
                println(indexOverflowMessage() == "Index overflow has happened.")
            }
            """,
            expectedOutput: "Index overflow has happened.\ntrue\n",
            moduleName: "KUU1499CollectionsOverflowHelpers",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
