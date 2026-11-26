import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testTickerThroughBundledStdlib(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*

            @OptIn(ObsoleteCoroutinesApi::class)
            fun main() = runBlocking {
                val t = ticker(10, 0)
                t.receive()
                t.cancel()
                println("ticker-ok")
            }
            """,
            expectedOutput: "ticker-ok\n",
            moduleName: "KUU1676Ticker",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
