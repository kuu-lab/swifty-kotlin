import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testTopLevelBlockGetterReturnTypeIndependentOfExpectedType() throws {
        try compileAndRunKotlin(
            """
            val allDone get(): Boolean { return true }

            fun pass(value: Boolean): Boolean = value

            fun main() {
                if (allDone) println("if")
                println(allDone)
                val inferred = allDone
                println(inferred)
                println(pass(allDone))
                println(!allDone)
                println(allDone.toString())
                println(allDone as Boolean)
                println(allDone as Any)
            }
            """,
            expectedOutput: "if\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\n",
            moduleName: "KUU2796BlockGetterReturnType"
        )
    }
}
