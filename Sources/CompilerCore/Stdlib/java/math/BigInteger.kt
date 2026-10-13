package java.math

public class BigInteger private constructor(private val decimalValue: String) {
    public companion object {
        public val ONE: BigInteger = BigInteger("1")

        public fun valueOf(value: Long): BigInteger = BigInteger(value.toString())
    }

    public fun multiply(other: BigInteger): BigInteger {
        val leftNegative = decimalValue[0] == '-'
        val rightNegative = other.decimalValue[0] == '-'
        val leftStart = if (leftNegative) 1 else 0
        val rightStart = if (rightNegative) 1 else 0

        if ((decimalValue.length - leftStart == 1 && decimalValue[leftStart] == '0')
            || (other.decimalValue.length - rightStart == 1 && other.decimalValue[rightStart] == '0')
        ) {
            return valueOf(0L)
        }

        val product = multiplyDecimalDigits(decimalValue, leftStart, other.decimalValue, rightStart)
        val negative = leftNegative != rightNegative
        return BigInteger((if (negative) "-" else "") + product)
    }

    public override fun equals(other: Any?): Boolean {
        if (other !is BigInteger) return false
        val that = other as BigInteger
        // All construction paths produce canonical signed decimal strings.
        return decimalValue == that.decimalValue
    }

    public override fun hashCode(): Int {
        val negative = decimalValue[0] == '-'
        var digitIndex = if (negative) 1 else 0
        // Convert the decimal magnitude to little-endian unsigned 32-bit words.
        val words = LongArray(decimalValue.length - digitIndex)
        var wordCount = 0
        while (digitIndex < decimalValue.length) {
            var carry = (decimalValue[digitIndex].code - '0'.code).toLong()
            var wordIndex = 0
            while (wordIndex < wordCount) {
                val value = words[wordIndex] * 10L + carry
                words[wordIndex] = value % 4294967296L
                carry = value / 4294967296L
                wordIndex++
            }
            if (carry != 0L) {
                words[wordCount] = carry
                wordCount++
            }
            digitIndex++
        }

        // Java BigInteger hashes magnitude words from most significant to least.
        var hash = 0
        var wordIndex = wordCount - 1
        while (wordIndex >= 0) {
            hash = (31L * hash.toLong() + words[wordIndex]).toInt()
            wordIndex--
        }
        return if (negative) -hash else hash
    }

    override fun toString(): String = decimalValue
}

private fun multiplyDecimalDigits(
    first: String,
    firstStart: Int,
    second: String,
    secondStart: Int
): String {
    val firstLength = first.length - firstStart
    val secondLength = second.length - secondStart
    val digits = IntArray(firstLength + secondLength)
    var firstIndex = firstLength - 1
    while (firstIndex >= 0) {
        val firstDigit = first[firstStart + firstIndex].code - '0'.code
        var carry = 0
        var secondIndex = secondLength - 1
        while (secondIndex >= 0) {
            val resultIndex = firstIndex + secondIndex + 1
            val value = digits[resultIndex]
                + firstDigit * (second[secondStart + secondIndex].code - '0'.code)
                + carry
            digits[resultIndex] = value % 10
            carry = value / 10
            secondIndex--
        }
        digits[firstIndex] += carry
        firstIndex--
    }

    var firstNonZero = 0
    while (firstNonZero < digits.size - 1 && digits[firstNonZero] == 0) {
        firstNonZero++
    }

    var result = ""
    while (firstNonZero < digits.size) {
        result += digits[firstNonZero].toString()
        firstNonZero++
    }
    return result
}
