import Testing

extension BundledStdlibExecutionTests {
    @Test func testImmutableBlobFactoryLinksAndTruncatesVarargs() throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("DEPRECATION_ERROR")

            import kotlin.native.immutableBlobOf

            fun main() {
                val direct = immutableBlobOf(0x41, 0x42)
                println(direct.size)
                println(direct[0])
                val source = shortArrayOf(65, 255, 256, -1)
                val blob = immutableBlobOf(*source)
                println(blob.size)
                println(blob[0])
                println(blob[1])
                println(blob[2])
                println(blob[3])
                val empty = immutableBlobOf()
                println(empty.size)
            }
            """,
            expectedOutput: "2\n65\n4\n65\n-1\n0\n-1\n0\n"
        )
    }
}
