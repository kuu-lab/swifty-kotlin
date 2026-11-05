import Testing

extension BundledStdlibExecutionTests {
    /// `MessageDigest.getInstance` must accept exactly the spellings the
    /// JDK's SUN provider registers for each digest — the service name, its
    /// KnownOIDs aliases, and the "OID.<oid>" / bare "<oid>" forms, matched
    /// case-insensitively — and reject dash-folding lookalikes such as
    /// "SHA3256", "SHA-3-256", "S-H-A-256" and "MD-5" with
    /// NoSuchAlgorithmException like the JDK. Pins the per-spelling
    /// algorithm echo, digestLength, and "abc" digest vectors across the
    /// MD2/MD5, SHA-1, SHA-2, SHA-512/224|256, SHA3 and SHAKE families.
    /// Expected output was captured from kotlinc on OpenJDK 27.
    /// Regression for KUU-4315.
    @Test
    func testMessageDigestAlgorithmNameSpellings() throws {
        try compileAndRunKotlin(
            """
            import java.security.MessageDigest
            import java.security.NoSuchAlgorithmException

            // KUU-4315: bundled java.security.MessageDigest must accept exactly the
            // spellings the JDK's SUN provider registers for each digest — the service
            // name, its KnownOIDs aliases, and the "OID.<oid>" / bare "<oid>" forms,
            // matched case-insensitively — and reject dash-folding lookalikes such as
            // "SHA3256", "SHA-3-256", "S-H-A-256" and "MD-5" with
            // NoSuchAlgorithmException like the JDK.

            fun hex(bytes: ByteArray): String = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }

            fun main() {
                // Spellings the JDK accepts for each bundled algorithm.
                val accepted = listOf(
                    // MD2 (OID 1.2.840.113549.2.2) and MD5 (OID 1.2.840.113549.2.5)
                    "MD2", "md2", "OID.1.2.840.113549.2.2", "1.2.840.113549.2.2",
                    "MD5", "md5", "OID.1.2.840.113549.2.5", "1.2.840.113549.2.5",
                    // SHA-1 service: aliases "SHA", "SHA-1", "SHA1" + OID 1.3.14.3.2.26
                    "SHA", "SHA-1", "SHA1", "sha", "sHa-1", "OID.1.3.14.3.2.26", "1.3.14.3.2.26",
                    // SHA-224/256/384/512 (NIST OIDs 2.16.840.1.101.3.4.2.4/.1/.2/.3)
                    "SHA-224", "SHA224", "sha224", "OID.2.16.840.1.101.3.4.2.4", "2.16.840.1.101.3.4.2.4",
                    "SHA-256", "SHA256", "sha256", "OID.2.16.840.1.101.3.4.2.1", "2.16.840.1.101.3.4.2.1",
                    "SHA-384", "SHA384", "OID.2.16.840.1.101.3.4.2.2", "2.16.840.1.101.3.4.2.2",
                    "SHA-512", "SHA512", "OID.2.16.840.1.101.3.4.2.3", "2.16.840.1.101.3.4.2.3",
                    // SHA-512/224 and SHA-512/256 truncation variants (OIDs .2.5/.2.6)
                    "SHA-512/224", "SHA512/224", "sha-512/224", "OID.2.16.840.1.101.3.4.2.5", "2.16.840.1.101.3.4.2.5",
                    "SHA-512/256", "SHA512/256", "OID.2.16.840.1.101.3.4.2.6", "2.16.840.1.101.3.4.2.6",
                    // SHA3 family (OIDs .2.7-.2.10): only the "SHA3-<bits>" spelling is registered
                    "SHA3-224", "sha3-224", "OID.2.16.840.1.101.3.4.2.7", "2.16.840.1.101.3.4.2.7",
                    "SHA3-256", "sha3-256", "OID.2.16.840.1.101.3.4.2.8", "2.16.840.1.101.3.4.2.8",
                    "SHA3-384", "OID.2.16.840.1.101.3.4.2.9", "2.16.840.1.101.3.4.2.9",
                    "SHA3-512", "OID.2.16.840.1.101.3.4.2.10", "2.16.840.1.101.3.4.2.10",
                    // SHAKE: "SHAKE128"/"SHAKE256" are aliases of the -256/-512 services
                    // (OIDs .2.11/.2.12)
                    "SHAKE128", "SHAKE128-256", "shake128-256", "OID.2.16.840.1.101.3.4.2.11", "2.16.840.1.101.3.4.2.11",
                    "SHAKE256", "SHAKE256-512", "OID.2.16.840.1.101.3.4.2.12", "2.16.840.1.101.3.4.2.12"
                )
                for (name in accepted) {
                    val md = MessageDigest.getInstance(name)
                    println("ok|" + name + "|" + md.algorithm + "|" + md.digestLength + "|" +
                        hex(md.digest("abc".encodeToByteArray())))
                }

                // Spellings the JDK rejects even though dash-folding would map them
                // onto a supported algorithm (or that are simply unregistered).
                val rejected = listOf(
                    "SHA3256", "SHA-3-256", "SHA-3-224", "S-H-A-256", "S-H-A", "SHA--256",
                    "SHA25-6", "SHA-25-6", "MD-5", "M-D-5", "MD-2", "MD 5",
                    "SHA-512-224", "SHA-512-256", "SHA512224", "SHA512256", "SHA-512224",
                    "SHA512/384", "SHA-512/384", "SHA512384",
                    "SHA3224", "SHA3384", "SHA3512", "SHA3_256", "SHA3 256", "SHA3",
                    "SHAKE-128", "SHAKE-256", "SHAKE128256", "SHAKE256512", "SHAKE128-512",
                    "SHAKE128-LEN", "SHA256withRSA", "SHA1withRSA", "HmacSHA256",
                    "Tiger", "Tiger/192", "RIPEMD160", "WHIRLPOOL",
                    "OID.MD5", "OID.SHA-256", "OID.SHA256",
                    "SHA-256 ", " SHA-256", "SHA256/", "", " "
                )
                for (name in rejected) {
                    try {
                        MessageDigest.getInstance(name)
                        println("BAD|" + name + "|NO-THROW")
                    } catch (e: NoSuchAlgorithmException) {
                        println("rej|" + name + "|" + e.message)
                    }
                }
            }
            """,
            expectedOutput: """
            ok|MD2|MD2|16|da853b0d3f88d99b30283a69e6ded6bb
            ok|md2|md2|16|da853b0d3f88d99b30283a69e6ded6bb
            ok|OID.1.2.840.113549.2.2|OID.1.2.840.113549.2.2|16|da853b0d3f88d99b30283a69e6ded6bb
            ok|1.2.840.113549.2.2|1.2.840.113549.2.2|16|da853b0d3f88d99b30283a69e6ded6bb
            ok|MD5|MD5|16|900150983cd24fb0d6963f7d28e17f72
            ok|md5|md5|16|900150983cd24fb0d6963f7d28e17f72
            ok|OID.1.2.840.113549.2.5|OID.1.2.840.113549.2.5|16|900150983cd24fb0d6963f7d28e17f72
            ok|1.2.840.113549.2.5|1.2.840.113549.2.5|16|900150983cd24fb0d6963f7d28e17f72
            ok|SHA|SHA|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|SHA-1|SHA-1|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|SHA1|SHA1|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|sha|sha|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|sHa-1|sHa-1|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|OID.1.3.14.3.2.26|OID.1.3.14.3.2.26|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|1.3.14.3.2.26|1.3.14.3.2.26|20|a9993e364706816aba3e25717850c26c9cd0d89d
            ok|SHA-224|SHA-224|28|23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
            ok|SHA224|SHA224|28|23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
            ok|sha224|sha224|28|23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
            ok|OID.2.16.840.1.101.3.4.2.4|OID.2.16.840.1.101.3.4.2.4|28|23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
            ok|2.16.840.1.101.3.4.2.4|2.16.840.1.101.3.4.2.4|28|23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
            ok|SHA-256|SHA-256|32|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            ok|SHA256|SHA256|32|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            ok|sha256|sha256|32|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            ok|OID.2.16.840.1.101.3.4.2.1|OID.2.16.840.1.101.3.4.2.1|32|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            ok|2.16.840.1.101.3.4.2.1|2.16.840.1.101.3.4.2.1|32|ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
            ok|SHA-384|SHA-384|48|cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
            ok|SHA384|SHA384|48|cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
            ok|OID.2.16.840.1.101.3.4.2.2|OID.2.16.840.1.101.3.4.2.2|48|cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
            ok|2.16.840.1.101.3.4.2.2|2.16.840.1.101.3.4.2.2|48|cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
            ok|SHA-512|SHA-512|64|ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
            ok|SHA512|SHA512|64|ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
            ok|OID.2.16.840.1.101.3.4.2.3|OID.2.16.840.1.101.3.4.2.3|64|ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
            ok|2.16.840.1.101.3.4.2.3|2.16.840.1.101.3.4.2.3|64|ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
            ok|SHA-512/224|SHA-512/224|28|4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
            ok|SHA512/224|SHA512/224|28|4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
            ok|sha-512/224|sha-512/224|28|4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
            ok|OID.2.16.840.1.101.3.4.2.5|OID.2.16.840.1.101.3.4.2.5|28|4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
            ok|2.16.840.1.101.3.4.2.5|2.16.840.1.101.3.4.2.5|28|4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa
            ok|SHA-512/256|SHA-512/256|32|53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
            ok|SHA512/256|SHA512/256|32|53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
            ok|OID.2.16.840.1.101.3.4.2.6|OID.2.16.840.1.101.3.4.2.6|32|53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
            ok|2.16.840.1.101.3.4.2.6|2.16.840.1.101.3.4.2.6|32|53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23
            ok|SHA3-224|SHA3-224|28|e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf
            ok|sha3-224|sha3-224|28|e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf
            ok|OID.2.16.840.1.101.3.4.2.7|OID.2.16.840.1.101.3.4.2.7|28|e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf
            ok|2.16.840.1.101.3.4.2.7|2.16.840.1.101.3.4.2.7|28|e642824c3f8cf24ad09234ee7d3c766fc9a3a5168d0c94ad73b46fdf
            ok|SHA3-256|SHA3-256|32|3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
            ok|sha3-256|sha3-256|32|3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
            ok|OID.2.16.840.1.101.3.4.2.8|OID.2.16.840.1.101.3.4.2.8|32|3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
            ok|2.16.840.1.101.3.4.2.8|2.16.840.1.101.3.4.2.8|32|3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
            ok|SHA3-384|SHA3-384|48|ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25
            ok|OID.2.16.840.1.101.3.4.2.9|OID.2.16.840.1.101.3.4.2.9|48|ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25
            ok|2.16.840.1.101.3.4.2.9|2.16.840.1.101.3.4.2.9|48|ec01498288516fc926459f58e2c6ad8df9b473cb0fc08c2596da7cf0e49be4b298d88cea927ac7f539f1edf228376d25
            ok|SHA3-512|SHA3-512|64|b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
            ok|OID.2.16.840.1.101.3.4.2.10|OID.2.16.840.1.101.3.4.2.10|64|b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
            ok|2.16.840.1.101.3.4.2.10|2.16.840.1.101.3.4.2.10|64|b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0
            ok|SHAKE128|SHAKE128|32|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            ok|SHAKE128-256|SHAKE128-256|32|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            ok|shake128-256|shake128-256|32|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            ok|OID.2.16.840.1.101.3.4.2.11|OID.2.16.840.1.101.3.4.2.11|32|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            ok|2.16.840.1.101.3.4.2.11|2.16.840.1.101.3.4.2.11|32|5881092dd818bf5cf8a3ddb793fbcba74097d5c526a6d35f97b83351940f2cc8
            ok|SHAKE256|SHAKE256|64|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            ok|SHAKE256-512|SHAKE256-512|64|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            ok|OID.2.16.840.1.101.3.4.2.12|OID.2.16.840.1.101.3.4.2.12|64|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            ok|2.16.840.1.101.3.4.2.12|2.16.840.1.101.3.4.2.12|64|483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739d5a15bef186a5386c75744c0527e1faa9f8726e462a12a4feb06bd8801e751e4
            rej|SHA3256|SHA3256 MessageDigest not available
            rej|SHA-3-256|SHA-3-256 MessageDigest not available
            rej|SHA-3-224|SHA-3-224 MessageDigest not available
            rej|S-H-A-256|S-H-A-256 MessageDigest not available
            rej|S-H-A|S-H-A MessageDigest not available
            rej|SHA--256|SHA--256 MessageDigest not available
            rej|SHA25-6|SHA25-6 MessageDigest not available
            rej|SHA-25-6|SHA-25-6 MessageDigest not available
            rej|MD-5|MD-5 MessageDigest not available
            rej|M-D-5|M-D-5 MessageDigest not available
            rej|MD-2|MD-2 MessageDigest not available
            rej|MD 5|MD 5 MessageDigest not available
            rej|SHA-512-224|SHA-512-224 MessageDigest not available
            rej|SHA-512-256|SHA-512-256 MessageDigest not available
            rej|SHA512224|SHA512224 MessageDigest not available
            rej|SHA512256|SHA512256 MessageDigest not available
            rej|SHA-512224|SHA-512224 MessageDigest not available
            rej|SHA512/384|SHA512/384 MessageDigest not available
            rej|SHA-512/384|SHA-512/384 MessageDigest not available
            rej|SHA512384|SHA512384 MessageDigest not available
            rej|SHA3224|SHA3224 MessageDigest not available
            rej|SHA3384|SHA3384 MessageDigest not available
            rej|SHA3512|SHA3512 MessageDigest not available
            rej|SHA3_256|SHA3_256 MessageDigest not available
            rej|SHA3 256|SHA3 256 MessageDigest not available
            rej|SHA3|SHA3 MessageDigest not available
            rej|SHAKE-128|SHAKE-128 MessageDigest not available
            rej|SHAKE-256|SHAKE-256 MessageDigest not available
            rej|SHAKE128256|SHAKE128256 MessageDigest not available
            rej|SHAKE256512|SHAKE256512 MessageDigest not available
            rej|SHAKE128-512|SHAKE128-512 MessageDigest not available
            rej|SHAKE128-LEN|SHAKE128-LEN MessageDigest not available
            rej|SHA256withRSA|SHA256withRSA MessageDigest not available
            rej|SHA1withRSA|SHA1withRSA MessageDigest not available
            rej|HmacSHA256|HmacSHA256 MessageDigest not available
            rej|Tiger|Tiger MessageDigest not available
            rej|Tiger/192|Tiger/192 MessageDigest not available
            rej|RIPEMD160|RIPEMD160 MessageDigest not available
            rej|WHIRLPOOL|WHIRLPOOL MessageDigest not available
            rej|OID.MD5|OID.MD5 MessageDigest not available
            rej|OID.SHA-256|OID.SHA-256 MessageDigest not available
            rej|OID.SHA256|OID.SHA256 MessageDigest not available
            rej|SHA-256 |SHA-256  MessageDigest not available
            rej| SHA-256| SHA-256 MessageDigest not available
            rej|SHA256/|SHA256/ MessageDigest not available
            rej|| MessageDigest not available
            rej| |  MessageDigest not available

            """
        )
    }
}
