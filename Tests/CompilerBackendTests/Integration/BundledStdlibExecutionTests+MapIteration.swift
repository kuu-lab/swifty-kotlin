import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testMapDestructuringUnboxesPrimitiveValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val edgeWeights = mapOf("B" to 7.0)
                for ((vertex, edgeWeight) in edgeWeights) {
                    println("$vertex: ${5.0 + edgeWeight}")
                }
            }
            """,
            expectedOutput: "B: 12.0\n",
            moduleName: "MapDestructuringPrimitiveABI",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
