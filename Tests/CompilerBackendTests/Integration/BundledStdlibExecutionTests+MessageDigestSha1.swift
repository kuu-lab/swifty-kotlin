import Testing

extension BundledStdlibExecutionTests {
    /// `MessageDigest.getInstance("SHA-1")` must produce a working SHA-1
    /// digest — JDK canonical vectors, incremental `update` buffering, the
    /// `digest(data)` append-then-finalize contract, per-algorithm
    /// `digestLength`, the JDK "SHA" alias, and a
    /// `NoSuchAlgorithmException` for unsupported names.
    /// Regression for KUU-3990: only MD5/SHA-256 were implemented, so
    /// `getInstance("SHA-1")` threw `NoSuchAlgorithmException` and Rosetta
    /// `SHA1` ended in `KSwiftK panic [KSWIFTK-LINK-0003]`.
    @Test
    func testMessageDigestSha1Contract() throws {
        try compileAndRunKotlin(
            """
            import java.security.MessageDigest
            import java.security.NoSuchAlgorithmException

            fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

            fun main() {
                val md = MessageDigest.getInstance("SHA-1")
                println(md.algorithm)
                println(md.digestLength)
                println(hex(md.digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("SHA-1").digest()))

                val incremental = MessageDigest.getInstance("SHA-1")
                incremental.update("a".encodeToByteArray())
                incremental.update('b'.code.toByte())
                incremental.update("c".encodeToByteArray())
                println(hex(incremental.digest()))
                println(hex(incremental.digest()))

                // JDK digest(data) appends to buffered input rather than resetting.
                incremental.update("zzz".encodeToByteArray())
                println(hex(incremental.digest("abc".encodeToByteArray())))

                val multiBlock = ByteArray(200) { (it % 256).toByte() }
                println(hex(MessageDigest.getInstance("SHA-1").digest(multiBlock)))

                // Inputs straddling the 56-byte padding boundary and the
                // 64-byte block edge.
                for (size in listOf(55, 56, 64, 65)) {
                    val boundary = ByteArray(size) { (it * 7 + 3).toByte() }
                    println(hex(MessageDigest.getInstance("SHA-1").digest(boundary)))
                }

                val output = ByteArray(30)
                val written = MessageDigest.getInstance("SHA-1").digest(output, 4, 20)
                println(written)
                println(hex(output))

                println(MessageDigest.getInstance("sha-1").digestLength)
                println(hex(MessageDigest.getInstance("SHA1").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("SHA").digest("abc".encodeToByteArray())))

                val sliced = MessageDigest.getInstance("SHA-1")
                val wrapped = "xxabcxx".encodeToByteArray()
                sliced.update(wrapped, 2, 3)
                println(hex(sliced.digest()))

                println(hex(MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())))
                println(MessageDigest.getInstance("MD5").digestLength)
                println(hex(MessageDigest.getInstance("SHA-256").digest("abc".encodeToByteArray())))

                try {
                    MessageDigest.getInstance("FOO")
                } catch (e: NoSuchAlgorithmException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: """
            SHA-1
            20
            a9993e364706816aba3e25717850c26c9cd0d89d
            da39a3ee5e6b4b0d3255bfef95601890afd80709
            a9993e364706816aba3e25717850c26c9cd0d89d
            da39a3ee5e6b4b0d3255bfef95601890afd80709
            6328939a39d974a2e5286e331720ce0617dc3292
            54d11e99127d159799dbce10f51a75e697780478
            ddf57317ef34bfee3b6df83d359098930eb278bc
            a0d492bb0fc889d0eca3bc137066ab6f4f74f369
            bede92be29c3874e1b54ddc77988d606fc857a8e
            b05a80522b053d6dc7e0a517d0e70212c7dad11f
            20
            00000000da39a3ee5e6b4b0d3255bfef95601890afd80709000000000000
            20
            a9993e364706816aba3e25717850c26c9cd0d89d
            a9993e364706816aba3e25717850c26c9cd0d89d
            a9993e364706816aba3e25717850c26c9cd0d89d
            098f6bcd4621d373cade4e832627b4f6
            16
            ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            FOO MessageDigest not available

            """
        )
    }
}
