package java.security

/** Message digest facade over the algorithms used by the bundled JVM APIs. */
public class MessageDigest private constructor(public val algorithm: String) {
    private var input = ByteArray(0)
    private val normalizedAlgorithm = normalizeAlgorithmName(algorithm)

    public val digestLength: Int
        get() = when (normalizedAlgorithm) {
            "MD2", "MD5" -> 16
            "SHA1" -> 20
            "SHA224", "SHA512/224", "SHA3224" -> 28
            "SHA256", "SHA512/256", "SHA3256" -> 32
            "SHA384", "SHA3384" -> 48
            "SHA512", "SHA3512" -> 64
            // SHAKE128/SHAKE256 are XOFs, but the JDK's MessageDigest
            // providers (SHAKE128Hash/SHAKE256Hash) expose a fixed default
            // digest length; the "-256"/"-512" spellings are the same
            // providers registered under their internal names.
            "SHAKE128", "SHAKE128256" -> 32
            "SHAKE256", "SHAKE256512" -> 64
            else -> 16
        }

    public fun update(value: Byte) {
        update(byteArrayOf(value))
    }

    public fun update(data: ByteArray) {
        update(data, 0, data.size)
    }

    public fun update(data: ByteArray, offset: Int, length: Int) {
        // Mirrors java.security.MessageDigest.update(byte[], int, int): the
        // facade rejects ranges past the buffer end with
        // IllegalArgumentException, while the engine's index check reports
        // negative offsets/lengths as ArrayIndexOutOfBoundsException. A zero
        // length is a no-op even for an out-of-range offset (JDK
        // DigestBase.engineUpdate returns before validating).
        if (data.size - offset < length) {
            throw IllegalArgumentException("Input buffer too short")
        }
        if (length != 0 && (offset < 0 || length < 0 || offset > data.size - length)) {
            throw ArrayIndexOutOfBoundsException()
        }
        if (length == 0) {
            return
        }
        val combined = ByteArray(input.size + length)
        input.copyInto(combined)
        data.copyInto(combined, input.size, offset, offset + length)
        input = combined
    }

    public fun digest(): ByteArray {
        val result = when (normalizedAlgorithm) {
            "MD2" -> md2(input)
            "MD5" -> md5(input)
            "SHA1" -> sha1(input)
            "SHA224" -> sha224(input)
            "SHA256" -> sha256(input)
            "SHA384" -> sha384(input)
            "SHA512" -> sha512(input)
            "SHA512/224" -> sha512_224(input)
            "SHA512/256" -> sha512_256(input)
            "SHA3224" -> sha3(input, 144, 28)
            "SHA3256" -> sha3(input, 136, 32)
            "SHA3384" -> sha3(input, 104, 48)
            "SHA3512" -> sha3(input, 72, 64)
            "SHAKE128", "SHAKE128256" -> shake(input, 168, 32)
            "SHAKE256", "SHAKE256512" -> shake(input, 136, 64)
            else -> md5(input)
        }
        input = ByteArray(0)
        return result
    }

    public fun digest(data: ByteArray): ByteArray {
        update(data)
        return digest()
    }

    public fun digest(output: ByteArray, offset: Int, length: Int): Int {
        // Mirrors java.security.MessageDigest.digest(byte[], int, int): the
        // facade bounds-checks offset+length against the buffer with
        // IllegalArgumentException, then DigestBase.engineDigest rejects a
        // length below digestLength and out-of-range offsets with
        // DigestException. digestLength bytes are written at offset and
        // digestLength is returned regardless of the requested length.
        if (output.size - offset < length) {
            throw IllegalArgumentException("Output buffer too small for specified offset and length")
        }
        if (length < digestLength) {
            throw DigestException("Length must be at least $digestLength for $algorithm digests")
        }
        if (offset < 0 || length < 0 || offset > output.size - length) {
            throw DigestException("Buffer too short to store digest")
        }
        val result = digest()
        result.copyInto(output, offset)
        return result.size
    }

    public fun reset() {
        input = ByteArray(0)
    }

    public companion object {
        public fun getInstance(algorithm: String): MessageDigest {
            val normalized = normalizeAlgorithmName(algorithm)
            if (!isSupportedAlgorithm(normalized) ||
                !hasAcceptedAlgorithmSpelling(algorithm, normalized)) {
                throw NoSuchAlgorithmException("$algorithm MessageDigest not available")
            }
            return MessageDigest(algorithm)
        }

        public fun isEqual(first: ByteArray?, second: ByteArray?): Boolean {
            if (first == null || second == null) return first == null && second == null
            if (first.size != second.size) return false
            var difference = 0
            var index = 0
            while (index < first.size) {
                difference = difference or (first[index].toInt() xor second[index].toInt())
                index += 1
            }
            return difference == 0
        }
    }
}

private val MD5_SHIFTS = intArrayOf(
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
)

private val MD5_CONSTANTS = intArrayOf(
    -680876936, -389564586, 606105819, -1044525330, -176418897, 1200080426, -1473231341, -45705983,
    1770035416, -1958414417, -42063, -1990404162, 1804603682, -40341101, -1502002290, 1236535329,
    -165796510, -1069501632, 643717713, -373897302, -701558691, 38016083, -660478335, -405537848,
    568446438, -1019803690, -187363961, 1163531501, -1444681467, -51403784, 1735328473, -1926607734,
    -378558, -2022574463, 1839030562, -35309556, -1530992060, 1272893353, -155497632, -1094730640,
    681279174, -358537222, -722521979, 76029189, -640364487, -421815835, 530742520, -995338651,
    -198630844, 1126891415, -1416354905, -57434055, 1700485571, -1894986606, -1051523, -2054922799,
    1873313359, -30611744, -1560198380, 1309151649, -145523070, -1120210379, 718787259, -343485551
)

private fun md5(input: ByteArray): ByteArray {
    val paddedLength = ((input.size + 8) / 64 + 1) * 64
    val padded = ByteArray(paddedLength)
    input.copyInto(padded)
    padded[input.size] = 0x80.toByte()
    val bitLength = input.size.toLong() * 8L
    var lengthIndex = 0
    while (lengthIndex < 8) {
        padded[paddedLength - 8 + lengthIndex] = (bitLength ushr (lengthIndex * 8)).toByte()
        lengthIndex++
    }

    var stateA = 0x67452301
    var stateB = -271733879
    var stateC = -1732584194
    var stateD = 0x10325476
    val words = IntArray(16)
    var block = 0
    while (block < padded.size) {
        var wordIndex = 0
        while (wordIndex < 16) {
            val byteIndex = block + wordIndex * 4
            words[wordIndex] = (padded[byteIndex].toInt() and 0xFF) or
                ((padded[byteIndex + 1].toInt() and 0xFF) shl 8) or
                ((padded[byteIndex + 2].toInt() and 0xFF) shl 16) or
                ((padded[byteIndex + 3].toInt() and 0xFF) shl 24)
            wordIndex++
        }

        var a = stateA
        var b = stateB
        var c = stateC
        var d = stateD
        var round = 0
        while (round < 64) {
            val function: Int
            val word: Int
            if (round < 16) {
                function = (b and c) or (b.inv() and d)
                word = round
            } else if (round < 32) {
                function = (d and b) or (d.inv() and c)
                word = (5 * round + 1) % 16
            } else if (round < 48) {
                function = b xor c xor d
                word = (3 * round + 5) % 16
            } else {
                function = c xor (b or d.inv())
                word = (7 * round) % 16
            }
            val previousD = d
            d = c
            c = b
            b += rotateLeft(a + function + MD5_CONSTANTS[round] + words[word], MD5_SHIFTS[round])
            a = previousD
            round++
        }
        stateA += a
        stateB += b
        stateC += c
        stateD += d
        block += 64
    }

    val result = ByteArray(16)
    val state = intArrayOf(stateA, stateB, stateC, stateD)
    var stateIndex = 0
    while (stateIndex < state.size) {
        var byteIndex = 0
        while (byteIndex < 4) {
            result[stateIndex * 4 + byteIndex] = (state[stateIndex] ushr (byteIndex * 8)).toByte()
            byteIndex++
        }
        stateIndex++
    }
    return result
}

private fun sha1(input: ByteArray): ByteArray {
    val paddedLength = ((input.size + 8) / 64 + 1) * 64
    val padded = ByteArray(paddedLength)
    input.copyInto(padded)
    padded[input.size] = 0x80.toByte()
    val bitLength = input.size.toLong() * 8L
    var lengthIndex = 0
    while (lengthIndex < 8) {
        padded[paddedLength - 1 - lengthIndex] = (bitLength ushr (lengthIndex * 8)).toByte()
        lengthIndex++
    }

    var state0 = 0x67452301
    var state1 = 0xefcdab89.toInt()
    var state2 = 0x98badcfe.toInt()
    var state3 = 0x10325476
    var state4 = 0xc3d2e1f0.toInt()
    val words = IntArray(80)
    var block = 0
    while (block < padded.size) {
        var wordIndex = 0
        while (wordIndex < 16) {
            val byteIndex = block + wordIndex * 4
            words[wordIndex] = ((padded[byteIndex].toInt() and 0xFF) shl 24) or
                ((padded[byteIndex + 1].toInt() and 0xFF) shl 16) or
                ((padded[byteIndex + 2].toInt() and 0xFF) shl 8) or
                (padded[byteIndex + 3].toInt() and 0xFF)
            wordIndex++
        }
        while (wordIndex < 80) {
            words[wordIndex] = rotateLeft(
                words[wordIndex - 3] xor words[wordIndex - 8] xor
                    words[wordIndex - 14] xor words[wordIndex - 16],
                1
            )
            wordIndex++
        }

        var a = state0
        var b = state1
        var c = state2
        var d = state3
        var e = state4
        var round = 0
        while (round < 80) {
            val function: Int
            val constant: Int
            if (round < 20) {
                function = (b and c) or (b.inv() and d)
                constant = 0x5a827999
            } else if (round < 40) {
                function = b xor c xor d
                constant = 0x6ed9eba1
            } else if (round < 60) {
                function = (b and c) or (b and d) or (c and d)
                constant = 0x8f1bbcdc.toInt()
            } else {
                function = b xor c xor d
                constant = 0xca62c1d6.toInt()
            }
            val temporary = rotateLeft(a, 5) + function + e + constant + words[round]
            e = d
            d = c
            c = rotateLeft(b, 30)
            b = a
            a = temporary
            round++
        }
        state0 += a
        state1 += b
        state2 += c
        state3 += d
        state4 += e
        block += 64
    }

    val result = ByteArray(20)
    val state = intArrayOf(state0, state1, state2, state3, state4)
    var stateIndex = 0
    while (stateIndex < state.size) {
        var byteIndex = 0
        while (byteIndex < 4) {
            result[stateIndex * 4 + byteIndex] = (state[stateIndex] ushr ((3 - byteIndex) * 8)).toByte()
            byteIndex++
        }
        stateIndex++
    }
    return result
}

private val SHA256_CONSTANTS = intArrayOf(
    0x428a2f98.toInt(), 0x71374491.toInt(), 0xb5c0fbcf.toInt(), 0xe9b5dba5.toInt(),
    0x3956c25b.toInt(), 0x59f111f1.toInt(), 0x923f82a4.toInt(), 0xab1c5ed5.toInt(),
    0xd807aa98.toInt(), 0x12835b01.toInt(), 0x243185be.toInt(), 0x550c7dc3.toInt(),
    0x72be5d74.toInt(), 0x80deb1fe.toInt(), 0x9bdc06a7.toInt(), 0xc19bf174.toInt(),
    0xe49b69c1.toInt(), 0xefbe4786.toInt(), 0x0fc19dc6.toInt(), 0x240ca1cc.toInt(),
    0x2de92c6f.toInt(), 0x4a7484aa.toInt(), 0x5cb0a9dc.toInt(), 0x76f988da.toInt(),
    0x983e5152.toInt(), 0xa831c66d.toInt(), 0xb00327c8.toInt(), 0xbf597fc7.toInt(),
    0xc6e00bf3.toInt(), 0xd5a79147.toInt(), 0x06ca6351.toInt(), 0x14292967.toInt(),
    0x27b70a85.toInt(), 0x2e1b2138.toInt(), 0x4d2c6dfc.toInt(), 0x53380d13.toInt(),
    0x650a7354.toInt(), 0x766a0abb.toInt(), 0x81c2c92e.toInt(), 0x92722c85.toInt(),
    0xa2bfe8a1.toInt(), 0xa81a664b.toInt(), 0xc24b8b70.toInt(), 0xc76c51a3.toInt(),
    0xd192e819.toInt(), 0xd6990624.toInt(), 0xf40e3585.toInt(), 0x106aa070.toInt(),
    0x19a4c116.toInt(), 0x1e376c08.toInt(), 0x2748774c.toInt(), 0x34b0bcb5.toInt(),
    0x391c0cb3.toInt(), 0x4ed8aa4a.toInt(), 0x5b9cca4f.toInt(), 0x682e6ff3.toInt(),
    0x748f82ee.toInt(), 0x78a5636f.toInt(), 0x84c87814.toInt(), 0x8cc70208.toInt(),
    0x90befffa.toInt(), 0xa4506ceb.toInt(), 0xbef9a3f7.toInt(), 0xc67178f2.toInt()
)

private val SHA256_IV = intArrayOf(
    0x6a09e667, 0xbb67ae85.toInt(), 0x3c6ef372, 0xa54ff53a.toInt(),
    0x510e527f, 0x9b05688c.toInt(), 0x1f83d9ab, 0x5be0cd19
)

// SHA-224 (FIPS 180-4) reuses the SHA-256 compression function with a
// different initial value and a 28-byte truncation.
private val SHA224_IV = intArrayOf(
    0xc1059ed8.toInt(), 0x367cd507, 0x3070dd17, 0xf70e5939.toInt(),
    0xffc00b31.toInt(), 0x68581511, 0x64f98fa7, 0xbefa4fa4.toInt()
)

private fun sha224(input: ByteArray): ByteArray = sha256Digest(input, SHA224_IV, 28)

private fun sha256(input: ByteArray): ByteArray = sha256Digest(input, SHA256_IV, 32)

private fun sha256Digest(input: ByteArray, initialState: IntArray, outputLength: Int): ByteArray {
    val paddedLength = ((input.size + 8) / 64 + 1) * 64
    val padded = ByteArray(paddedLength)
    input.copyInto(padded)
    padded[input.size] = 0x80.toByte()
    val bitLength = input.size.toLong() * 8L
    var lengthIndex = 0
    while (lengthIndex < 8) {
        padded[paddedLength - 1 - lengthIndex] = (bitLength ushr (lengthIndex * 8)).toByte()
        lengthIndex++
    }

    var state0 = initialState[0]
    var state1 = initialState[1]
    var state2 = initialState[2]
    var state3 = initialState[3]
    var state4 = initialState[4]
    var state5 = initialState[5]
    var state6 = initialState[6]
    var state7 = initialState[7]
    val words = IntArray(64)
    var block = 0
    while (block < padded.size) {
        var wordIndex = 0
        while (wordIndex < 16) {
            val byteIndex = block + wordIndex * 4
            words[wordIndex] = ((padded[byteIndex].toInt() and 0xFF) shl 24) or
                ((padded[byteIndex + 1].toInt() and 0xFF) shl 16) or
                ((padded[byteIndex + 2].toInt() and 0xFF) shl 8) or
                (padded[byteIndex + 3].toInt() and 0xFF)
            wordIndex++
        }
        while (wordIndex < 64) {
            val word15 = words[wordIndex - 15]
            val word2 = words[wordIndex - 2]
            words[wordIndex] = words[wordIndex - 16] +
                (rotateRight(word15, 7) xor rotateRight(word15, 18) xor (word15 ushr 3)) +
                words[wordIndex - 7] +
                (rotateRight(word2, 17) xor rotateRight(word2, 19) xor (word2 ushr 10))
            wordIndex++
        }

        var a = state0
        var b = state1
        var c = state2
        var d = state3
        var e = state4
        var f = state5
        var g = state6
        var h = state7
        var round = 0
        while (round < 64) {
            val sigma1 = rotateRight(e, 6) xor rotateRight(e, 11) xor rotateRight(e, 25)
            val choose = (e and f) xor (e.inv() and g)
            val temp1 = h + sigma1 + choose + SHA256_CONSTANTS[round] + words[round]
            val sigma0 = rotateRight(a, 2) xor rotateRight(a, 13) xor rotateRight(a, 22)
            val majority = (a and b) xor (a and c) xor (b and c)
            val temp2 = sigma0 + majority
            h = g
            g = f
            f = e
            e = d + temp1
            d = c
            c = b
            b = a
            a = temp1 + temp2
            round++
        }
        state0 += a
        state1 += b
        state2 += c
        state3 += d
        state4 += e
        state5 += f
        state6 += g
        state7 += h
        block += 64
    }

    val result = ByteArray(outputLength)
    val state = intArrayOf(state0, state1, state2, state3, state4, state5, state6, state7)
    var outIndex = 0
    while (outIndex < outputLength) {
        val wordIndex = outIndex / 4
        val byteInWord = outIndex % 4
        result[outIndex] = (state[wordIndex] ushr ((3 - byteInWord) * 8)).toByte()
        outIndex++
    }
    return result
}

private fun rotateLeft(value: Int, distance: Int): Int =
    (value shl distance) or (value ushr (32 - distance))

private fun rotateRight(value: Int, distance: Int): Int =
    (value ushr distance) or (value shl (32 - distance))

private fun rotateRight(value: Long, distance: Int): Long =
    (value ushr distance) or (value shl (64 - distance))

private fun rotateLeft(value: Long, distance: Int): Long =
    (value shl distance) or (value ushr (64 - distance))

private fun isSupportedAlgorithm(normalized: String): Boolean = when (normalized) {
    "MD2", "MD5", "SHA1", "SHA224", "SHA256", "SHA384", "SHA512",
    "SHA512/224", "SHA512/256",
    "SHA3224", "SHA3256", "SHA3384", "SHA3512",
    "SHAKE128", "SHAKE256", "SHAKE128256", "SHAKE256512" -> true
    else -> false
}

// The JDK registers SHAKE only under the spellings "SHAKE128", "SHAKE256",
// "SHAKE128-256" and "SHAKE256-512" (matched case-insensitively).
// normalizeAlgorithmName folds '-' and case, so lookalikes such as
// "SHAKE-128" or the undashed "SHAKE128256" would normalize to a supported
// name; the original spelling is checked here to reject them like the JDK.
private fun hasAcceptedAlgorithmSpelling(algorithm: String, normalized: String): Boolean =
    when (normalized) {
        "SHAKE128" -> algorithm.uppercase() == "SHAKE128"
        "SHAKE256" -> algorithm.uppercase() == "SHAKE256"
        "SHAKE128256" -> algorithm.uppercase() == "SHAKE128-256"
        "SHAKE256512" -> algorithm.uppercase() == "SHAKE256-512"
        else -> true
    }

private fun normalizeAlgorithmName(algorithm: String): String {
    val normalized = algorithm.replace("-", "").uppercase()
    // The JDK accepts "SHA" as an alias for SHA-1.
    return if (normalized == "SHA") "SHA1" else normalized
}

// MARK: - SHA-512 family (FIPS 180-4)
//
// SHA-512, SHA-384, SHA-512/224 and SHA-512/256 share the same 128-byte
// block compression function and 128-bit big-endian length padding; they
// differ only in the initial chaining value and the output truncation.
// All 64-bit word arithmetic is done on `Long`, whose operators wrap
// modulo 2^64 exactly like the spec requires. Constants that exceed
// Int64/UInt64-positive range are written as `ULong` literals converted
// with `toLong()` so the bit pattern is preserved.

private val SHA512_K = longArrayOf(
    0x428a2f98d728ae22uL.toLong(), 0x7137449123ef65cduL.toLong(),
    0xb5c0fbcfec4d3b2fuL.toLong(), 0xe9b5dba58189dbbcuL.toLong(),
    0x3956c25bf348b538uL.toLong(), 0x59f111f1b605d019uL.toLong(),
    0x923f82a4af194f9buL.toLong(), 0xab1c5ed5da6d8118uL.toLong(),
    0xd807aa98a3030242uL.toLong(), 0x12835b0145706fbeuL.toLong(),
    0x243185be4ee4b28cuL.toLong(), 0x550c7dc3d5ffb4e2uL.toLong(),
    0x72be5d74f27b896fuL.toLong(), 0x80deb1fe3b1696b1uL.toLong(),
    0x9bdc06a725c71235uL.toLong(), 0xc19bf174cf692694uL.toLong(),
    0xe49b69c19ef14ad2uL.toLong(), 0xefbe4786384f25e3uL.toLong(),
    0x0fc19dc68b8cd5b5uL.toLong(), 0x240ca1cc77ac9c65uL.toLong(),
    0x2de92c6f592b0275uL.toLong(), 0x4a7484aa6ea6e483uL.toLong(),
    0x5cb0a9dcbd41fbd4uL.toLong(), 0x76f988da831153b5uL.toLong(),
    0x983e5152ee66dfabuL.toLong(), 0xa831c66d2db43210uL.toLong(),
    0xb00327c898fb213fuL.toLong(), 0xbf597fc7beef0ee4uL.toLong(),
    0xc6e00bf33da88fc2uL.toLong(), 0xd5a79147930aa725uL.toLong(),
    0x06ca6351e003826fuL.toLong(), 0x142929670a0e6e70uL.toLong(),
    0x27b70a8546d22ffcuL.toLong(), 0x2e1b21385c26c926uL.toLong(),
    0x4d2c6dfc5ac42aeduL.toLong(), 0x53380d139d95b3dfuL.toLong(),
    0x650a73548baf63deuL.toLong(), 0x766a0abb3c77b2a8uL.toLong(),
    0x81c2c92e47edaee6uL.toLong(), 0x92722c851482353buL.toLong(),
    0xa2bfe8a14cf10364uL.toLong(), 0xa81a664bbc423001uL.toLong(),
    0xc24b8b70d0f89791uL.toLong(), 0xc76c51a30654be30uL.toLong(),
    0xd192e819d6ef5218uL.toLong(), 0xd69906245565a910uL.toLong(),
    0xf40e35855771202auL.toLong(), 0x106aa07032bbd1b8uL.toLong(),
    0x19a4c116b8d2d0c8uL.toLong(), 0x1e376c085141ab53uL.toLong(),
    0x2748774cdf8eeb99uL.toLong(), 0x34b0bcb5e19b48a8uL.toLong(),
    0x391c0cb3c5c95a63uL.toLong(), 0x4ed8aa4ae3418acbuL.toLong(),
    0x5b9cca4f7763e373uL.toLong(), 0x682e6ff3d6b2b8a3uL.toLong(),
    0x748f82ee5defb2fcuL.toLong(), 0x78a5636f43172f60uL.toLong(),
    0x84c87814a1f0ab72uL.toLong(), 0x8cc702081a6439ecuL.toLong(),
    0x90befffa23631e28uL.toLong(), 0xa4506cebde82bde9uL.toLong(),
    0xbef9a3f7b2c67915uL.toLong(), 0xc67178f2e372532buL.toLong(),
    0xca273eceea26619cuL.toLong(), 0xd186b8c721c0c207uL.toLong(),
    0xeada7dd6cde0eb1euL.toLong(), 0xf57d4f7fee6ed178uL.toLong(),
    0x06f067aa72176fbauL.toLong(), 0x0a637dc5a2c898a6uL.toLong(),
    0x113f9804bef90daeuL.toLong(), 0x1b710b35131c471buL.toLong(),
    0x28db77f523047d84uL.toLong(), 0x32caab7b40c72493uL.toLong(),
    0x3c9ebe0a15c9bebcuL.toLong(), 0x431d67c49c100d4cuL.toLong(),
    0x4cc5d4becb3e42b6uL.toLong(), 0x597f299cfc657e2auL.toLong(),
    0x5fcb6fab3ad6faecuL.toLong(), 0x6c44198c4a475817uL.toLong()
)

private val SHA512_IV = longArrayOf(
    0x6a09e667f3bcc908uL.toLong(), 0xbb67ae8584caa73buL.toLong(),
    0x3c6ef372fe94f82buL.toLong(), 0xa54ff53a5f1d36f1uL.toLong(),
    0x510e527fade682d1uL.toLong(), 0x9b05688c2b3e6c1fuL.toLong(),
    0x1f83d9abfb41bd6buL.toLong(), 0x5be0cd19137e2179uL.toLong()
)

private val SHA384_IV = longArrayOf(
    0xcbbb9d5dc1059ed8uL.toLong(), 0x629a292a367cd507uL.toLong(),
    0x9159015a3070dd17uL.toLong(), 0x152fecd8f70e5939uL.toLong(),
    0x67332667ffc00b31uL.toLong(), 0x8eb44a8768581511uL.toLong(),
    0xdb0c2e0d64f98fa7uL.toLong(), 0x47b5481dbefa4fa4uL.toLong()
)

private val SHA512_224_IV = longArrayOf(
    0x8c3d37c819544da2uL.toLong(), 0x73e1996689dcd4d6uL.toLong(),
    0x1dfab7ae32ff9c82uL.toLong(), 0x679dd514582f9fcfuL.toLong(),
    0x0f6d2b697bd44da8uL.toLong(), 0x77e36f7304c48942uL.toLong(),
    0x3f9d85a86a1d36c8uL.toLong(), 0x1112e6ad91d692a1uL.toLong()
)

private val SHA512_256_IV = longArrayOf(
    0x22312194fc2bf72cuL.toLong(), 0x9f555fa3c84c64c2uL.toLong(),
    0x2393b86b6f53b151uL.toLong(), 0x963877195940eabduL.toLong(),
    0x96283ee2a88effe3uL.toLong(), 0xbe5e1e2553863992uL.toLong(),
    0x2b0199fc2c85b8aauL.toLong(), 0x0eb72ddc81c52ca2uL.toLong()
)

private fun sha512(input: ByteArray): ByteArray = sha512Digest(input, SHA512_IV, 64)

private fun sha384(input: ByteArray): ByteArray = sha512Digest(input, SHA384_IV, 48)

private fun sha512_224(input: ByteArray): ByteArray = sha512Digest(input, SHA512_224_IV, 28)

private fun sha512_256(input: ByteArray): ByteArray = sha512Digest(input, SHA512_256_IV, 32)

private fun sha512Digest(input: ByteArray, initialState: LongArray, outputLength: Int): ByteArray {
    // 128-byte blocks; the length field is a 128-bit big-endian bit count.
    // input.size is an Int, so the high 64 bits of the length are always 0.
    val paddedLength = ((input.size + 16) / 128 + 1) * 128
    val padded = ByteArray(paddedLength)
    input.copyInto(padded)
    padded[input.size] = 0x80.toByte()
    val bitLength = input.size.toLong() * 8L
    var lengthIndex = 0
    while (lengthIndex < 8) {
        padded[paddedLength - 1 - lengthIndex] = (bitLength ushr (lengthIndex * 8)).toByte()
        lengthIndex++
    }

    var state0 = initialState[0]
    var state1 = initialState[1]
    var state2 = initialState[2]
    var state3 = initialState[3]
    var state4 = initialState[4]
    var state5 = initialState[5]
    var state6 = initialState[6]
    var state7 = initialState[7]
    val words = LongArray(80)
    var block = 0
    while (block < padded.size) {
        var wordIndex = 0
        while (wordIndex < 16) {
            val byteIndex = block + wordIndex * 8
            words[wordIndex] =
                ((padded[byteIndex].toLong() and 0xFFL) shl 56) or
                ((padded[byteIndex + 1].toLong() and 0xFFL) shl 48) or
                ((padded[byteIndex + 2].toLong() and 0xFFL) shl 40) or
                ((padded[byteIndex + 3].toLong() and 0xFFL) shl 32) or
                ((padded[byteIndex + 4].toLong() and 0xFFL) shl 24) or
                ((padded[byteIndex + 5].toLong() and 0xFFL) shl 16) or
                ((padded[byteIndex + 6].toLong() and 0xFFL) shl 8) or
                (padded[byteIndex + 7].toLong() and 0xFFL)
            wordIndex++
        }
        while (wordIndex < 80) {
            val word15 = words[wordIndex - 15]
            val word2 = words[wordIndex - 2]
            words[wordIndex] = words[wordIndex - 16] +
                (rotateRight(word15, 1) xor rotateRight(word15, 8) xor (word15 ushr 7)) +
                words[wordIndex - 7] +
                (rotateRight(word2, 19) xor rotateRight(word2, 61) xor (word2 ushr 6))
            wordIndex++
        }

        var a = state0
        var b = state1
        var c = state2
        var d = state3
        var e = state4
        var f = state5
        var g = state6
        var h = state7
        var round = 0
        while (round < 80) {
            val sigma1 = rotateRight(e, 14) xor rotateRight(e, 18) xor rotateRight(e, 41)
            val choose = (e and f) xor (e.inv() and g)
            val temp1 = h + sigma1 + choose + SHA512_K[round] + words[round]
            val sigma0 = rotateRight(a, 28) xor rotateRight(a, 34) xor rotateRight(a, 39)
            val majority = (a and b) xor (a and c) xor (b and c)
            val temp2 = sigma0 + majority
            h = g
            g = f
            f = e
            e = d + temp1
            d = c
            c = b
            b = a
            a = temp1 + temp2
            round++
        }
        state0 += a
        state1 += b
        state2 += c
        state3 += d
        state4 += e
        state5 += f
        state6 += g
        state7 += h
        block += 128
    }

    val result = ByteArray(outputLength)
    val state = longArrayOf(state0, state1, state2, state3, state4, state5, state6, state7)
    var outIndex = 0
    while (outIndex < outputLength) {
        val wordIndex = outIndex / 8
        val byteInWord = outIndex % 8
        result[outIndex] = (state[wordIndex] ushr ((7 - byteInWord) * 8)).toByte()
        outIndex++
    }
    return result
}

// MARK: - MD2 (RFC 1319)

// 256-byte permutation constructed from the digits of pi.
private val MD2_S = intArrayOf(
    41, 46, 67, 201, 162, 216, 124, 1, 61, 54, 84, 161, 236, 240, 6, 19,
    98, 167, 5, 243, 192, 199, 115, 140, 152, 147, 43, 217, 188, 76, 130, 202,
    30, 155, 87, 60, 253, 212, 224, 22, 103, 66, 111, 24, 138, 23, 229, 18,
    190, 78, 196, 214, 218, 158, 222, 73, 160, 251, 245, 142, 187, 47, 238, 122,
    169, 104, 121, 145, 21, 178, 7, 63, 148, 194, 16, 137, 11, 34, 95, 33,
    128, 127, 93, 154, 90, 144, 50, 39, 53, 62, 204, 231, 191, 247, 151, 3,
    255, 25, 48, 179, 72, 165, 181, 209, 215, 94, 146, 42, 172, 86, 170, 198,
    79, 184, 56, 210, 150, 164, 125, 182, 118, 252, 107, 226, 156, 116, 4, 241,
    69, 157, 112, 89, 100, 113, 135, 32, 134, 91, 207, 101, 230, 45, 168, 2,
    27, 96, 37, 173, 174, 176, 185, 246, 28, 70, 97, 105, 52, 64, 126, 15,
    85, 71, 163, 35, 221, 81, 175, 58, 195, 92, 249, 206, 186, 197, 234, 38,
    44, 83, 13, 110, 133, 40, 132, 9, 211, 223, 205, 244, 65, 129, 77, 82,
    106, 220, 55, 200, 108, 193, 171, 250, 36, 225, 123, 8, 12, 189, 177, 74,
    120, 136, 149, 139, 227, 99, 232, 109, 233, 203, 213, 254, 59, 0, 29, 57,
    242, 239, 183, 14, 102, 88, 208, 228, 166, 119, 114, 248, 235, 117, 75, 10,
    49, 68, 80, 180, 143, 237, 31, 26, 219, 153, 141, 51, 159, 17, 131, 20
)

private fun md2(input: ByteArray): ByteArray {
    // Pad with i bytes of value i until the length is a multiple of 16;
    // padding is always applied (1..16 bytes).
    val padLength = 16 - (input.size % 16)
    val paddedLength = input.size + padLength
    val padded = ByteArray(paddedLength)
    input.copyInto(padded)
    var padIndex = 0
    while (padIndex < padLength) {
        padded[input.size + padIndex] = padLength.toByte()
        padIndex++
    }

    // 16-byte checksum over the padded message.
    val checksum = IntArray(16)
    var offset = 0
    while (offset < paddedLength) {
        var l = checksum[15]
        var j = 0
        while (j < 16) {
            checksum[j] = checksum[j] xor MD2_S[(padded[offset + j].toInt() and 0xFF) xor l]
            l = checksum[j]
            j++
        }
        offset += 16
    }

    val x = IntArray(48)
    offset = 0
    while (offset < paddedLength) {
        md2Block(x, padded, offset)
        offset += 16
    }
    val checksumBytes = ByteArray(16)
    padIndex = 0
    while (padIndex < 16) {
        checksumBytes[padIndex] = checksum[padIndex].toByte()
        padIndex++
    }
    md2Block(x, checksumBytes, 0)

    val result = ByteArray(16)
    padIndex = 0
    while (padIndex < 16) {
        result[padIndex] = x[padIndex].toByte()
        padIndex++
    }
    return result
}

private fun md2Block(x: IntArray, block: ByteArray, offset: Int) {
    var i = 0
    while (i < 16) {
        x[16 + i] = block[offset + i].toInt() and 0xFF
        x[32 + i] = x[16 + i] xor x[i]
        i++
    }
    var t = 0
    var j = 0
    while (j < 18) {
        var k = 0
        while (k < 48) {
            x[k] = x[k] xor MD2_S[t]
            t = x[k]
            k++
        }
        t = (t + j) % 256
        j++
    }
}

// MARK: - SHA-3 family (FIPS 202)

// Keccak-f[1600] round constants (RC) and rotation offsets indexed as
// lane = x + 5 * y.
private val KECCAK_ROUND_CONSTANTS = longArrayOf(
    0x0000000000000001uL.toLong(), 0x0000000000008082uL.toLong(),
    0x800000000000808auL.toLong(), 0x8000000080008000uL.toLong(),
    0x000000000000808buL.toLong(), 0x0000000080000001uL.toLong(),
    0x8000000080008081uL.toLong(), 0x8000000000008009uL.toLong(),
    0x000000000000008auL.toLong(), 0x0000000000000088uL.toLong(),
    0x0000000080008009uL.toLong(), 0x000000008000000auL.toLong(),
    0x000000008000808buL.toLong(), 0x800000000000008buL.toLong(),
    0x8000000000008089uL.toLong(), 0x8000000000008003uL.toLong(),
    0x8000000000008002uL.toLong(), 0x8000000000000080uL.toLong(),
    0x000000000000800auL.toLong(), 0x800000008000000auL.toLong(),
    0x8000000080008081uL.toLong(), 0x8000000000008080uL.toLong(),
    0x0000000080000001uL.toLong(), 0x8000000080008008uL.toLong()
)

private val KECCAK_ROTATION_OFFSETS = intArrayOf(
    0, 1, 62, 28, 27,
    36, 44, 6, 55, 20,
    3, 10, 43, 25, 39,
    41, 45, 15, 21, 8,
    18, 2, 61, 56, 14
)

private fun keccakF1600(state: LongArray, scratch: LongArray) {
    var round = 0
    while (round < 24) {
        // Theta: column parities and the D offsets.
        var x = 0
        while (x < 5) {
            scratch[x] = state[x] xor state[x + 5] xor state[x + 10] xor
                state[x + 15] xor state[x + 20]
            x++
        }
        x = 0
        while (x < 5) {
            val d = scratch[(x + 4) % 5] xor rotateLeft(scratch[(x + 1) % 5], 1)
            var y = 0
            while (y < 5) {
                state[x + 5 * y] = state[x + 5 * y] xor d
                y++
            }
            x++
        }
        // Rho + Pi: rotated lanes permuted to their new positions.
        x = 0
        while (x < 5) {
            var y = 0
            while (y < 5) {
                val newX = y
                val newY = (2 * x + 3 * y) % 5
                scratch[newX + 5 * newY] =
                    rotateLeft(state[x + 5 * y], KECCAK_ROTATION_OFFSETS[x + 5 * y])
                y++
            }
            x++
        }
        // Chi: nonlinear row mixing.
        x = 0
        while (x < 5) {
            var y = 0
            while (y < 5) {
                state[x + 5 * y] = scratch[x + 5 * y] xor
                    (scratch[((x + 1) % 5) + 5 * y].inv() and
                        scratch[((x + 2) % 5) + 5 * y])
                y++
            }
            x++
        }
        // Iota: round constant into lane (0, 0).
        state[0] = state[0] xor KECCAK_ROUND_CONSTANTS[round]
        round++
    }
}

// SHA-3 (FIPS 202) uses the 0x06 delimited suffix; SHAKE128/SHAKE256 are
// extendable-output functions on the same Keccak-f[1600] permutation and
// pad10*1 padding but use the 0x1F suffix. Through java.security.MessageDigest
// the JDK exposes SHAKE with a fixed default digest length (32/64 bytes), so
// no streaming squeeze state is needed: each digest() finalizes and resets
// exactly like the SHA-3 variants. All SHA-3/SHAKE output lengths fit inside
// a single rate block, but the squeeze loop is written generally anyway.
private fun sha3(input: ByteArray, rate: Int, outputLength: Int): ByteArray =
    keccakDigest(input, rate, outputLength, 0x06)

private fun shake(input: ByteArray, rate: Int, outputLength: Int): ByteArray =
    keccakDigest(input, rate, outputLength, 0x1F)

private fun keccakDigest(input: ByteArray, rate: Int, outputLength: Int, suffix: Int): ByteArray {
    val paddedLength = (input.size / rate + 1) * rate
    val padded = ByteArray(paddedLength)
    input.copyInto(padded)
    padded[input.size] = suffix.toByte()
    padded[paddedLength - 1] = (padded[paddedLength - 1].toInt() or 0x80).toByte()

    val state = LongArray(25)
    val scratch = LongArray(25)
    val laneCount = rate / 8
    var offset = 0
    while (offset < paddedLength) {
        var lane = 0
        while (lane < laneCount) {
            val base = offset + lane * 8
            state[lane] = state[lane] xor
                ((padded[base].toLong() and 0xFFL) or
                    ((padded[base + 1].toLong() and 0xFFL) shl 8) or
                    ((padded[base + 2].toLong() and 0xFFL) shl 16) or
                    ((padded[base + 3].toLong() and 0xFFL) shl 24) or
                    ((padded[base + 4].toLong() and 0xFFL) shl 32) or
                    ((padded[base + 5].toLong() and 0xFFL) shl 40) or
                    ((padded[base + 6].toLong() and 0xFFL) shl 48) or
                    ((padded[base + 7].toLong() and 0xFFL) shl 56))
            lane++
        }
        keccakF1600(state, scratch)
        offset += rate
    }

    val result = ByteArray(outputLength)
    var produced = 0
    var position = 0
    while (produced < outputLength) {
        if (position == rate) {
            keccakF1600(state, scratch)
            position = 0
        }
        result[produced] = (state[position / 8] ushr ((position % 8) * 8)).toByte()
        produced++
        position++
    }
    return result
}
