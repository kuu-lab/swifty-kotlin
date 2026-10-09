import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testKtorIOReadStringCoverage(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_io_read_string_charset.kt", file: #filePath),
            expectedOutput: "hé\nllo\n0\né\nA\n\nAB\nnegative\neof\ntail\nbuffered\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testKtorOwnedSourceDiscard(allowDefaultStdlibLibrary: Bool) throws {
        // kotlinx-io 0.9.1 has no discard API. This is the extension supplied by
        // ktor's io.ktor.utils.io.core.ByteReadPacket.kt. Cross-package import
        // resolution is covered by KtorIOCoverageSourceTests.
        try compileAndRunKotlin(
            """
            import kotlinx.io.*

            fun Source.discard(count: Long = Long.MAX_VALUE): Long {
                request(count)
                val countToDiscard = minOf(count, buffer.size)
                buffer.skip(countToDiscard)
                return countToDiscard
            }
            fun main() {
                val buffer = Buffer()
                buffer.writeString("abc")
                val source: Source = buffer
                println(source.discard(0))
                println(source.discard(2))
                println(buffer.readString())
                buffer.writeString("xy")
                println(source.discard(10))
                println(source.discard())
            }
            """,
            expectedOutput: "0\n2\nc\n2\n0\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testKtorIOCopyableThrowableCoverage(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("copyable_throwable.kt", file: #filePath),
            expectedOutput: "7\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
