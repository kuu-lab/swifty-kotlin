package java.math

import java.util.Random

public class BigInteger : Number(), Comparable<BigInteger> {
    private val decimalValue: String

    public companion object {
        public val ZERO: BigInteger = BigInteger("0")
        public val ONE: BigInteger = BigInteger("1")
        public val TWO: BigInteger = BigInteger("2")
        public val TEN: BigInteger = BigInteger("10")

        public fun valueOf(value: Long): BigInteger = BigInteger(value.toString())

        public fun probablePrime(bitLength: Int, random: Random): BigInteger =
            BigInteger(randomPrimeDecimal(bitLength, random))
    }

    public constructor(value: String) {
        decimalValue = canonicalDecimal(value, 10)
    }

    public constructor(value: String, radix: Int) {
        decimalValue = canonicalDecimal(value, radix)
    }

    public constructor(magnitude: ByteArray) {
        decimalValue = twosComplementToDecimal(magnitude)
    }

    public constructor(signum: Int, magnitude: ByteArray) {
        decimalValue = signMagnitudeToDecimal(signum, magnitude)
    }

    public constructor(numBits: Int, random: Random) {
        decimalValue = randomMagnitudeDecimal(numBits, random)
    }

    public constructor(bitLength: Int, certainty: Int, random: Random) {
        decimalValue = randomPrimeDecimal(bitLength, random)
    }

    public fun add(other: BigInteger): BigInteger {
        val leftNegative = decimalValue[0] == '-'
        val rightNegative = other.decimalValue[0] == '-'
        val leftMagnitude = magnitudeOf(decimalValue)
        val rightMagnitude = magnitudeOf(other.decimalValue)
        if (leftNegative == rightNegative) {
            val sum = addMagnitudes(leftMagnitude, rightMagnitude)
            if (sum == "0") {
                return ZERO
            }
            return BigInteger(if (leftNegative) "-" + sum else sum)
        }
        val order = compareMagnitudes(leftMagnitude, rightMagnitude)
        if (order == 0) {
            return ZERO
        }
        val difference = if (order > 0) {
            subtractMagnitudes(leftMagnitude, rightMagnitude)
        } else {
            subtractMagnitudes(rightMagnitude, leftMagnitude)
        }
        val negative = if (order > 0) leftNegative else rightNegative
        return BigInteger(if (negative) "-" + difference else difference)
    }

    public fun subtract(other: BigInteger): BigInteger = add(other.negate())

    public fun multiply(other: BigInteger): BigInteger {
        val leftNegative = decimalValue[0] == '-'
        val rightNegative = other.decimalValue[0] == '-'
        val leftStart = if (leftNegative) 1 else 0
        val rightStart = if (rightNegative) 1 else 0

        if ((decimalValue.length - leftStart == 1 && decimalValue[leftStart] == '0')
            || (other.decimalValue.length - rightStart == 1 && other.decimalValue[rightStart] == '0')
        ) {
            return ZERO
        }

        val product = multiplyDecimalDigits(decimalValue, leftStart, other.decimalValue, rightStart)
        val negative = leftNegative != rightNegative
        return BigInteger((if (negative) "-" else "") + product)
    }

    public fun divide(divisor: BigInteger): BigInteger {
        if (divisor.decimalValue == "0") {
            throw ArithmeticException("BigInteger divide by zero")
        }
        val quotient = divideMagnitudes(
            magnitudeOf(decimalValue),
            magnitudeOf(divisor.decimalValue)
        )[0]
        if (quotient == "0") {
            return ZERO
        }
        val negative = (decimalValue[0] == '-') != (divisor.decimalValue[0] == '-')
        return BigInteger(if (negative) "-" + quotient else quotient)
    }

    public fun remainder(divisor: BigInteger): BigInteger {
        if (divisor.decimalValue == "0") {
            throw ArithmeticException("BigInteger divide by zero")
        }
        val remainder = divideMagnitudes(
            magnitudeOf(decimalValue),
            magnitudeOf(divisor.decimalValue)
        )[1]
        if (remainder == "0") {
            return ZERO
        }
        return BigInteger(if (decimalValue[0] == '-') "-" + remainder else remainder)
    }

    public fun divideAndRemainder(divisor: BigInteger): Array<BigInteger> {
        if (divisor.decimalValue == "0") {
            throw ArithmeticException("BigInteger divide by zero")
        }
        val results = divideMagnitudes(
            magnitudeOf(decimalValue),
            magnitudeOf(divisor.decimalValue)
        )
        val negative = (decimalValue[0] == '-') != (divisor.decimalValue[0] == '-')
        val quotient = if (results[0] == "0") ZERO else
            BigInteger(if (negative) "-" + results[0] else results[0])
        val remainder = if (results[1] == "0") ZERO else
            BigInteger(if (decimalValue[0] == '-') "-" + results[1] else results[1])
        return arrayOf(quotient, remainder)
    }

    public fun mod(m: BigInteger): BigInteger {
        if (m.signum() <= 0) {
            throw ArithmeticException("BigInteger: modulus not positive")
        }
        val remainder = remainder(m)
        return if (remainder.signum() < 0) remainder.add(m) else remainder
    }

    public fun negate(): BigInteger {
        if (decimalValue == "0") {
            return this
        }
        return if (decimalValue[0] == '-') {
            BigInteger(decimalValue.substring(1))
        } else {
            BigInteger("-" + decimalValue)
        }
    }

    public fun abs(): BigInteger =
        if (decimalValue[0] == '-') BigInteger(decimalValue.substring(1)) else this

    public fun signum(): Int =
        if (decimalValue == "0") 0 else if (decimalValue[0] == '-') -1 else 1

    public fun min(other: BigInteger): BigInteger =
        if (compareTo(other) <= 0) this else other

    public fun max(other: BigInteger): BigInteger =
        if (compareTo(other) >= 0) this else other

    public fun pow(exponent: Int): BigInteger {
        if (exponent < 0) {
            throw ArithmeticException("Negative exponent")
        }
        var result = ONE
        var factor = this
        var remaining = exponent
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

    public fun gcd(other: BigInteger): BigInteger {
        var left = magnitudeOf(decimalValue)
        var right = magnitudeOf(other.decimalValue)
        while (right != "0") {
            val remainder = divideMagnitudes(left, right)[1]
            left = right
            right = remainder
        }
        return BigInteger(left)
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
                return ZERO
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

    public fun shiftRight(n: Int): BigInteger = shiftLeft(-n)

    public fun andNot(other: BigInteger): BigInteger = and(other.not())

    public fun not(): BigInteger = negate().subtract(ONE)

    public fun inv(): BigInteger = not()

    public fun testBit(n: Int): Boolean {
        if (n < 0) {
            throw ArithmeticException("Negative bit address")
        }
        val width = maxOf(bitLength(), n) + 2
        return twosComplementBits(width)[n] == 1
    }

    public fun setBit(n: Int): BigInteger {
        if (n < 0) {
            throw ArithmeticException("Negative bit address")
        }
        val bits = twosComplementBits(maxOf(bitLength(), n) + 2)
        bits[n] = 1
        return BigInteger(signedBitsToDecimal(bits))
    }

    public fun clearBit(n: Int): BigInteger {
        if (n < 0) {
            throw ArithmeticException("Negative bit address")
        }
        val bits = twosComplementBits(maxOf(bitLength(), n) + 2)
        bits[n] = 0
        return BigInteger(signedBitsToDecimal(bits))
    }

    public fun flipBit(n: Int): BigInteger {
        if (n < 0) {
            throw ArithmeticException("Negative bit address")
        }
        val bits = twosComplementBits(maxOf(bitLength(), n) + 2)
        bits[n] = 1 - bits[n]
        return BigInteger(signedBitsToDecimal(bits))
    }

    public fun bitLength(): Int {
        val magnitude = magnitudeOf(decimalValue)
        if (decimalValue[0] != '-') {
            return magnitudeToBits(magnitude).size
        }
        return magnitudeToBits(subtractMagnitudes(magnitude, "1")).size
    }

    public fun bitCount(): Int {
        val magnitude = magnitudeOf(decimalValue)
        val bits = if (decimalValue[0] != '-') {
            magnitudeToBits(magnitude)
        } else {
            magnitudeToBits(subtractMagnitudes(magnitude, "1"))
        }
        var count = 0
        var index = 0
        while (index < bits.size) {
            count += bits[index]
            index++
        }
        return count
    }

    // Java exposes getLowestSetBit() as the lowestSetBit property to Kotlin callers.
    public val lowestSetBit: Int
        get() = getLowestSetBit()

    public fun getLowestSetBit(): Int {
        if (decimalValue == "0") {
            return -1
        }
        val bits = magnitudeToBits(magnitudeOf(decimalValue))
        var index = 0
        while (index < bits.size) {
            if (bits[index] == 1) {
                return index
            }
            index++
        }
        return -1
    }

    public fun modPow(exponent: BigInteger, m: BigInteger): BigInteger {
        if (m.signum() <= 0) {
            throw ArithmeticException("BigInteger: modulus not positive")
        }
        if (exponent.signum() < 0) {
            return modInverse(m).modPow(exponent.negate(), m)
        }
        val exponentBits = magnitudeToBits(magnitudeOf(exponent.decimalValue))
        var result = ONE.mod(m)
        var base = mod(m)
        var index = 0
        while (index < exponentBits.size) {
            if (exponentBits[index] == 1) {
                result = result.multiply(base).mod(m)
            }
            if (index + 1 < exponentBits.size) {
                base = base.multiply(base).mod(m)
            }
            index++
        }
        return result
    }

    public fun modInverse(m: BigInteger): BigInteger {
        if (m.signum() <= 0) {
            throw ArithmeticException("BigInteger: modulus not positive")
        }
        var previousRemainder = m
        var remainder = mod(m)
        var previousCoefficient = ZERO
        var coefficient = ONE
        while (remainder.signum() != 0) {
            val quotient = previousRemainder.divide(remainder)
            val nextRemainder = previousRemainder.subtract(quotient.multiply(remainder))
            val nextCoefficient = previousCoefficient.subtract(quotient.multiply(coefficient))
            previousRemainder = remainder
            remainder = nextRemainder
            previousCoefficient = coefficient
            coefficient = nextCoefficient
        }
        if (previousRemainder != ONE) {
            throw ArithmeticException("BigInteger is not invertible.")
        }
        return previousCoefficient.mod(m)
    }

    public fun isProbablePrime(certainty: Int): Boolean {
        if (certainty <= 0) {
            return true
        }
        // The JVM reports primality of the absolute value.
        val n = abs()
        if (n.compareTo(TWO) < 0) {
            return false
        }
        val smallPrimes = intArrayOf(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37)
        var index = 0
        while (index < smallPrimes.size) {
            val prime = valueOf(smallPrimes[index].toLong())
            if (n == prime) {
                return true
            }
            if (n.remainder(prime).signum() == 0) {
                return false
            }
            index++
        }
        // Any composite below 41^2 has a factor in the sieved primes.
        if (n.compareTo(valueOf(1681L)) < 0) {
            return true
        }
        val reduced = n.subtract(ONE)
        val shiftCount = reduced.getLowestSetBit()
        val oddPart = reduced.shiftRight(shiftCount)
        val bases = intArrayOf(2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53)
        var baseIndex = 0
        while (baseIndex < bases.size) {
            val base = valueOf(bases[baseIndex].toLong())
            var witness = base.modPow(oddPart, n)
            if (witness != ONE && witness != reduced) {
                var round = 1
                var composite = true
                while (round < shiftCount) {
                    witness = witness.multiply(witness).mod(n)
                    if (witness == reduced) {
                        composite = false
                        break
                    }
                    round++
                }
                if (composite) {
                    return false
                }
            }
            baseIndex++
        }
        return true
    }

    public fun nextProbablePrime(): BigInteger {
        if (signum() < 0) {
            throw ArithmeticException("start < 0: " + decimalValue)
        }
        if (compareTo(TWO) < 0) {
            return TWO
        }
        var candidate = if (testBit(0)) add(TWO) else add(ONE)
        while (!candidate.isProbablePrime(100)) {
            candidate = candidate.add(TWO)
        }
        return candidate
    }

    public fun sqrt(): BigInteger {
        if (signum() < 0) {
            throw ArithmeticException("Negative BigInteger")
        }
        if (signum() == 0) {
            return ZERO
        }
        var estimate = ONE.shiftLeft((bitLength() + 1) / 2)
        while (true) {
            val next = estimate.add(divide(estimate)).shiftRight(1)
            if (next.compareTo(estimate) >= 0) {
                return estimate
            }
            estimate = next
        }
    }

    public fun sqrtAndRemainder(): Array<BigInteger> {
        val root = sqrt()
        return arrayOf(root, subtract(root.multiply(root)))
    }

    public fun toByteArray(): ByteArray {
        val byteCount = (bitLength() + 8) / 8
        val bits = twosComplementBits(byteCount * 8)
        val result = ByteArray(byteCount)
        var index = 0
        while (index < byteCount) {
            var value = 0
            var bit = 0
            while (bit < 8) {
                value = value or (bits[(byteCount - 1 - index) * 8 + bit] shl bit)
                bit++
            }
            result[index] = value.toByte()
            index++
        }
        return result
    }

    public fun byteValue(): Byte = toByte()

    public fun shortValue(): Short = toShort()

    public fun intValue(): Int = toInt()

    public fun longValue(): Long = toLong()

    public fun floatValue(): Float = toFloat()

    public fun doubleValue(): Double = toDouble()

    public fun byteValueExact(): Byte {
        if (compareTo(valueOf(Byte.MAX_VALUE.toLong())) > 0
            || compareTo(valueOf(Byte.MIN_VALUE.toLong())) < 0
        ) {
            throw ArithmeticException("BigInteger out of byte range")
        }
        return toByte()
    }

    public fun shortValueExact(): Short {
        if (compareTo(valueOf(Short.MAX_VALUE.toLong())) > 0
            || compareTo(valueOf(Short.MIN_VALUE.toLong())) < 0
        ) {
            throw ArithmeticException("BigInteger out of short range")
        }
        return toShort()
    }

    public fun intValueExact(): Int {
        if (compareTo(valueOf(Int.MAX_VALUE.toLong())) > 0
            || compareTo(valueOf(Int.MIN_VALUE.toLong())) < 0
        ) {
            throw ArithmeticException("BigInteger out of int range")
        }
        return toInt()
    }

    public fun longValueExact(): Long {
        if (compareTo(valueOf(Long.MAX_VALUE)) > 0
            || compareTo(valueOf(Long.MIN_VALUE)) < 0
        ) {
            throw ArithmeticException("BigInteger out of long range")
        }
        return toLong()
    }

    public override fun toByte(): Byte = toLong().toByte()

    public override fun toShort(): Short = toLong().toShort()

    public override fun toInt(): Int = toLong().toInt()

    public override fun toLong(): Long {
        val bits = twosComplementBits(64)
        var value = 0L
        var index = 63
        while (index >= 0) {
            value = (value shl 1) or bits[index].toLong()
            index--
        }
        return value
    }

    public override fun toFloat(): Float = decimalValue.toFloat()

    public override fun toDouble(): Double = decimalValue.toDouble()

    public fun toString(radix: Int): String {
        val base = if (radix < 2 || radix > 36) 10 else radix
        if (base == 10) {
            return decimalValue
        }
        val magnitude = toRadixDigits(magnitudeOf(decimalValue), base)
        return if (decimalValue[0] == '-') "-" + magnitude else magnitude
    }

    public operator fun inc(): BigInteger = add(ONE)

    public operator fun dec(): BigInteger = subtract(ONE)

    public operator fun unaryMinus(): BigInteger = negate()

    public operator fun plus(other: BigInteger): BigInteger = add(other)

    public operator fun minus(other: BigInteger): BigInteger = subtract(other)

    public operator fun times(other: BigInteger): BigInteger = multiply(other)

    public operator fun div(other: BigInteger): BigInteger = divide(other)

    public operator fun rem(other: BigInteger): BigInteger = remainder(other)

    public infix fun shl(distance: Int): BigInteger = shiftLeft(distance)

    public infix fun shr(distance: Int): BigInteger = shiftRight(distance)

    public infix fun and(other: BigInteger): BigInteger = bitwise(other, 0)

    public infix fun or(other: BigInteger): BigInteger = bitwise(other, 1)

    public infix fun xor(other: BigInteger): BigInteger = bitwise(other, 2)

    public override fun compareTo(other: BigInteger): Int {
        val leftSign = signum()
        val rightSign = other.signum()
        if (leftSign != rightSign) {
            return if (leftSign < rightSign) -1 else 1
        }
        if (leftSign == 0) {
            return 0
        }
        val order = compareMagnitudes(
            magnitudeOf(decimalValue),
            magnitudeOf(other.decimalValue)
        )
        return if (leftSign > 0) order else -order
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

    private fun bitwise(other: BigInteger, operation: Int): BigInteger {
        val width = maxOf(bitLength(), other.bitLength()) + 1
        val left = twosComplementBits(width)
        val right = other.twosComplementBits(width)
        val result = IntArray(width)
        var index = 0
        while (index < width) {
            result[index] = if (operation == 0) {
                left[index] and right[index]
            } else if (operation == 1) {
                left[index] or right[index]
            } else {
                left[index] xor right[index]
            }
            index++
        }
        return BigInteger(signedBitsToDecimal(result))
    }

    private fun twosComplementBits(width: Int): IntArray {
        val magnitude = magnitudeOf(decimalValue)
        val magnitudeBits = magnitudeToBits(magnitude)
        val bits = IntArray(width)
        var index = 0
        while (index < magnitudeBits.size && index < width) {
            bits[index] = magnitudeBits[index]
            index++
        }
        if (decimalValue[0] != '-') {
            return bits
        }
        index = 0
        while (index < width) {
            bits[index] = 1 - bits[index]
            index++
        }
        var carry = 1
        index = 0
        while (index < width && carry != 0) {
            val value = bits[index] + carry
            bits[index] = value and 1
            carry = value shr 1
            index++
        }
        return bits
    }
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

private fun canonicalDecimal(value: String, radix: Int): String {
    if (value.isEmpty()) {
        throw NumberFormatException("Zero length BigInteger")
    }
    var start = 0
    var negative = false
    if (value[0] == '-') {
        negative = true
        start = 1
    } else if (value[0] == '+') {
        start = 1
    }
    if (start == value.length) {
        throw NumberFormatException("Zero length BigInteger")
    }
    if (radix == 10) {
        var firstDigit = start
        while (firstDigit < value.length && value[firstDigit] == '0') {
            firstDigit++
        }
        var index = firstDigit
        while (index < value.length) {
            val digit = value[index]
            if (digit < '0' || digit > '9') {
                throw NumberFormatException("Illegal digit")
            }
            index++
        }
        if (firstDigit == value.length) {
            return "0"
        }
        return if (negative) "-" + value.substring(firstDigit) else value.substring(firstDigit)
    }
    if (radix < 2 || radix > 36) {
        throw NumberFormatException("Radix out of range")
    }
    val digits = IntArray(value.length * 2 + 2)
    var length = 0
    var index = start
    while (index < value.length) {
        val digit = digitValue(value[index])
        if (digit < 0 || digit >= radix) {
            throw NumberFormatException("Illegal digit")
        }
        var carry = digit
        var digitIndex = 0
        while (digitIndex < length) {
            val accumulated = digits[digitIndex] * radix + carry
            digits[digitIndex] = accumulated % 10
            carry = accumulated / 10
            digitIndex++
        }
        while (carry != 0) {
            digits[length] = carry % 10
            carry /= 10
            length++
        }
        index++
    }
    val magnitude = digitsToMagnitude(digits, length)
    return if (negative && magnitude != "0") "-" + magnitude else magnitude
}

private fun digitValue(digit: Char): Int {
    if (digit >= '0' && digit <= '9') {
        return digit.code - '0'.code
    }
    if (digit >= 'a' && digit <= 'z') {
        return digit.code - 'a'.code + 10
    }
    if (digit >= 'A' && digit <= 'Z') {
        return digit.code - 'A'.code + 10
    }
    return -1
}

private fun magnitudeOf(value: String): String =
    if (value[0] == '-') value.substring(1) else value

private fun canonicalMagnitude(value: String): String {
    var firstDigit = 0
    while (firstDigit < value.length && value[firstDigit] == '0') {
        firstDigit++
    }
    return if (firstDigit == value.length) "0" else value.substring(firstDigit)
}

private fun compareMagnitudes(first: String, second: String): Int {
    if (first.length != second.length) {
        return if (first.length < second.length) -1 else 1
    }
    var index = 0
    while (index < first.length) {
        if (first[index] != second[index]) {
            return if (first[index] < second[index]) -1 else 1
        }
        index++
    }
    return 0
}

private fun addMagnitudes(first: String, second: String): String {
    val digits = CharArray(maxOf(first.length, second.length) + 1)
    var firstIndex = first.length - 1
    var secondIndex = second.length - 1
    var carry = 0
    var length = 0
    while (firstIndex >= 0 || secondIndex >= 0 || carry != 0) {
        var sum = carry
        if (firstIndex >= 0) {
            sum += first[firstIndex].code - '0'.code
            firstIndex--
        }
        if (secondIndex >= 0) {
            sum += second[secondIndex].code - '0'.code
            secondIndex--
        }
        digits[length] = ('0'.code + sum % 10).toChar()
        carry = sum / 10
        length++
    }
    val result = CharArray(length)
    var index = 0
    while (index < length) {
        result[index] = digits[length - 1 - index]
        index++
    }
    return result.concatToString()
}

private fun subtractMagnitudes(first: String, second: String): String {
    val digits = CharArray(first.length)
    var firstIndex = first.length - 1
    var secondIndex = second.length - 1
    var borrow = 0
    var length = 0
    while (firstIndex >= 0) {
        var difference = first[firstIndex].code - '0'.code - borrow
        if (secondIndex >= 0) {
            difference -= second[secondIndex].code - '0'.code
            secondIndex--
        }
        if (difference < 0) {
            difference += 10
            borrow = 1
        } else {
            borrow = 0
        }
        digits[length] = ('0'.code + difference).toChar()
        length++
        firstIndex--
    }
    while (length > 1 && digits[length - 1] == '0') {
        length--
    }
    val result = CharArray(length)
    var index = 0
    while (index < length) {
        result[index] = digits[length - 1 - index]
        index++
    }
    return result.concatToString()
}

private fun multiplyByDigit(magnitude: String, digit: Int): String {
    if (digit == 0 || magnitude == "0") {
        return "0"
    }
    val digits = CharArray(magnitude.length + 1)
    var index = magnitude.length - 1
    var carry = 0
    var length = 0
    while (index >= 0) {
        val value = (magnitude[index].code - '0'.code) * digit + carry
        digits[length] = ('0'.code + value % 10).toChar()
        carry = value / 10
        length++
        index--
    }
    if (carry != 0) {
        digits[length] = ('0'.code + carry).toChar()
        length++
    }
    val result = CharArray(length)
    var resultIndex = 0
    while (resultIndex < length) {
        result[resultIndex] = digits[length - 1 - resultIndex]
        resultIndex++
    }
    return result.concatToString()
}

private fun divideMagnitudes(dividend: String, divisor: String): Array<String> {
    if (compareMagnitudes(dividend, divisor) < 0) {
        return arrayOf("0", dividend)
    }
    var remainder = "0"
    val quotient = CharArray(dividend.length)
    var quotientLength = 0
    var index = 0
    while (index < dividend.length) {
        remainder = if (remainder == "0") {
            dividend[index].toString()
        } else {
            remainder + dividend[index].toString()
        }
        var low = 0
        var high = 9
        var digit = 0
        while (low <= high) {
            val mid = (low + high) / 2
            if (compareMagnitudes(multiplyByDigit(divisor, mid), remainder) <= 0) {
                digit = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        quotient[quotientLength] = ('0'.code + digit).toChar()
        quotientLength++
        if (digit != 0) {
            remainder = subtractMagnitudes(remainder, multiplyByDigit(divisor, digit))
        }
        index++
    }
    val result = CharArray(quotientLength)
    var resultIndex = 0
    while (resultIndex < quotientLength) {
        result[resultIndex] = quotient[resultIndex]
        resultIndex++
    }
    return arrayOf(canonicalMagnitude(result.concatToString()), remainder)
}

private fun digitsToMagnitude(digits: IntArray, length: Int): String {
    var resultLength = length
    while (resultLength > 0 && digits[resultLength - 1] == 0) {
        resultLength--
    }
    if (resultLength == 0) {
        return "0"
    }
    val result = CharArray(resultLength)
    var index = 0
    while (index < resultLength) {
        result[index] = ('0'.code + digits[resultLength - 1 - index]).toChar()
        index++
    }
    return result.concatToString()
}

private fun magnitudeToBits(magnitude: String): IntArray {
    if (magnitude == "0") {
        return IntArray(0)
    }
    val digits = decimalMagnitudeDigits(magnitude, 0)
    var length = magnitude.length
    val bits = IntArray(length * 4)
    var count = 0
    while (length > 0) {
        bits[count] = digits[0] and 1
        count++
        length = halveDecimalMagnitude(digits, length)
    }
    return bits.copyOf(count)
}

private fun bitsToMagnitude(bits: IntArray): String {
    val digits = IntArray(bits.size / 3 + 2)
    var length = 0
    var index = bits.size - 1
    while (index >= 0) {
        var carry = bits[index]
        var digitIndex = 0
        while (digitIndex < length) {
            val value = digits[digitIndex] * 2 + carry
            digits[digitIndex] = value % 10
            carry = value / 10
            digitIndex++
        }
        while (carry != 0) {
            digits[length] = carry % 10
            carry /= 10
            length++
        }
        index--
    }
    return digitsToMagnitude(digits, length)
}

private fun signedBitsToDecimal(bits: IntArray): String {
    if (bits.isEmpty() || bits[bits.size - 1] == 0) {
        return bitsToMagnitude(bits)
    }
    val inverted = IntArray(bits.size)
    var index = 0
    while (index < bits.size) {
        inverted[index] = 1 - bits[index]
        index++
    }
    var carry = 1
    index = 0
    while (index < inverted.size && carry != 0) {
        val value = inverted[index] + carry
        inverted[index] = value and 1
        carry = value shr 1
        index++
    }
    val magnitude = bitsToMagnitude(inverted)
    return if (magnitude == "0") "0" else "-" + magnitude
}

private fun twosComplementToDecimal(bytes: ByteArray): String {
    if (bytes.isEmpty()) {
        throw NumberFormatException("Zero length BigInteger")
    }
    val bits = IntArray(bytes.size * 8)
    var index = 0
    while (index < bits.size) {
        val byte = bytes[bytes.size - 1 - index / 8].toInt()
        bits[index] = (byte ushr (index % 8)) and 1
        index++
    }
    return signedBitsToDecimal(bits)
}

private fun signMagnitudeToDecimal(signum: Int, magnitude: ByteArray): String {
    if (signum < -1 || signum > 1) {
        throw NumberFormatException("Invalid signum value")
    }
    val bits = IntArray(magnitude.size * 8)
    var index = 0
    while (index < bits.size) {
        val byte = magnitude[magnitude.size - 1 - index / 8].toInt()
        bits[index] = (byte ushr (index % 8)) and 1
        index++
    }
    val result = bitsToMagnitude(bits)
    if (result == "0") {
        return "0"
    }
    if (signum == 0) {
        throw NumberFormatException("signum-magnitude mismatch")
    }
    return if (signum < 0) "-" + result else result
}

private fun randomMagnitudeDecimal(numBits: Int, random: Random): String {
    if (numBits < 0) {
        throw IllegalArgumentException("numBits must be non-negative")
    }
    val bits = IntArray(numBits)
    var produced = 0
    while (produced < numBits) {
        val count = minOf(32, numBits - produced)
        val chunk = random.delegate.nextBits(count)
        var index = 0
        while (index < count) {
            bits[produced + index] = (chunk ushr index) and 1
            index++
        }
        produced += count
    }
    return bitsToMagnitude(bits)
}

private fun randomPrimeDecimal(bitLength: Int, random: Random): String {
    if (bitLength < 2) {
        throw ArithmeticException("bitLength < 2")
    }
    while (true) {
        val bits = IntArray(bitLength)
        var produced = 0
        while (produced < bitLength) {
            val count = minOf(32, bitLength - produced)
            val chunk = random.delegate.nextBits(count)
            var index = 0
            while (index < count) {
                bits[produced + index] = (chunk ushr index) and 1
                index++
            }
            produced += count
        }
        bits[0] = 1
        bits[bitLength - 1] = 1
        val candidate = BigInteger(bitsToMagnitude(bits))
        if (candidate.isProbablePrime(100)) {
            return candidate.toString()
        }
    }
}

private fun toRadixDigits(magnitude: String, radix: Int): String {
    if (magnitude == "0") {
        return "0"
    }
    val digits = decimalMagnitudeDigits(magnitude, 0)
    var length = magnitude.length
    val alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    val chars = CharArray(magnitude.length * 4)
    var count = 0
    while (length > 0) {
        var carry = 0
        var index = length - 1
        while (index >= 0) {
            val value = carry * 10 + digits[index]
            digits[index] = value / radix
            carry = value % radix
            index--
        }
        chars[count] = alphabet[carry]
        count++
        while (length > 0 && digits[length - 1] == 0) {
            length--
        }
    }
    val result = CharArray(count)
    var index = 0
    while (index < count) {
        result[index] = chars[count - 1 - index]
        index++
    }
    return result.concatToString()
}
