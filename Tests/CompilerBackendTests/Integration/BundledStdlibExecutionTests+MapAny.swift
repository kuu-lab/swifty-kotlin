import Testing

// KSP-1002: Map.any() must distinguish empty and non-empty maps while leaving
// the predicate overload on its existing runtime path.
extension BundledStdlibExecutionTests {
    @Test
    func testMapAnyNoArgAndPredicateOverloads() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val empty = emptyMap<String?, Int?>()
                val nonEmpty = mapOf<String?, Int?>(null to null, "value" to 1)

                println(empty.any())
                println(nonEmpty.any())
                println(nonEmpty.any { entry -> entry.key == null && entry.value == null })
                println(nonEmpty.any { false })
            }
            """,
            expectedOutput: "false\ntrue\ntrue\nfalse\n",
            moduleName: "KSP1002MapAny"
        )
    }
}
