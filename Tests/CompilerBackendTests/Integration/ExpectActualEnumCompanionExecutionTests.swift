import Testing

@Suite
struct ExpectActualEnumCompanionExecutionTests {
    @Test
    func actualCompanionMemberCallLinks() throws {
        try compileAndRunKotlin(
            """
            package x
            expect enum class E { A; companion object { fun h(): Int } }
            actual enum class E { A; actual companion object { actual fun h(): Int = 3 } }
            fun main() { println(E.h()) }
            """,
            expectedOutput: "3\n",
            moduleName: "KUU2348ExpectActualEnumCompanion"
        )
    }
}
