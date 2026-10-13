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
