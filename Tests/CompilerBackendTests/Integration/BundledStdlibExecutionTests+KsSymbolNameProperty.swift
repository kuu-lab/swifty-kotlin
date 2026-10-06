import Testing

extension BundledStdlibExecutionTests {
    // KUU-585 regression: @KsSymbolName on a bundled class property must bind
    // the property symbol to its runtime getter bridge.
    @Test
    func testKsSymbolNameOnBundledClassPropertyExecutesThroughGetterBridge() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val pair = Pair("left", "right")
                println(pair.first)
            }
            """,
            moduleName: "KsSymbolNameProperty",
            expected: "left\n",
            allowDefaultStdlibLibrary: false
        )
    }

    @Test
    func testOptimizedKsSymbolNamePropertyUsesRuntimeBridgeABI() throws {
        try assertKotlinOutput(
            """
            fun main() {
                val pair = Pair("left", "right")
                println(pair.first)
            }
            """,
            moduleName: "OptimizedKsSymbolNameProperty",
            expected: "left\n",
            optLevel: .O2
        )
    }
}
