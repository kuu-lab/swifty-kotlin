package java.lang

import kotlin.internal.KsSymbolName
import kotlin.math.abs as kotlinAbs
import kotlin.math.acosh as kotlinAcosh
import kotlin.math.acos as kotlinAcos
import kotlin.math.asinh as kotlinAsinh
import kotlin.math.asin as kotlinAsin
import kotlin.math.atan as kotlinAtan
import kotlin.math.atan2 as kotlinAtan2
import kotlin.math.atanh as kotlinAtanh
import kotlin.math.cbrt as kotlinCbrt
import kotlin.math.ceil as kotlinCeil
import kotlin.math.cos as kotlinCos
import kotlin.math.cosh as kotlinCosh
import kotlin.math.exp as kotlinExp
import kotlin.math.expm1 as kotlinExpm1
import kotlin.math.floor as kotlinFloor
import kotlin.math.hypot as kotlinHypot
import kotlin.math.IEEErem
import kotlin.math.ln as kotlinLn
import kotlin.math.ln1p as kotlinLn1p
import kotlin.math.nextDown
import kotlin.math.nextTowards
import kotlin.math.nextUp
import kotlin.math.pow
import kotlin.math.round as kotlinRound
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sign as kotlinSign
import kotlin.math.sin as kotlinSin
import kotlin.math.sinh as kotlinSinh
import kotlin.math.sqrt as kotlinSqrt
import kotlin.math.tan as kotlinTan
import kotlin.math.tanh as kotlinTanh
import kotlin.math.ulp
import kotlin.math.withSign

public object Math {
    public const val E: kotlin.Double = 2.718281828459045
    public const val PI: kotlin.Double = 3.141592653589793
    public const val TAU: kotlin.Double = 6.283185307179586

    public fun abs(value: kotlin.Int): kotlin.Int = kotlinAbs(value)
    public fun abs(value: kotlin.Long): kotlin.Long = kotlinAbs(value)
    public fun abs(value: kotlin.Float): kotlin.Float = kotlinAbs(value)
    public fun abs(value: kotlin.Double): kotlin.Double = kotlinAbs(value)

    public fun max(a: kotlin.Int, b: kotlin.Int): kotlin.Int = if (a >= b) a else b
    public fun max(a: kotlin.Long, b: kotlin.Long): kotlin.Long = if (a >= b) a else b
    public fun max(a: kotlin.Float, b: kotlin.Float): kotlin.Float {
        if (a.isNaN() || b.isNaN()) return kotlin.Float.NaN
        if (a == 0.0f && b == 0.0f) {
            return if (a.toRawBits() >= 0 || b.toRawBits() >= 0) 0.0f else -0.0f
        }
        return if (a >= b) a else b
    }

    public fun max(a: kotlin.Double, b: kotlin.Double): kotlin.Double {
        if (a.isNaN() || b.isNaN()) return kotlin.Double.NaN
        if (a == 0.0 && b == 0.0) {
            return if (a.toRawBits() >= 0L || b.toRawBits() >= 0L) 0.0 else -0.0
        }
        return if (a >= b) a else b
    }

    public fun min(a: kotlin.Int, b: kotlin.Int): kotlin.Int = if (a <= b) a else b
    public fun min(a: kotlin.Long, b: kotlin.Long): kotlin.Long = if (a <= b) a else b
    public fun min(a: kotlin.Float, b: kotlin.Float): kotlin.Float {
        if (a.isNaN() || b.isNaN()) return kotlin.Float.NaN
        if (a == 0.0f && b == 0.0f) {
            return if (a.toRawBits() < 0 || b.toRawBits() < 0) -0.0f else 0.0f
        }
        return if (a <= b) a else b
    }

    public fun min(a: kotlin.Double, b: kotlin.Double): kotlin.Double {
        if (a.isNaN() || b.isNaN()) return kotlin.Double.NaN
        if (a == 0.0 && b == 0.0) {
            return if (a.toRawBits() < 0L || b.toRawBits() < 0L) -0.0 else 0.0
        }
        return if (a <= b) a else b
    }

    public fun absExact(value: kotlin.Int): kotlin.Int {
        if (value == kotlin.Int.MIN_VALUE) throw ArithmeticException("integer overflow")
        return kotlinAbs(value)
    }

    public fun absExact(value: kotlin.Long): kotlin.Long {
        if (value == kotlin.Long.MIN_VALUE) throw ArithmeticException("long overflow")
        return kotlinAbs(value)
    }

    public fun addExact(a: kotlin.Int, b: kotlin.Int): kotlin.Int {
        val result = a + b
        if (((a xor result) and (b xor result)) < 0) throw ArithmeticException("integer overflow")
        return result
    }

    public fun addExact(a: kotlin.Long, b: kotlin.Long): kotlin.Long {
        val result = a + b
        if (((a xor result) and (b xor result)) < 0L) throw ArithmeticException("long overflow")
        return result
    }

    public fun subtractExact(a: kotlin.Int, b: kotlin.Int): kotlin.Int {
        val result = a - b
        if (((a xor b) and (a xor result)) < 0) throw ArithmeticException("integer overflow")
        return result
    }

    public fun subtractExact(a: kotlin.Long, b: kotlin.Long): kotlin.Long {
        val result = a - b
        if (((a xor b) and (a xor result)) < 0L) throw ArithmeticException("long overflow")
        return result
    }

    public fun divideExact(a: kotlin.Int, b: kotlin.Int): kotlin.Int {
        if (a == kotlin.Int.MIN_VALUE && b == -1) throw ArithmeticException("integer overflow")
        return a / b
    }

    public fun divideExact(a: kotlin.Long, b: kotlin.Long): kotlin.Long {
        if (a == kotlin.Long.MIN_VALUE && b == -1L) throw ArithmeticException("long overflow")
        return a / b
    }

    public fun multiplyExact(a: kotlin.Int, b: kotlin.Int): kotlin.Int {
        val result = a.toLong() * b.toLong()
        if (result < kotlin.Int.MIN_VALUE || result > kotlin.Int.MAX_VALUE) {
            throw ArithmeticException("integer overflow")
        }
        return result.toInt()
    }

    public fun multiplyExact(a: kotlin.Long, b: kotlin.Int): kotlin.Long =
        multiplyExact(a, b.toLong())

    public fun multiplyExact(a: kotlin.Long, b: kotlin.Long): kotlin.Long {
        if (a == 0L || b == 0L) return 0L
        if ((a == -1L && b == kotlin.Long.MIN_VALUE) ||
            (b == -1L && a == kotlin.Long.MIN_VALUE)
        ) {
            throw ArithmeticException("long overflow")
        }
        val result = a * b
        if (result / b != a) throw ArithmeticException("long overflow")
        return result
    }

    public fun incrementExact(value: kotlin.Int): kotlin.Int {
        if (value == kotlin.Int.MAX_VALUE) throw ArithmeticException("integer overflow")
        return value + 1
    }

    public fun incrementExact(value: kotlin.Long): kotlin.Long {
        if (value == kotlin.Long.MAX_VALUE) throw ArithmeticException("long overflow")
        return value + 1L
    }

    public fun decrementExact(value: kotlin.Int): kotlin.Int {
        if (value == kotlin.Int.MIN_VALUE) throw ArithmeticException("integer overflow")
        return value - 1
    }

    public fun decrementExact(value: kotlin.Long): kotlin.Long {
        if (value == kotlin.Long.MIN_VALUE) throw ArithmeticException("long overflow")
        return value - 1L
    }

    public fun negateExact(value: kotlin.Int): kotlin.Int {
        if (value == kotlin.Int.MIN_VALUE) throw ArithmeticException("integer overflow")
        return -value
    }

    public fun negateExact(value: kotlin.Long): kotlin.Long {
        if (value == kotlin.Long.MIN_VALUE) throw ArithmeticException("long overflow")
        return -value
    }

    public fun toIntExact(value: kotlin.Long): kotlin.Int {
        if (value < kotlin.Int.MIN_VALUE.toLong() || value > kotlin.Int.MAX_VALUE.toLong()) {
            throw ArithmeticException("integer overflow")
        }
        return value.toInt()
    }

    public fun multiplyFull(a: kotlin.Int, b: kotlin.Int): kotlin.Long = a.toLong() * b.toLong()

    public fun multiplyHigh(a: kotlin.Long, b: kotlin.Long): kotlin.Long {
        val aHigh = a shr 32
        val aLow = a and 0xffff_ffffL
        val bHigh = b shr 32
        val bLow = b and 0xffff_ffffL
        val lowProduct = aLow * bLow
        val middle = aHigh * bLow + (lowProduct ushr 32)
        val middleLow = middle and 0xffff_ffffL
        val middleHigh = middle shr 32
        val cross = middleLow + aLow * bHigh
        return aHigh * bHigh + middleHigh + (cross shr 32)
    }

    public fun unsignedMultiplyHigh(a: kotlin.Long, b: kotlin.Long): kotlin.Long =
        multiplyHigh(a, b) + (if (a < 0L) b else 0L) + (if (b < 0L) a else 0L)

    public fun unsignedMultiplyExact(a: kotlin.Int, b: kotlin.Int): kotlin.Int {
        val product = a.toUInt().toULong() * b.toUInt().toULong()
        if (product > kotlin.UInt.MAX_VALUE.toULong()) throw ArithmeticException("unsigned integer overflow")
        return product.toUInt().toInt()
    }

    public fun unsignedMultiplyExact(a: kotlin.Long, b: kotlin.Int): kotlin.Long {
        val unsignedA = a.toULong()
        val unsignedB = b.toUInt().toULong()
        if (unsignedB != 0uL && unsignedA > kotlin.ULong.MAX_VALUE / unsignedB) {
            throw ArithmeticException("unsigned long overflow")
        }
        return (unsignedA * unsignedB).toLong()
    }

    public fun unsignedMultiplyExact(a: kotlin.Long, b: kotlin.Long): kotlin.Long {
        val unsignedA = a.toULong()
        val unsignedB = b.toULong()
        if (unsignedB != 0uL && unsignedA > kotlin.ULong.MAX_VALUE / unsignedB) {
            throw ArithmeticException("unsigned long overflow")
        }
        return (unsignedA * unsignedB).toLong()
    }

    private fun multiplyExactPower(base: kotlin.Int, exponent: kotlin.Int): kotlin.Int {
        if (exponent < 0) throw ArithmeticException("negative exponent")
        var factor = base
        var remaining = exponent
        var result = 1
        while (remaining > 0) {
            if ((remaining and 1) != 0) result = multiplyExact(result, factor)
            remaining = remaining ushr 1
            if (remaining > 0) factor = multiplyExact(factor, factor)
        }
        return result
    }

    private fun multiplyExactPower(base: kotlin.Long, exponent: kotlin.Int): kotlin.Long {
        if (exponent < 0) throw ArithmeticException("negative exponent")
        var factor = base
        var remaining = exponent
        var result = 1L
        while (remaining > 0) {
            if ((remaining and 1) != 0) result = multiplyExact(result, factor)
            remaining = remaining ushr 1
            if (remaining > 0) factor = multiplyExact(factor, factor)
        }
        return result
    }

    public fun powExact(base: kotlin.Int, exponent: kotlin.Int): kotlin.Int =
        multiplyExactPower(base, exponent)

    public fun powExact(base: kotlin.Long, exponent: kotlin.Int): kotlin.Long =
        multiplyExactPower(base, exponent)

    private fun unsignedMultiplyExactPower(base: kotlin.UInt, exponent: kotlin.Int): kotlin.UInt {
        if (exponent < 0) throw ArithmeticException("negative exponent")
        var factor = base
        var remaining = exponent
        var result = 1u
        while (remaining > 0) {
            if ((remaining and 1) != 0) result = unsignedMultiplyExact(result.toInt(), factor.toInt()).toUInt()
            remaining = remaining ushr 1
            if (remaining > 0) factor = unsignedMultiplyExact(factor.toInt(), factor.toInt()).toUInt()
        }
        return result
    }

    private fun unsignedMultiplyExactPower(base: kotlin.ULong, exponent: kotlin.Int): kotlin.ULong {
        if (exponent < 0) throw ArithmeticException("negative exponent")
        var factor = base
        var remaining = exponent
        var result = 1uL
        while (remaining > 0) {
            if ((remaining and 1) != 0) result = unsignedMultiplyExact(result.toLong(), factor.toLong()).toULong()
            remaining = remaining ushr 1
            if (remaining > 0) factor = unsignedMultiplyExact(factor.toLong(), factor.toLong()).toULong()
        }
        return result
    }

    public fun unsignedPowExact(base: kotlin.Int, exponent: kotlin.Int): kotlin.Int =
        unsignedMultiplyExactPower(base.toUInt(), exponent).toInt()

    public fun unsignedPowExact(base: kotlin.Long, exponent: kotlin.Int): kotlin.Long =
        unsignedMultiplyExactPower(base.toULong(), exponent).toLong()

    private fun floorDivLong(x: kotlin.Long, y: kotlin.Long): kotlin.Long {
        val quotient = x / y
        val remainder = x % y
        return if (remainder != 0L && ((x xor y) < 0L)) quotient - 1L else quotient
    }

    private fun ceilDivLong(x: kotlin.Long, y: kotlin.Long): kotlin.Long {
        val quotient = x / y
        val remainder = x % y
        return if (remainder != 0L && ((x xor y) >= 0L)) quotient + 1L else quotient
    }

    public fun floorDiv(x: kotlin.Int, y: kotlin.Int): kotlin.Int =
        floorDivLong(x.toLong(), y.toLong()).toInt()

    public fun floorDiv(x: kotlin.Long, y: kotlin.Int): kotlin.Long = floorDivLong(x, y.toLong())

    public fun floorDiv(x: kotlin.Long, y: kotlin.Long): kotlin.Long = floorDivLong(x, y)

    public fun floorDivExact(x: kotlin.Int, y: kotlin.Int): kotlin.Int {
        if (x == kotlin.Int.MIN_VALUE && y == -1) throw ArithmeticException("integer overflow")
        return floorDivLong(x.toLong(), y.toLong()).toInt()
    }

    public fun floorDivExact(x: kotlin.Long, y: kotlin.Long): kotlin.Long {
        if (x == kotlin.Long.MIN_VALUE && y == -1L) throw ArithmeticException("long overflow")
        return floorDivLong(x, y)
    }

    public fun ceilDiv(x: kotlin.Int, y: kotlin.Int): kotlin.Int =
        ceilDivLong(x.toLong(), y.toLong()).toInt()

    public fun ceilDiv(x: kotlin.Long, y: kotlin.Int): kotlin.Long = ceilDivLong(x, y.toLong())

    public fun ceilDiv(x: kotlin.Long, y: kotlin.Long): kotlin.Long = ceilDivLong(x, y)

    public fun ceilDivExact(x: kotlin.Int, y: kotlin.Int): kotlin.Int {
        if (x == kotlin.Int.MIN_VALUE && y == -1) throw ArithmeticException("integer overflow")
        return ceilDivLong(x.toLong(), y.toLong()).toInt()
    }

    public fun ceilDivExact(x: kotlin.Long, y: kotlin.Long): kotlin.Long {
        if (x == kotlin.Long.MIN_VALUE && y == -1L) throw ArithmeticException("long overflow")
        return ceilDivLong(x, y)
    }

    public fun floorMod(x: kotlin.Int, y: kotlin.Int): kotlin.Int =
        (x.toLong() - floorDivLong(x.toLong(), y.toLong()) * y.toLong()).toInt()

    public fun floorMod(x: kotlin.Long, y: kotlin.Int): kotlin.Int =
        (x - floorDivLong(x, y.toLong()) * y.toLong()).toInt()

    public fun floorMod(x: kotlin.Long, y: kotlin.Long): kotlin.Long =
        x - floorDivLong(x, y) * y

    public fun ceilMod(x: kotlin.Int, y: kotlin.Int): kotlin.Int =
        (x.toLong() - ceilDivLong(x.toLong(), y.toLong()) * y.toLong()).toInt()

    public fun ceilMod(x: kotlin.Long, y: kotlin.Int): kotlin.Int =
        (x - ceilDivLong(x, y.toLong()) * y.toLong()).toInt()

    public fun ceilMod(x: kotlin.Long, y: kotlin.Long): kotlin.Long =
        x - ceilDivLong(x, y) * y

    public fun clamp(value: kotlin.Int, min: kotlin.Int, max: kotlin.Int): kotlin.Int {
        if (min > max) throw IllegalArgumentException("min > max")
        return if (value < min) min else if (value > max) max else value
    }

    public fun clamp(value: kotlin.Long, min: kotlin.Long, max: kotlin.Long): kotlin.Long {
        if (min > max) throw IllegalArgumentException("min > max")
        return if (value < min) min else if (value > max) max else value
    }

    public fun clamp(value: kotlin.Long, min: kotlin.Int, max: kotlin.Int): kotlin.Int {
        if (min > max) throw IllegalArgumentException("min > max")
        return if (value < min.toLong()) min else if (value > max.toLong()) max else value.toInt()
    }

    public fun clamp(value: kotlin.Float, min: kotlin.Float, max: kotlin.Float): kotlin.Float {
        if (min.isNaN() || max.isNaN() || min > max) throw IllegalArgumentException("invalid bounds")
        return if (value < min) min else if (value > max) max else value
    }

    public fun clamp(value: kotlin.Double, min: kotlin.Double, max: kotlin.Double): kotlin.Double {
        if (min.isNaN() || max.isNaN() || min > max) throw IllegalArgumentException("invalid bounds")
        return if (value < min) min else if (value > max) max else value
    }

    public fun ceil(value: kotlin.Double): kotlin.Double = kotlinCeil(value)
    public fun floor(value: kotlin.Double): kotlin.Double = kotlinFloor(value)
    public fun rint(value: kotlin.Double): kotlin.Double = kotlinRound(value)
    public fun round(value: kotlin.Double): kotlin.Long = value.roundToLong()
    public fun round(value: kotlin.Float): kotlin.Int = value.roundToInt()

    public fun sqrt(value: kotlin.Double): kotlin.Double = kotlinSqrt(value)
    public fun cbrt(value: kotlin.Double): kotlin.Double = kotlinCbrt(value)
    public fun pow(base: kotlin.Double, exponent: kotlin.Double): kotlin.Double = base.pow(exponent)
    public fun hypot(x: kotlin.Double, y: kotlin.Double): kotlin.Double = kotlinHypot(x, y)

    public fun sin(value: kotlin.Double): kotlin.Double = kotlinSin(value)
    public fun cos(value: kotlin.Double): kotlin.Double = kotlinCos(value)
    public fun tan(value: kotlin.Double): kotlin.Double = kotlinTan(value)
    public fun asin(value: kotlin.Double): kotlin.Double = kotlinAsin(value)
    public fun acos(value: kotlin.Double): kotlin.Double = kotlinAcos(value)
    public fun atan(value: kotlin.Double): kotlin.Double = kotlinAtan(value)
    public fun atan2(y: kotlin.Double, x: kotlin.Double): kotlin.Double = kotlinAtan2(y, x)
    public fun sinh(value: kotlin.Double): kotlin.Double = kotlinSinh(value)
    public fun cosh(value: kotlin.Double): kotlin.Double = kotlinCosh(value)
    public fun tanh(value: kotlin.Double): kotlin.Double = kotlinTanh(value)
    public fun asinh(value: kotlin.Double): kotlin.Double = kotlinAsinh(value)
    public fun acosh(value: kotlin.Double): kotlin.Double = kotlinAcosh(value)
    public fun atanh(value: kotlin.Double): kotlin.Double = kotlinAtanh(value)
    public fun exp(value: kotlin.Double): kotlin.Double = kotlinExp(value)
    public fun expm1(value: kotlin.Double): kotlin.Double = kotlinExpm1(value)
    public fun log(value: kotlin.Double): kotlin.Double = kotlinLn(value)
    public fun log10(value: kotlin.Double): kotlin.Double = kotlin.math.log10(value)
    public fun log1p(value: kotlin.Double): kotlin.Double = kotlinLn1p(value)

    public fun IEEEremainder(value: kotlin.Double, divisor: kotlin.Double): kotlin.Double =
        value.IEEErem(divisor)

    public fun signum(value: kotlin.Double): kotlin.Double = kotlinSign(value)
    public fun signum(value: kotlin.Float): kotlin.Float = kotlinSign(value)
    public fun toRadians(degrees: kotlin.Double): kotlin.Double = degrees / 180.0 * PI
    public fun toDegrees(radians: kotlin.Double): kotlin.Double = radians * 180.0 / PI

    public fun copySign(magnitude: kotlin.Double, sign: kotlin.Double): kotlin.Double =
        magnitude.withSign(sign)

    public fun copySign(magnitude: kotlin.Float, sign: kotlin.Float): kotlin.Float =
        magnitude.withSign(sign)

    public fun ulp(value: kotlin.Double): kotlin.Double = value.ulp
    public fun ulp(value: kotlin.Float): kotlin.Float = value.ulp
    public fun nextUp(value: kotlin.Double): kotlin.Double = value.nextUp()
    public fun nextUp(value: kotlin.Float): kotlin.Float = value.nextUp()
    public fun nextDown(value: kotlin.Double): kotlin.Double = value.nextDown()
    public fun nextDown(value: kotlin.Float): kotlin.Float = value.nextDown()
    public fun nextAfter(start: kotlin.Double, direction: kotlin.Double): kotlin.Double =
        start.nextTowards(direction)

    public fun nextAfter(start: kotlin.Float, direction: kotlin.Double): kotlin.Float {
        if (start.isNaN() || direction.isNaN()) return kotlin.Float.NaN
        if (start.toDouble() == direction) return direction.toFloat()
        return if (start.toDouble() < direction) start.nextUp() else start.nextDown()
    }

    public fun getExponent(value: kotlin.Double): kotlin.Int {
        val exponent = ((value.toRawBits() ushr 52) and 0x7ffL).toInt()
        return if (exponent == 0) -1023 else exponent - 1023
    }

    public fun getExponent(value: kotlin.Float): kotlin.Int {
        val exponent = (value.toRawBits() ushr 23) and 0xff
        return if (exponent == 0) -127 else exponent - 127
    }

    @KsSymbolName("__kk_math_scalb")
    private external fun __scalb(value: kotlin.Double, scaleFactor: kotlin.Int): kotlin.Double

    @KsSymbolName("__kk_math_scalb_float")
    private external fun __scalb(value: kotlin.Float, scaleFactor: kotlin.Int): kotlin.Float

    public fun scalb(value: kotlin.Double, scaleFactor: kotlin.Int): kotlin.Double =
        __scalb(value, scaleFactor)

    public fun scalb(value: kotlin.Float, scaleFactor: kotlin.Int): kotlin.Float =
        __scalb(value, scaleFactor)

    @KsSymbolName("__kk_math_fma")
    private external fun __fma(a: kotlin.Double, b: kotlin.Double, c: kotlin.Double): kotlin.Double

    @KsSymbolName("__kk_math_fma_float")
    private external fun __fma(a: kotlin.Float, b: kotlin.Float, c: kotlin.Float): kotlin.Float

    public fun fma(a: kotlin.Double, b: kotlin.Double, c: kotlin.Double): kotlin.Double =
        __fma(a, b, c)

    public fun fma(a: kotlin.Float, b: kotlin.Float, c: kotlin.Float): kotlin.Float =
        __fma(a, b, c)

    public fun random(): kotlin.Double = kotlin.random.Random.nextDouble()
}
