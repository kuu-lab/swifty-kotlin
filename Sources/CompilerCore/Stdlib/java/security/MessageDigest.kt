package java.security

/** Message digest facade with the MD5 algorithm used by the bundled JVM APIs. */
public class MessageDigest private constructor(public val algorithm: String) {
    private var input = ByteArray(0)

    public val digestLength: Int
        get() = 16

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
        val result = md5(input)
        input = ByteArray(0)
        return result
    }

    public fun digest(data: ByteArray): ByteArray {
        reset()
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
            val normalized = algorithm.replace("-", "").uppercase()
            if (normalized != "MD5") throw NoSuchAlgorithmException(algorithm)
            return MessageDigest("MD5")
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

private fun rotateLeft(value: Int, distance: Int): Int =
    (value shl distance) or (value ushr (32 - distance))
