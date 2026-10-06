import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testKtorIOReadStringCoverage(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.io.*
            import kotlin.text.Charsets

            fun main() {
                val buffer = Buffer()
                buffer.writeString("héllo")
                println(buffer.readString(3L))
                println(buffer.readString())
                println(buffer.size)
                buffer.write(byteArrayOf(233.toByte(), 65))
                println(buffer.readString(1L, Charsets.ISO_8859_1))
                val source: Source = buffer
                println(source.readString(Charsets.US_ASCII))
                println(source.readString())
                buffer.write(byteArrayOf(65, 0, 66, 0))
                println(buffer.readString(charset = Charsets.UTF_16LE))
                buffer.writeString("tail")
                try { buffer.readString(-1L, Charsets.UTF_8) }
                catch (e: IllegalArgumentException) { println("negative") }
                try { buffer.readString(5L, Charsets.UTF_8) }
                catch (e: EOFException) { println("eof") }
                println(buffer.readString())
                val upstream = Buffer()
                upstream.writeString("buffered")
                val raw: RawSource = upstream
                println(raw.buffered().readString(Charsets.UTF_8))
            }
            """,
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
            """
            import kotlinx.coroutines.CopyableThrowable
            import kotlinx.coroutines.ExperimentalCoroutinesApi

            @OptIn(ExperimentalCoroutinesApi::class)
            class CopyableError(val code: Int) : Exception("copy"), CopyableThrowable<CopyableError> {
                override fun createCopy(): CopyableError? = CopyableError(code)
            }
            @OptIn(ExperimentalCoroutinesApi::class)
            class OptOutError : Exception(), CopyableThrowable<OptOutError> {
                override fun createCopy(): OptOutError? = null
            }
            @OptIn(ExperimentalCoroutinesApi::class)
            fun main() {
                val error: Throwable = CopyableError(7)
                if (error is CopyableThrowable<*>) {
                    println((error.createCopy() as CopyableError).code)
                }
                println(OptOutError().createCopy() == null)
            }
            """,
            expectedOutput: "7\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
