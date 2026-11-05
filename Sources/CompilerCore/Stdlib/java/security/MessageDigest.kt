package java.security

/** Message digest facade over the algorithms used by the bundled JVM APIs. */
public class MessageDigest private constructor(public val algorithm: String) {
    private var input = ByteArray(0)
    private val normalizedAlgorithm = normalizeAlgorithmName(algorithm)

    public val digestLength: Int
        get() = if (normalizedAlgorithm == "SHA256") 32 else if (normalizedAlgorithm == "SHA1") 20 else 16

    public fun update(value: Byte) {
        update(byteArrayOf(value))
    }

    public fun update(data: ByteArray) {
        update(data, 0, data.size)
    }

    public fun update(data: ByteArray, offset: Int, length: Int) {
        if (offset < 0 || length < 0 || offset > data.size - length) {
            throw IndexOutOfBoundsException()
        }
        val combined = ByteArray(input.size + length)
        input.copyInto(combined)
        data.copyInto(combined, input.size, offset, offset + length)
        input = combined
    }

    public fun digest(): ByteArray {
        val result = if (normalizedAlgorithm == "SHA256") {
            sha256(input)
        } else if (normalizedAlgorithm == "SHA1") {
            sha1(input)
        } else {
            md5(input)
        }
        input = ByteArray(0)
        return result
    }

    public fun digest(data: ByteArray): ByteArray {
        update(data)
        return digest()
    }

    public fun digest(output: ByteArray, offset: Int, length: Int): Int {
        if (length < digestLength || offset < 0 || offset > output.size - digestLength) {
            throw IllegalArgumentException("output buffer is too small")
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
            if (normalized != "MD5" && normalized != "SHA1" && normalized != "SHA256") {
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

private fun sha256(input: ByteArray): ByteArray {
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

    var state0 = 0x6a09e667
    var state1 = 0xbb67ae85.toInt()
    var state2 = 0x3c6ef372
    var state3 = 0xa54ff53a.toInt()
    var state4 = 0x510e527f
    var state5 = 0x9b05688c.toInt()
    var state6 = 0x1f83d9ab
    var state7 = 0x5be0cd19
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

    val result = ByteArray(32)
    val state = intArrayOf(state0, state1, state2, state3, state4, state5, state6, state7)
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

private fun rotateLeft(value: Int, distance: Int): Int =
    (value shl distance) or (value ushr (32 - distance))

private fun rotateRight(value: Int, distance: Int): Int =
    (value ushr distance) or (value shl (32 - distance))

private fun normalizeAlgorithmName(algorithm: String): String {
    val normalized = algorithm.replace("-", "").uppercase()
    // The JDK accepts "SHA" as an alias for SHA-1.
    return if (normalized == "SHA") "SHA1" else normalized
}
