import Testing

extension BundledStdlibExecutionTests {
    /// `MessageDigest.getInstance` must accept the full SHA-2 family
    /// (SHA-224/384/512 and the SHA-512/224, SHA-512/256 truncation variants),
    /// MD2 (RFC 1319), and the SHA-3 family (FIPS 202) — JDK canonical vectors,
    /// per-algorithm `digestLength`, incremental `update` buffering, the
    /// `digest(data)` append-then-finalize contract, JDK-accepted aliases, and
    /// a `NoSuchAlgorithmException` for unsupported names such as SHAKE-128
    /// (dashed spellings are rejected by the JDK; plain SHAKE128/SHAKE256 are
    /// covered by the KUU-4306 SHAKE suite).
    /// Regression for KUU-4281: only MD5/SHA-1/SHA-256 were implemented, so
    /// `getInstance("SHA-512")` and friends threw `NoSuchAlgorithmException`.
    @Test
    func testMessageDigestSha2FamilyContract() throws {
        try compileAndRunKotlin(
            """
            import java.security.MessageDigest
            import java.security.NoSuchAlgorithmException

            fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

            fun main() {
                // JDK canonical vectors for "abc" and the empty message across
                // the SHA-2 family, MD2, and the SHA-3 family.
                val algorithms = listOf(
                    "SHA-224", "SHA-384", "SHA-512", "SHA-512/224", "SHA-512/256",
                    "MD2", "SHA3-224", "SHA3-256", "SHA3-384", "SHA3-512"
                )
                for (name in algorithms) {
                    val md = MessageDigest.getInstance(name)
                    println(name + "|" + md.digestLength + "|" + hex(md.digest("abc".encodeToByteArray())) + "|" + hex(md.digest()))
                }

                // Incremental update and the JDK digest(data) append contract.
                val incremental = MessageDigest.getInstance("SHA-512")
                incremental.update("ab".encodeToByteArray())
                incremental.update(byteArrayOf('c'.code.toByte()))
                incremental.update("d".encodeToByteArray())
                println(hex(incremental.digest()))

                val appended = MessageDigest.getInstance("SHA3-256")
                appended.update("zzz".encodeToByteArray())
                println(hex(appended.digest("abc".encodeToByteArray())))

                // JDK-accepted alias spellings.
                println(hex(MessageDigest.getInstance("SHA512").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("SHA512/224").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("SHA512/256").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("sha3-256").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("md2").digest("abc".encodeToByteArray())))

                // Inputs straddling the SHA-512 128-byte block edge and the
                // SHA-3 rate boundaries.
                for (size in listOf(111, 112, 113, 127, 128, 129)) {
                    val boundary = ByteArray(size) { (it * 7 + 3).toByte() }
                    println("SHA-512|" + size + "|" + hex(MessageDigest.getInstance("SHA-512").digest(boundary)))
                    println("SHA3-256|" + size + "|" + hex(MessageDigest.getInstance("SHA3-256").digest(boundary)))
                }

                // Multi-block input.
                val multiBlock = ByteArray(200) { (it % 256).toByte() }
                println(hex(MessageDigest.getInstance("MD2").digest(multiBlock)))
                println(hex(MessageDigest.getInstance("SHA-384").digest(multiBlock)))
                println(hex(MessageDigest.getInstance("SHA3-512").digest(multiBlock)))

                // digest(output, offset, length) writes digestLength bytes.
                val output = ByteArray(80)
                val written = MessageDigest.getInstance("SHA-512").digest(output, 8, 64)
                println(written)
                println(hex(output))

                // Existing algorithms keep working.
                println(hex(MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())))
                println(MessageDigest.getInstance("MD5").digestLength)
                println(hex(MessageDigest.getInstance("SHA-1").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("SHA-256").digest("abc".encodeToByteArray())))

                for (name in listOf("SHA3", "FOO", "SHA_512", "SHA-512-256", "SHA512256", "SHAKE-128", "SHAKE128256")) {
                    try {
                        MessageDigest.getInstance(name)
                        println(name + "|NO-THROW")
                    } catch (e: NoSuchAlgorithmException) {
                        println(name + "|" + e.message)
                    }
                }
            }
            """,
            expectedOutput: """
            SHA-224|28|23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7|d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f
            SHA-384|48|cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7|38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b
            SHA-512|64|ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f|cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e
            SHA-512/224|28|4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa|6ed0dd02806fa89e25de060c19d3ac86cabb87d6a0ddd05c333b84f4
            SHA-512/256|32|53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23|c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a
            MD2|16|da853b0d3f88d99b30283a69e6ded6bb|8350e5a3e24c153df2275c9f80692773
            SHA3-224|28|e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf|6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7
            SHA3-256|32|3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532|a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a
            SHA3-384|48|ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25|0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004
            SHA3-512|64|b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0|a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26
            d8022f2060ad6efd297ab73dcc5355c9b214054b0d1776a136a669d26a7d3b14f73aa0d0ebff19ee333368f0164b6419a96da49e3e481753e7e96b716bdccb6f
            7b8047c5e390cb717c6b7435ebed1e8fba68aa13f00772ebdcef1dadc097bf12
            ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
            4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
            53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
            3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
            da853b0d3f88d99b30283a69e6ded6bb
            SHA-512|111|68cffa6d0d76f309c9ce0d35280939f8e25990c43b7b086ccdf709be35b07d4ddba599541ff2b1c19d34ea49aeafb9659adb7ac3c0b078bb30a22d57fc6687ef
            SHA3-256|111|1fc816a1c9bfb6fee349fb661b97d87a1adce7a3ec7a584de1fd9105cbd2d0a1
            SHA-512|112|d0865c524d1dddf7c23b799c413f5adcd7caefd3f66a9b49750ec81066012c25a8bcf94ddea6dc525691673097ca40e0101e897fc97218cfdb0704084e2bef4b
            SHA3-256|112|b2826938a19cca0b3f31274fa0d6dd36424508d245a16722a7b443efcfc167af
            SHA-512|113|606314353bd419f9f7720e8297f2af8a9ed5f0bb0bed29b716bf18e34577623ae7effa46f496bd4282134e7e895284a4760a910d2ad8ec11e9dd75863058cd9c
            SHA3-256|113|9520a3ee50eea6d83974bc420f2fefad9d42b98ad26e644e9ec98d2b8e3f6fea
            SHA-512|127|e0b6a20f1c0c88970a9340152cd5a1c1ecf3d3b8de55102741879438079473540133b812706e5dbec322c8c9523b6fc8c6d16ee626e87ad5fe3d2916afedc369
            SHA3-256|127|31578857f28c795c37ceb9bfffd3d24267d338e622927ae128330a5b07f22358
            SHA-512|128|99b16f17aa0b969a5b8f08f367719d516e330ccd2660b6f0688ec031dbc783de50a1cd185a2568dba75070a2403d17d4741d163578515dfd2ff756ddfe4d47b1
            SHA3-256|128|fcb6ea7388b68266e5df9f9beaf980fca55fdc6393f4d97ce1bcb2096eb4a975
            SHA-512|129|a1556e29185778aa5991e34b8884c840d589f0fbb4b8ed590e51e9ac4eb03a008125000db2671f8fe7f485b59a77b518670078ecb41a54b4cd02a7f1d2ca4c6d
            SHA3-256|129|7f516cd0d670dc44936a6f7e9b67271e41d88502acb3936a02b464f9475ca2cc
            c3b69aeecb7710b20fa0524ef1bf552d
            7ea4bb2534c67036f49de7beb5fe8a2478df04ff3fef40a9cd4923999a590e9912df1297217ce1a021aa2fb1013498b8
            ea5d05f19348dd589793354793a15f37a73b4c0bb4e750b9a00757dfce2f8b65a64191bb9b137de00feef6474cfd47abf7880efbc51614a5715df12cfe0caee3
            64
            0000000000000000cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e0000000000000000
            098f6bcd4621d373cade4e832627b4f6
            16
            a9993e364706816aba3e25717850c26c9cd0d89d
            ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            SHA3|SHA3 MessageDigest not available
            FOO|FOO MessageDigest not available
            SHA_512|SHA_512 MessageDigest not available
            SHA-512-256|SHA-512-256 MessageDigest not available
            SHA512256|SHA512256 MessageDigest not available
            SHAKE-128|SHAKE-128 MessageDigest not available
            SHAKE128256|SHAKE128256 MessageDigest not available

            """
        )
    }
}
