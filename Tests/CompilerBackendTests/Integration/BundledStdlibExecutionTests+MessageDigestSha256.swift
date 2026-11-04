import Testing

extension BundledStdlibExecutionTests {
    /// `MessageDigest.getInstance("SHA-256")` must produce a working SHA-256
    /// digest — JDK canonical vectors, incremental `update` buffering, the
    /// `digest(data)` append-then-finalize contract, per-algorithm
    /// `digestLength`, and a `NoSuchAlgorithmException` for unsupported names.
    /// Regression for KUU-4166: only MD5 was implemented, so Rosetta
    /// `Parallel_Brute_Force` (`md.digest(pwd)` per candidate) threw at
    /// runtime.
    @Test
    func testMessageDigestSha256Contract() throws {
        try compileAndRunKotlin(
            """
            import java.security.MessageDigest
            import java.security.NoSuchAlgorithmException

            fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

            fun main() {
                val md = MessageDigest.getInstance("SHA-256")
                println(md.algorithm)
                println(md.digestLength)
                println(hex(md.digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("SHA-256").digest()))

                val incremental = MessageDigest.getInstance("SHA-256")
                incremental.update("a".encodeToByteArray())
                incremental.update('b'.code.toByte())
                incremental.update("c".encodeToByteArray())
                println(hex(incremental.digest()))
                println(hex(incremental.digest()))

                // JDK digest(data) appends to buffered input rather than resetting.
                incremental.update("zzz".encodeToByteArray())
                println(hex(incremental.digest("abc".encodeToByteArray())))

                val multiBlock = ByteArray(200) { (it % 256).toByte() }
                println(hex(MessageDigest.getInstance("SHA-256").digest(multiBlock)))

                val output = ByteArray(40)
                val written = MessageDigest.getInstance("SHA-256").digest(output, 4, 32)
                println(written)
                println(hex(output))

                println(MessageDigest.getInstance("sha-256").digestLength)
                println(hex(MessageDigest.getInstance("SHA256").digest("abc".encodeToByteArray())))

                println(hex(MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())))
                println(MessageDigest.getInstance("MD5").digestLength)

                try {
                    MessageDigest.getInstance("FOO")
                } catch (e: NoSuchAlgorithmException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: """
            SHA-256
            32
            ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
            ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
            f57c1b3650d8f46bdd8c17c733844c0cc0e25d04060b9629c109ec7bd09c0224
            1901da1c9f699b48f6b2636e65cbf73abf99d0441ef67f5c540a42f7051dec6f
            32
            00000000e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85500000000
            32
            ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            098f6bcd4621d373cade4e832627b4f6
            16
            FOO MessageDigest not available

            """
        )
    }
}
