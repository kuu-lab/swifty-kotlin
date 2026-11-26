import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testCreateFailureThrowableErasedAnyToStringLength() throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
            fun main() {
                val marker: Any = kotlin.createFailure(RuntimeException("boom"))
                println(marker.toString().length > 0)
            }
            """,
            expectedOutput: "true\n",
            moduleName: "KUU4545CreateFailureThrowableAnyToString"
        )
    }
}
