package java.math

public class BigInteger private constructor(private val decimalValue: String) {
    public companion object {
        public val ZERO: BigInteger = BigInteger("0")
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
    /**
     * Shifts exactly, reversing direction for negative distances.
     * Results outside (-2^Int.MAX_VALUE, 2^Int.MAX_VALUE) throw ArithmeticException.
     */
    public fun shiftLeft(n: Int): BigInteger {
        if (n == 0 || decimalValue == "0") {
            return this
        }
        val negative = decimalValue[0] == '-'
        val start = if (negative) 1 else 0
        if (n < 0) {
            val digits = decimalMagnitudeDigits(decimalValue, start)
            var length = decimalValue.length - start
            // Widen before negating: Int.MIN_VALUE is a valid right-shift distance.
            var remaining = -n.toLong()
            var discarded = false
            while (remaining > 0L && length > 0) {
                if (digits[0] % 2 != 0) {
                    discarded = true
                }
                length = halveDecimalMagnitude(digits, length)
                remaining--
            }
            // Arithmetic right shifts round negative values toward negative infinity.
            if (negative && discarded) {
                var index = 0
                while (index < length && digits[index] == 9) {
                    digits[index] = 0
                    index++
                }
                digits[index]++
                if (index == length) {
                    length++
                }
            }
            if (length == 0) {
                return valueOf(0L)
            }
            var result = if (negative) "-" else ""
            var index = length - 1
            while (index >= 0) {
                result += digits[index].toString()
                index--
            }
            return BigInteger(result)
        }

        // Four bits per decimal digit is a safe upper bound. Only values near
        // the supported boundary need an exact magnitude bit-length calculation.
        if (n.toLong() + (decimalValue.length - start).toLong() * 4L > Int.MAX_VALUE.toLong()) {
            val digits = decimalMagnitudeDigits(decimalValue, start)
            var length = decimalValue.length - start
            var bits = 0L
            while (length > 0) {
                length = halveDecimalMagnitude(digits, length)
                bits++
            }
            if (bits + n.toLong() > Int.MAX_VALUE.toLong()) {
                throw ArithmeticException("BigInteger would overflow supported range")
            }
        }
        var result = this
        var factor = valueOf(2L)
        var remaining = n
        while (remaining > 0) {
            if (remaining % 2 != 0) {
                result = result.multiply(factor)
            }
            remaining /= 2
            if (remaining > 0) {
                factor = factor.multiply(factor)
            }
        }
        return result
    }

    override fun toString(): String = decimalValue
}

// Little-endian decimal digits, with one spare slot for negative right-shift rounding.
private fun decimalMagnitudeDigits(value: String, start: Int): IntArray {
    val length = value.length - start
    val digits = IntArray(length + 1)
    var index = 0
    while (index < length) {
        digits[index] = value[value.length - index - 1].code - '0'.code
        index++
    }
    return digits
}

private fun halveDecimalMagnitude(digits: IntArray, length: Int): Int {
    var carry = 0
    var index = length - 1
    while (index >= 0) {
        val value = carry * 10 + digits[index]
        digits[index] = value / 2
        carry = value % 2
        index--
    }
    var resultLength = length
    while (resultLength > 0 && digits[resultLength - 1] == 0) {
        resultLength--
    }
    return resultLength
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
            val value = digits[resultIndex] +
                firstDigit * (second[secondStart + secondIndex].code - '0'.code) +
                carry
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
