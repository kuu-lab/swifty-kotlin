import Testing

extension BundledStdlibExecutionTests {
    /// `MessageDigest.getInstance` must accept SHAKE128/SHAKE256 (the JDK's
    /// XOF providers expose a fixed 32/64-byte digest through this API) plus
    /// the SHAKE128-256/SHAKE256-512 spellings, while dashed or undashed
    /// lookalikes such as "SHAKE-128"/"SHAKE128256" are rejected exactly like
    /// the JDK. Pins canonical XOF vectors, case-insensitive aliases, the JDK
    /// reset contract (each digest() finalizes; the next digest() restarts
    /// from an empty buffer rather than continuing the XOF stream),
    /// digest(data) append semantics, update() bounds checking, and the
    /// DigestException / IllegalArgumentException / index-error split in
    /// digest(output, offset, length). Expected output was captured from
    /// kotlinc on OpenJDK 27. Regression for KUU-4306.
    @Test
    func testMessageDigestShakeXofContract() throws {
        try compileAndRunKotlin(
            """
            import java.security.DigestException
            import java.security.MessageDigest
            import java.security.NoSuchAlgorithmException

            // KUU-4306: bundled java.security.MessageDigest accepts SHAKE128/SHAKE256
            // (plus the JDK's SHAKE128-256/SHAKE256-512 spellings). Pins JVM parity for
            // the fixed digestLength contract (32/64 bytes), canonical XOF vectors,
            // alias spellings, the JDK reset semantics (each digest() finalizes and the
            // next digest() restarts from an empty buffer — the JDK SHAKE providers do
            // not continue the XOF stream across digest() calls), digest(data) append
            // semantics, update() bounds checking, and the DigestException /
            // IllegalArgumentException / index-error split in digest(output, offset,
            // length).

            fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

            fun probeDigestOut(md: MessageDigest, out: ByteArray, offset: Int, length: Int): String = try {
                "ok|" + md.digest(out, offset, length)
            } catch (e: DigestException) {
                "DigestException"
            } catch (e: IllegalArgumentException) {
                "IllegalArgumentException"
            } catch (e: IndexOutOfBoundsException) {
                "IndexOutOfBounds"
            } catch (e: Exception) {
                "Exception"
            }

            fun probeUpdate(data: ByteArray, offset: Int, length: Int): String = try {
                MessageDigest.getInstance("SHAKE128").update(data, offset, length)
                "ok"
            } catch (e: IllegalArgumentException) {
                "IllegalArgumentException"
            } catch (e: IndexOutOfBoundsException) {
                "IndexOutOfBounds"
            } catch (e: Exception) {
                "Exception"
            }

            fun main() {
                // digestLength and canonical vectors for the empty and "abc" inputs.
                for (name in listOf("SHAKE128", "SHAKE256", "SHAKE128-256", "SHAKE256-512")) {
                    val md = MessageDigest.getInstance(name)
                    println(name + "|" + md.algorithm + "|" + md.digestLength + "|" +
                        hex(md.digest("".encodeToByteArray())) + "|" +
                        hex(md.digest("abc".encodeToByteArray())))
                }

                // Case-insensitive aliases; the requested spelling is echoed back.
                println(MessageDigest.getInstance("shake128").algorithm)
                println(MessageDigest.getInstance("Shake256").digestLength)
                println(hex(MessageDigest.getInstance("sHaKe128-256").digest("abc".encodeToByteArray())))
                println(hex(MessageDigest.getInstance("shake256-512").digest("abc".encodeToByteArray())))

                // JDK reset semantics: after digest() the buffered input is consumed, so
                // a following digest() computes over an empty message (the XOF stream
                // does not continue across digest() calls on the JDK).
                val cont = MessageDigest.getInstance("SHAKE128")
                cont.update("abc".encodeToByteArray())
                println("c1|" + hex(cont.digest()))
                println("c2|" + hex(cont.digest()))
                println("c3|" + hex(cont.digest()))

                // update() after digest() starts a fresh computation.
                val upd = MessageDigest.getInstance("SHAKE128")
                upd.update("abc".encodeToByteArray())
                println("u1|" + hex(upd.digest()))
                upd.update("def".encodeToByteArray())
                println("u2|" + hex(upd.digest()))

                // digest(data) appends to buffered input before finalizing.
                val app = MessageDigest.getInstance("SHAKE256")
                app.update("abc".encodeToByteArray())
                println("a1|" + hex(app.digest("def".encodeToByteArray())))
                println("a2|" + hex(app.digest("ghi".encodeToByteArray())))

                // reset() discards buffered input and any consumed state.
                val rst = MessageDigest.getInstance("SHAKE256")
                rst.update("abc".encodeToByteArray())
                rst.digest()
                rst.update("zzz".encodeToByteArray())
                rst.reset()
                rst.update("abc".encodeToByteArray())
                println("r|" + hex(rst.digest()))

                // Incremental updates: ranged form, single byte, and zero-length updates
                // (a no-op for in-range or negative offsets; a positive out-of-range
                // offset still fails the facade bounds check, as on the JDK).
                val inc = MessageDigest.getInstance("SHAKE128")
                inc.update("ab".encodeToByteArray())
                inc.update(byteArrayOf('c'.code.toByte()))
                val ranged = "def".encodeToByteArray()
                inc.update(ranged, 0, 3)
                inc.update(ranged, 1, 0)
                inc.update(ranged, -5, 0)
                println("i|" + hex(inc.digest()))

                // Inputs straddling the SHAKE128 rate (168 bytes) and SHAKE256 rate
                // (136 bytes) boundaries, plus a multi-block case.
                for (size in listOf(135, 136, 137, 167, 168, 169, 200)) {
                    val boundary = ByteArray(size) { (it * 7 + 3).toByte() }
                    println("b128|" + size + "|" + hex(MessageDigest.getInstance("SHAKE128").digest(boundary)))
                    println("b256|" + size + "|" + hex(MessageDigest.getInstance("SHAKE256").digest(boundary)))
                }

                // digest(output, offset, length): writes digestLength bytes at offset and
                // returns digestLength, even when length is larger.
                val out = ByteArray(100)
                val okMd = MessageDigest.getInstance("SHAKE128")
                okMd.update("abc".encodeToByteArray())
                println("o1|" + probeDigestOut(okMd, out, 5, 40) + "|" + hex(out))
                val okMd2 = MessageDigest.getInstance("SHAKE256")
                okMd2.update("abc".encodeToByteArray())
                println("o2|" + probeDigestOut(okMd2, out, 0, 64) + "|" + hex(out))
                val okMd3 = MessageDigest.getInstance("SHAKE128")
                okMd3.update("abc".encodeToByteArray())
                println("o3|" + probeDigestOut(okMd3, out, 68, 32))

                // digest(output, offset, length) failure split: the facade's
                // offset+length bounds check is IllegalArgumentException; a length below
                // digestLength or an out-of-range offset is DigestException. A failed
                // call does not consume the buffered input.
                for (args in listOf(intArrayOf(0, 10), intArrayOf(0, 31), intArrayOf(90, 20), intArrayOf(95, 10),
                    intArrayOf(-1, 32), intArrayOf(0, -1), intArrayOf(0, 0), intArrayOf(69, 32), intArrayOf(60, 40))) {
                    val md = MessageDigest.getInstance("SHAKE128")
                    md.update("abc".encodeToByteArray())
                    println("p|" + args[0] + "|" + args[1] + "|" + probeDigestOut(md, out, args[0], args[1]))
                }
                val afterFail = MessageDigest.getInstance("SHAKE128")
                afterFail.update("abc".encodeToByteArray())
                try {
                    afterFail.digest(out, 0, 10)
                } catch (e: DigestException) {
                }
                println("af|" + hex(afterFail.digest()))

                // update(data, offset, length) bounds: past-the-end is
                // IllegalArgumentException, negative offset/length is an index error,
                // and a zero length never throws for the offset alone.
                val three = byteArrayOf(1, 2, 3)
                println("ub|" + probeUpdate(three, 0, 5))
                println("ub|" + probeUpdate(three, 100, 0))
                println("ub|" + probeUpdate(three, -2, 2))
                println("ub|" + probeUpdate(three, 0, -1))
                println("ub|" + probeUpdate(three, -5, 0))
                println("ub|" + probeUpdate(three, 1, 2))

                // Spellings the JDK rejects even though they fold to a supported name.
                for (name in listOf("SHAKE-128", "SHAKE-256", "SHAKE", "SHAKE128 ", "SHAKE128256",
                    "SHAKE256-256", "SHAKE128-128", "SHA3-128", "Keccak-128")) {
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
            SHAKE128|SHAKE128|32|7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            SHAKE256|SHAKE256|64|46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762fd75dc4ddd8c0f200cb05019d67b592f6fc821c49479ab48640292eacb3b7c4be|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            SHAKE128-256|SHAKE128-256|32|7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            SHAKE256-512|SHAKE256-512|64|46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762fd75dc4ddd8c0f200cb05019d67b592f6fc821c49479ab48640292eacb3b7c4be|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            shake128
            64
            5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            c1|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            c2|7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26
            c3|7f9c2ba4e88f827d616045507605853ed73b8093f6efbc88eb1a6eacfa66ef26
            u1|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            u2|5260b7b37c61501cd3de7e796ca493ccdab62ca931eeef3eca3fdcb0f7ac34d2
            a1|81d5e45d095acf3c0decf25bcc63f6ee16c689b909b48040ad91c7c67dfe4e9fec910fa73b44e84541600b5a5736b7b0869c89b1e403e35e550158e09bdb7430
            a2|a3c6444dc7444bfaa6e755b58dd25fe265a1ee01735e2cf186e69ef6d36e58113d01e9437e7382c947e4d2d1238ee55549c2bf47ac417991790f4a0a1081bfb2
            r|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            i|9428dbf9493c942630c0618d8a0983d518e828a7c0f4a39c2a54e013f64ebc12
            b128|135|c46af4f9a43a25a3f21d90f6a131ff3ed6944306e8c29a7c03f7e237e42c7e0c
            b256|135|0213fc98352f009fafdf8ee1ea36391485a85aa6f6c07a5cd81266d21eb17f9af3e3a6aa4a5e03793be3a4da4ba01c438b689164fc6bebb290eb372bfecd569d
            b128|136|c9b065cf999862c0c15d02ffa9450e5bf9b57d8457e3a366700de35043f450b4
            b256|136|c00f43811e5b4a38e14e3c06d8a5ce34115a19cd604ce5bac6c3823b76046d5c6b149f173bef3089dbfe66774f9723bc344ecbaa7e9674df4ceb8558811423c5
            b128|137|4bd0a672017e58746a1d4c98e2474ce03edf72679bb40f9613070cff215ae1b7
            b256|137|3c983983487bcbe74feba53b35bb1e05812379cb4116d9761f78d2ce3177866edc88e750bfaf43bd31ccd052078d97406fbfca21145c09c8d9bd1e81cd443e31
            b128|167|bb961bb015521037905f9baf69ce60dd3ba73f6ead09a559c8d8a85e10753bca
            b256|167|89a2450c9785e8a01d1baca6b7023479d3a0de33c757a9a584ec84714894c3b774b2960a6ae3a2f5f6e277b9b01f5b1a3ec0499d93b7d76d0b856e0d53fc1ad0
            b128|168|d4f73f3b6c4b72d05f45ed1f80b5774409f9cf336fc202bffa42ac38a6d3fbee
            b256|168|8e824d0df5f99be40bd0c4ee530e2b409a7c7713aba1ee96c56fb7f35729504e05dc6f8adb84b7e89d9b7de9c8e87f491c4c35e7d16173e4a986d26992d9c196
            b128|169|30454dd0f630ab1bb8fada554060d54012efdbb8e782d013f83a16af1282ca81
            b256|169|e76eaecce9983b4be8a8b9cd8b5a457e9b6995449ad142af68a83a0e171e52bb638feadda7d5732e1596f07e6a05e58b8668c23733ebf58ae88f783f6bbef4eb
            b128|200|243a1de243bd9dce318a217d75b1b026985c06b5de480fc6236143b663f7fe2c
            b256|200|cd24482e6e8eca556bce1cad6dfec6f4b53bac32f6a0eb0a99aaaf25018db3c1593cc1304b2e7b9075f18a93638530f3dfd52424a982cfa081bf49580bda2bd0
            o1|ok|32|00000000005881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
            o2|ok|64|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4000000000000000000000000000000000000000000000000000000000000000000000000
            o3|ok|32
            p|0|10|DigestException
            p|0|31|DigestException
            p|90|20|IllegalArgumentException
            p|95|10|IllegalArgumentException
            p|-1|32|DigestException
            p|0|-1|DigestException
            p|0|0|DigestException
            p|69|32|IllegalArgumentException
            p|60|40|ok|32
            af|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            ub|IllegalArgumentException
            ub|IllegalArgumentException
            ub|IndexOutOfBounds
            ub|IndexOutOfBounds
            ub|ok
            ub|ok
            SHAKE-128|SHAKE-128 MessageDigest not available
            SHAKE-256|SHAKE-256 MessageDigest not available
            SHAKE|SHAKE MessageDigest not available
            SHAKE128 |SHAKE128  MessageDigest not available
            SHAKE128256|SHAKE128256 MessageDigest not available
            SHAKE256-256|SHAKE256-256 MessageDigest not available
            SHAKE128-128|SHAKE128-128 MessageDigest not available
            SHA3-128|SHA3-128 MessageDigest not available
            Keccak-128|Keccak-128 MessageDigest not available

            """
        )
    }
}
