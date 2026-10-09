import Testing

extension BundledStdlibExecutionTests {
    /// KUU-1676: the obsolete public ticker API remains source-compatible and
    /// returns a channel whose producer stops when the channel is cancelled.
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
