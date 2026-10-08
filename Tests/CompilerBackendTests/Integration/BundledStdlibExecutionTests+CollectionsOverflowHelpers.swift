import Testing

extension BundledStdlibExecutionTests {
    // JVM kotlinc requires friend access to these internal @PublishedApi helpers.
    @Test(arguments: [true, false])
    func testCollectionsOverflowHelpersRunCandidateOnly(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            package kotlin.collections
            @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

            private fun countOverflowMessage(): String = try {
                throwCountOverflow()
                "no throw"
            } catch (e: ArithmeticException) {
                e.message ?: "null"
            }

            private fun indexOverflowMessage(): String = try {
                throwIndexOverflow()
                "no throw"
            } catch (e: ArithmeticException) {
                e.message ?: "null"
            }

            fun main() {
                println(countOverflowMessage())
                println(indexOverflowMessage())
                println(countOverflowMessage() == "Count overflow has happened.")
                println(indexOverflowMessage() == "Index overflow has happened.")
            }
            """,
            expectedOutput: "Count overflow has happened.\nIndex overflow has happened.\ntrue\ntrue\n",
            moduleName: "KUU1499CollectionsOverflowHelpers",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
