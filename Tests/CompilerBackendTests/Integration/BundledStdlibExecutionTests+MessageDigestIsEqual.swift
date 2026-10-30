import Testing

extension BundledStdlibExecutionTests {
    /// `MessageDigest.isEqual` must compare the full byte range without an
    /// early exit on the first mismatch — the JDK documents a time-constant
    /// comparison because callers use it to verify MACs and digests. Pins the
    /// observable equality contract over the cases a `contentEquals`
    /// short-circuit also satisfies, plus null handling.
    @Test
    func testMessageDigestIsEqualComparisonContract() throws {
        try compileAndRunKotlin(
            """
            import java.security.MessageDigest

            fun main() {
                val digest = MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())
                val copy = digest.copyOf()
                val differentFirst = digest.copyOf()
                differentFirst[0] = (differentFirst[0] + 1).toByte()
                val differentLast = digest.copyOf()
                differentLast[15] = (differentLast[15] + 1).toByte()
                val shorter = digest.copyOfRange(0, 15)
                val longer = digest + byteArrayOf(0)

                println(MessageDigest.isEqual(digest, copy))
                println(MessageDigest.isEqual(digest, digest))
                println(MessageDigest.isEqual(digest, differentFirst))
                println(MessageDigest.isEqual(digest, differentLast))
                println(MessageDigest.isEqual(digest, shorter))
                println(MessageDigest.isEqual(digest, longer))
                println(MessageDigest.isEqual(null, null))
                println(MessageDigest.isEqual(digest, null))
                println(MessageDigest.isEqual(null, digest))
                println(MessageDigest.isEqual(ByteArray(0), ByteArray(0)))
            }
            """,
            expectedOutput: """
            true
            true
            false
            false
            false
            false
            true
            false
            false
            true

            """
        )
    }
}
