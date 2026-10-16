import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testReferenceVarargArrayHigherOrderFunctions(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            abstract class Base(val name: String)
            class S : Base("s")

            fun forEachNames(vararg items: Base) {
                items.forEach { println(it.name) }
            }

            fun forEachEmpty(vararg items: Base) {
                items.forEach { }
                println("empty-ok")
            }

            fun mapNames(vararg items: Base) {
                println(items.map { it.name })
            }

            fun filterNames(vararg items: Base) {
                items.filter { it.name == "s" }.forEach { println(it.name) }
            }

            fun main() {
                forEachNames(S(), S())
                forEachEmpty(S())
                mapNames(S(), S())
                filterNames(S(), S())
            }
            """,
            expectedOutput: """
            s
            s
            empty-ok
            [s, s]
            s
            s

            """,
            moduleName: "KUU2281ReferenceVarargArrayHOF",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
