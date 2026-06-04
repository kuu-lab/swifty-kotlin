package kotlin.math

fun abs(x: Int): Int = if (x < 0) -x else x

fun abs(n: Long): Long = if (n < 0L) -n else n

fun abs(x: Double): Double = if (x < 0.0) -x else if (x == 0.0) 0.0 else x

fun abs(x: Float): Float = if (x < 0.0f) -x else if (x == 0.0f) 0.0f else x

// Helper: Check if Double is NaN
private fun doubleIsNaN(x: Double): Boolean = x != x

// Helper: Check if Float is NaN
private fun floatIsNaN(x: Float): Boolean = x != x

// Helper: Check if Double is infinite
private fun doubleIsInfinite(x: Double): Boolean = x == Double.POSITIVE_INFINITY || x == Double.NEGATIVE_INFINITY

// Helper: Check if Float is infinite
private fun floatIsInfinite(x: Float): Boolean = x == Float.POSITIVE_INFINITY || x == Float.NEGATIVE_INFINITY

// Mathematical constants
private const val PI = 3.14159265358979323846
private const val TWO_PI = 2.0 * PI
private const val HALF_PI = PI / 2.0
private const val INV_PI = 1.0 / PI
private const val E = 2.71828182845904523536
private const val LN_2 = 0.69314718055994530942
private const val INV_LN_2 = 1.0 / LN_2

// Range reduction helper: reduce x to [-PI, PI]
private fun reduceRange(x: Double): Double {
    if (doubleIsInfinite(x) || doubleIsNaN(x)) return x
    val reduced = x - TWO_PI * floor(x * INV_PI + 0.5)
    return reduced
}

// Range reduction helper for Float
private fun reduceRangeFloat(x: Float): Float {
    if (floatIsInfinite(x) || floatIsNaN(x)) return x
    val reduced = x - (2.0f * PI.toFloat()) * floor(x / PI.toFloat() + 0.5f)
    return reduced
}

fun sqrt(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x < 0.0) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    
    // Newton-Raphson method
    var guess = x
    var prev = 0.0
    val epsilon = 1e-15
    
    // Initial guess using bit manipulation for better starting point
    val bits = x.toRawBits()
    val exp = ((bits ushr 52) and 0x7FF).toInt() - 1023
    val adjustedExp = if (exp < 0) (exp - 1) / 2 else exp / 2
    val initialBits = ((bits and 0x800FFFFFFFFFFFFFL) or ((adjustedExp + 1023).toLong() shl 52))
    guess = Double.fromBits(initialBits)
    
    // Newton-Raphson iteration: guess = (guess + x/guess) / 2
    repeat(20) {
        prev = guess
        guess = (guess + x / guess) * 0.5
        if (abs(guess - prev) < epsilon * guess) break
    }
    
    return guess
}

fun sqrt(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x < 0.0f) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    
    // Newton-Raphson method
    var guess = x
    var prev = 0.0f
    val epsilon = 1e-7f
    
    // Initial guess using bit manipulation
    val bits = x.toRawBits()
    val exp = ((bits ushr 23) and 0xFF).toInt() - 127
    val adjustedExp = if (exp < 0) (exp - 1) / 2 else exp / 2
    val initialBits = ((bits and 0x807FFFFF) or ((adjustedExp + 127) shl 23))
    guess = Float.fromBits(initialBits)
    
    // Newton-Raphson iteration
    repeat(10) {
        prev = guess
        guess = (guess + x / guess) * 0.5f
        if (abs(guess - prev) < epsilon * guess) break
    }
    
    return guess
}

fun ceil(x: Double): Double {
    if (doubleIsNaN(x) || doubleIsInfinite(x)) return x
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    val intPart = x.toLong()
    if (x <= intPart.toDouble()) return intPart.toDouble()
    return (intPart + 1).toDouble()
}

fun ceil(x: Float): Float {
    if (floatIsNaN(x) || floatIsInfinite(x)) return x
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    val intPart = x.toInt()
    if (x <= intPart.toFloat()) return intPart.toFloat()
    return (intPart + 1).toFloat()
}

fun floor(x: Double): Double {
    if (doubleIsNaN(x) || doubleIsInfinite(x)) return x
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    val intPart = x.toLong()
    if (x >= intPart.toDouble()) return intPart.toDouble()
    return (intPart - 1).toDouble()
}

fun floor(x: Float): Float {
    if (floatIsNaN(x) || floatIsInfinite(x)) return x
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    val intPart = x.toInt()
    if (x >= intPart.toFloat()) return intPart.toFloat()
    return (intPart - 1).toFloat()
}

fun round(x: Double): Double {
    if (doubleIsNaN(x) || doubleIsInfinite(x)) return x
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    return floor(x + 0.5)
}

fun round(x: Float): Float {
    if (floatIsNaN(x) || floatIsInfinite(x)) return x
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    return floor(x + 0.5f)
}

fun truncate(x: Double): Double {
    if (doubleIsNaN(x) || doubleIsInfinite(x)) return x
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    return if (x >= 0.0) floor(x) else ceil(x)
}

fun truncate(x: Float): Float {
    if (floatIsNaN(x) || floatIsInfinite(x)) return x
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    return if (x >= 0.0f) floor(x) else ceil(x)
}

fun sin(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    val reduced = reduceRange(x)
    
    // Taylor series: sin(x) = x - x^3/3! + x^5/5! - x^7/7! + ...
    var result = 0.0
    var term = reduced
    var xSquared = reduced * reduced
    var sign = 1.0
    
    for (n in 1..15 step 2) {
        result += sign * term
        sign = -sign
        term *= xSquared / ((n + 1) * (n + 2))
    }
    
    return result
}

fun sin(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    val reduced = reduceRangeFloat(x)
    
    // Taylor series for Float
    var result = 0.0f
    var term = reduced
    var xSquared = reduced * reduced
    var sign = 1.0f
    
    for (n in 1..9 step 2) {
        result += sign * term
        sign = -sign
        term *= xSquared / ((n + 1) * (n + 2))
    }
    
    return result
}

fun cos(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) return Double.NaN
    
    val reduced = reduceRange(x)
    
    // Taylor series: cos(x) = 1 - x^2/2! + x^4/4! - x^6/6! + ...
    var result = 0.0
    var term = 1.0
    var xSquared = reduced * reduced
    var sign = 1.0
    
    for (n in 0..14 step 2) {
        result += sign * term
        sign = -sign
        term *= xSquared / ((n + 1) * (n + 2))
    }
    
    return result
}

fun cos(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) return Float.NaN
    
    val reduced = reduceRangeFloat(x)
    
    // Taylor series for Float
    var result = 0.0f
    var term = 1.0f
    var xSquared = reduced * reduced
    var sign = 1.0f
    
    for (n in 0..8 step 2) {
        result += sign * term
        sign = -sign
        term *= xSquared / ((n + 1) * (n + 2))
    }
    
    return result
}

fun tan(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) return Double.NaN
    
    val s = sin(x)
    val c = cos(x)
    
    // Handle singularities where cos(x) is near zero
    if (abs(c) < 1e-15) {
        return if (s > 0.0) Double.POSITIVE_INFINITY else Double.NEGATIVE_INFINITY
    }
    
    return s / c
}

fun tan(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) return Float.NaN
    
    val s = sin(x)
    val c = cos(x)
    
    // Handle singularities
    if (abs(c) < 1e-7f) {
        return if (s > 0.0f) Float.POSITIVE_INFINITY else Float.NEGATIVE_INFINITY
    }
    
    return s / c
}

fun asin(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x > 1.0 || x < -1.0) return Double.NaN
    if (x == 1.0) return HALF_PI
    if (x == -1.0) return -HALF_PI
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    // Use relationship: asin(x) = atan(x / sqrt(1 - x^2))
    val sqrtTerm = sqrt(1.0 - x * x)
    return atan(x / sqrtTerm)
}

fun asin(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x > 1.0f || x < -1.0f) return Float.NaN
    if (x == 1.0f) return (HALF_PI).toFloat()
    if (x == -1.0f) return (-HALF_PI).toFloat()
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    val sqrtTerm = sqrt(1.0f - x * x)
    return atan(x / sqrtTerm)
}

fun acos(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x > 1.0 || x < -1.0) return Double.NaN
    if (x == 1.0) return 0.0
    if (x == -1.0) return PI
    if (x == 0.0) return HALF_PI
    
    // Use relationship: acos(x) = PI/2 - asin(x)
    return HALF_PI - asin(x)
}

fun acos(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x > 1.0f || x < -1.0f) return Float.NaN
    if (x == 1.0f) return 0.0f
    if (x == -1.0f) return PI.toFloat()
    if (x == 0.0f) return (HALF_PI).toFloat()
    
    return (HALF_PI).toFloat() - asin(x)
}

fun atan(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) {
        return if (x > 0.0) HALF_PI else -HALF_PI
    }
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    // Use polynomial approximation for atan
    val absX = abs(x)
    
    // For large values, use atan(x) = PI/2 - atan(1/x)
    if (absX > 1.0) {
        return if (x > 0.0) HALF_PI - atan(1.0 / x) else -HALF_PI - atan(1.0 / x)
    }
    
    // Polynomial approximation for |x| <= 1
    // atan(x) ≈ x - x^3/3 + x^5/5 - x^7/7 + ...
    var result = 0.0
    var term = absX
    var xSquared = absX * absX
    var sign = 1.0
    
    for (n in 1..15 step 2) {
        result += sign * term / n
        sign = -sign
        term *= xSquared
    }
    
    return if (x < 0.0) -result else result
}

fun atan(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) {
        return if (x > 0.0f) (HALF_PI).toFloat() else (-HALF_PI).toFloat()
    }
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    val absX = abs(x)
    
    if (absX > 1.0f) {
        return if (x > 0.0f) (HALF_PI).toFloat() - atan(1.0f / x) else (-HALF_PI).toFloat() - atan(1.0f / x)
    }
    
    var result = 0.0f
    var term = absX
    var xSquared = absX * absX
    var sign = 1.0f
    
    for (n in 1..9 step 2) {
        result += sign * term / n
        sign = -sign
        term *= xSquared
    }
    
    return if (x < 0.0f) -result else result
}

fun atan2(y: Double, x: Double): Double {
    if (doubleIsNaN(y) || doubleIsNaN(x)) return Double.NaN
    if (y == 0.0 && x == 0.0) return if (y < 0.0) -0.0 else 0.0
    
    if (doubleIsInfinite(y) || doubleIsInfinite(x)) {
        if (doubleIsInfinite(y)) {
            return if (y > 0.0) HALF_PI else -HALF_PI
        }
        if (doubleIsInfinite(x)) {
            return if (x > 0.0) if (y >= 0.0) 0.0 else -0.0 else PI
        }
    }
    
    if (x > 0.0) {
        return atan(y / x)
    } else if (x < 0.0) {
        if (y >= 0.0) {
            return atan(y / x) + PI
        } else {
            return atan(y / x) - PI
        }
    } else {
        // x == 0
        return if (y > 0.0) HALF_PI else -HALF_PI
    }
}

fun atan2(y: Float, x: Float): Float {
    if (floatIsNaN(y) || floatIsNaN(x)) return Float.NaN
    if (y == 0.0f && x == 0.0f) return if (y < 0.0f) -0.0f else 0.0f
    
    if (floatIsInfinite(y) || floatIsInfinite(x)) {
        if (floatIsInfinite(y)) {
            return if (y > 0.0f) (HALF_PI).toFloat() else (-HALF_PI).toFloat()
        }
        if (floatIsInfinite(x)) {
            return if (x > 0.0f) if (y >= 0.0f) 0.0f else -0.0f else PI.toFloat()
        }
    }
    
    if (x > 0.0f) {
        return atan(y / x)
    } else if (x < 0.0f) {
        if (y >= 0.0f) {
            return atan(y / x) + PI.toFloat()
        } else {
            return atan(y / x) - PI.toFloat()
        }
    } else {
        return if (y > 0.0f) (HALF_PI).toFloat() else (-HALF_PI).toFloat()
    }
}

fun exp(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x == 0.0) return 1.0
    if (doubleIsInfinite(x)) {
        return if (x > 0.0) Double.POSITIVE_INFINITY else 0.0
    }
    
    // Range reduction: exp(x) = exp(n * ln(2)) * exp(f) where x = n * ln(2) + f, |f| <= ln(2)/2
    val n = (x * INV_LN_2).toLong()
    val f = x - n * LN_2
    
    // Taylor series: exp(f) = 1 + f + f^2/2! + f^3/3! + ...
    var result = 1.0
    var term = 1.0
    
    for (i in 1..30) {
        term *= f / i
        result += term
        if (abs(term) < 1e-16 * result) break
    }
    
    // Multiply by 2^n
    return result * (1L shl n.toInt()).toDouble()
}

fun exp(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x == 0.0f) return 1.0f
    if (floatIsInfinite(x)) {
        return if (x > 0.0f) Float.POSITIVE_INFINITY else 0.0f
    }
    
    val n = (x * INV_LN_2.toFloat()).toInt()
    val f = x - n * LN_2.toFloat()
    
    var result = 1.0f
    var term = 1.0f
    
    for (i in 1..20) {
        term *= f / i
        result += term
        if (abs(term) < 1e-7f * result) break
    }
    
    return result * (1 shl n).toFloat()
}

fun expm1(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    if (doubleIsInfinite(x)) {
        return if (x > 0.0) Double.POSITIVE_INFINITY else -1.0
    }
    
    // For small x, use Taylor series directly: exp(x) - 1 = x + x^2/2! + x^3/3! + ...
    if (abs(x) < 1e-8) {
        var result = 0.0
        var term = x
        
        for (i in 1..20) {
            result += term
            term *= x / (i + 1)
            if (abs(term) < 1e-16) break
        }
        
        return result
    }
    
    // For larger x, use exp(x) - 1
    return exp(x) - 1.0
}

fun expm1(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    if (floatIsInfinite(x)) {
        return if (x > 0.0f) Float.POSITIVE_INFINITY else -1.0f
    }
    
    if (abs(x) < 1e-4f) {
        var result = 0.0f
        var term = x
        
        for (i in 1..15) {
            result += term
            term *= x / (i + 1)
            if (abs(term) < 1e-7f) break
        }
        
        return result
    }
    
    return exp(x) - 1.0f
}

fun ln(x: Double): Double {
    if (doubleIsNaN(x) || x < 0.0) return Double.NaN
    if (x == 0.0) return Double.NEGATIVE_INFINITY
    if (x == 1.0) return 0.0
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    
    // Use log2(x) * ln(2)
    return log2(x) * LN_2
}

fun ln(x: Float): Float {
    if (floatIsNaN(x) || x < 0.0f) return Float.NaN
    if (x == 0.0f) return Float.NEGATIVE_INFINITY
    if (x == 1.0f) return 0.0f
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    
    return log2(x) * LN_2.toFloat()
}

fun ln1p(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x <= -1.0) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    // For small x, use Taylor series: ln(1+x) = x - x^2/2 + x^3/3 - ...
    if (abs(x) < 1e-8) {
        var result = 0.0
        var term = x
        var sign = 1.0
        
        for (n in 1..20) {
            result += sign * term / n
            sign = -sign
            term *= x
            if (abs(term / n) < 1e-16) break
        }
        
        return result
    }
    
    // For larger x, use ln(1+x)
    return ln(1.0 + x)
}

fun ln1p(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x <= -1.0f) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    if (abs(x) < 1e-4f) {
        var result = 0.0f
        var term = x
        var sign = 1.0f
        
        for (n in 1..15) {
            result += sign * term / n
            sign = -sign
            term *= x
            if (abs(term / n) < 1e-7f) break
        }
        
        return result
    }
    
    return ln(1.0f + x)
}

fun log2(x: Double): Double {
    if (doubleIsNaN(x) || x < 0.0) return Double.NaN
    if (x == 0.0) return Double.NEGATIVE_INFINITY
    if (x == 1.0) return 0.0
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    
    // Use bit manipulation to get exponent and mantissa
    val bits = x.toRawBits()
    val exp = ((bits ushr 52) and 0x7FF).toInt() - 1023
    val mantissa = (bits and 0x000FFFFFFFFFFFFFL) or 0x3FF0000000000000L
    val m = Double.fromBits(mantissa)
    
    // log2(x) = exp + log2(m) where m is in [1, 2)
    // Use Newton-Raphson to compute log2(m)
    var result = exp.toDouble()
    
    // For mantissa close to 1, use Taylor series: log2(1+y) ≈ y/ln(2) - y^2/(2*ln(2)) + ...
    val y = m - 1.0
    if (abs(y) < 0.1) {
        var term = y
        var sign = 1.0
        for (n in 1..15) {
            result += sign * term / (n * LN_2)
            sign = -sign
            term *= y
            if (abs(term / (n * LN_2)) < 1e-16) break
        }
    } else {
        // Use Newton-Raphson: find y such that 2^y = m
        var y = (m - 1.0) / LN_2
        repeat(20) {
            val expY = exp(y)
            val newY = y + (m - expY) / (expY * LN_2)
            if (abs(newY - y) < 1e-15) break
            y = newY
        }
        result += y
    }
    
    return result
}

fun log2(x: Float): Float {
    if (floatIsNaN(x) || x < 0.0f) return Float.NaN
    if (x == 0.0f) return Float.NEGATIVE_INFINITY
    if (x == 1.0f) return 0.0f
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    
    val bits = x.toRawBits()
    val exp = ((bits ushr 23) and 0xFF).toInt() - 127
    val mantissa = (bits and 0x007FFFFF) or 0x3F800000
    val m = Float.fromBits(mantissa)
    
    var result = exp.toFloat()
    
    val y = m - 1.0f
    if (abs(y) < 0.1f) {
        var term = y
        var sign = 1.0f
        for (n in 1..10) {
            result += sign * term / (n * LN_2.toFloat())
            sign = -sign
            term *= y
            if (abs(term / (n * LN_2.toFloat())) < 1e-7f) break
        }
    } else {
        var y = (m - 1.0f) / LN_2.toFloat()
        repeat(15) {
            val expY = exp(y)
            val newY = y + (m - expY) / (expY * LN_2.toFloat())
            if (abs(newY - y) < 1e-7f) break
            y = newY
        }
        result += y
    }
    
    return result
}

fun log10(x: Double): Double {
    if (doubleIsNaN(x) || x < 0.0) return Double.NaN
    if (x == 0.0) return Double.NEGATIVE_INFINITY
    if (x == 1.0) return 0.0
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    
    // log10(x) = ln(x) / ln(10)
    return ln(x) / 2.30258509299404568402
}

fun log10(x: Float): Float {
    if (floatIsNaN(x) || x < 0.0f) return Float.NaN
    if (x == 0.0f) return Float.NEGATIVE_INFINITY
    if (x == 1.0f) return 0.0f
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    
    return ln(x) / 2.30258509299404568402f
}

fun log(x: Double, base: Double): Double {
    if (doubleIsNaN(x) || doubleIsNaN(base)) return Double.NaN
    if (base <= 0.0 || base == 1.0) return Double.NaN
    if (x <= 0.0) {
        if (x == 0.0) return Double.NEGATIVE_INFINITY
        return Double.NaN
    }
    
    return ln(x) / ln(base)
}

fun log(x: Float, base: Float): Float {
    if (floatIsNaN(x) || floatIsNaN(base)) return Float.NaN
    if (base <= 0.0f || base == 1.0f) return Float.NaN
    if (x <= 0.0f) {
        if (x == 0.0f) return Float.NEGATIVE_INFINITY
        return Float.NaN
    }
    
    return ln(x) / ln(base)
}

fun sinh(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) {
        return if (x > 0.0) Double.POSITIVE_INFINITY else Double.NEGATIVE_INFINITY
    }
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    // sinh(x) = (exp(x) - exp(-x)) / 2
    val expX = exp(x)
    val expNegX = exp(-x)
    return (expX - expNegX) * 0.5
}

fun sinh(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) {
        return if (x > 0.0f) Float.POSITIVE_INFINITY else Float.NEGATIVE_INFINITY
    }
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    val expX = exp(x)
    val expNegX = exp(-x)
    return (expX - expNegX) * 0.5f
}

fun cosh(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    if (x == 0.0) return 1.0
    
    // cosh(x) = (exp(x) + exp(-x)) / 2
    val expX = exp(x)
    val expNegX = exp(-x)
    return (expX + expNegX) * 0.5
}

fun cosh(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    if (x == 0.0f) return 1.0f
    
    val expX = exp(x)
    val expNegX = exp(-x)
    return (expX + expNegX) * 0.5f
}

fun tanh(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) {
        return if (x > 0.0) 1.0 else -1.0
    }
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    // tanh(x) = sinh(x) / cosh(x)
    val s = sinh(x)
    val c = cosh(x)
    return s / c
}

fun tanh(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) {
        return if (x > 0.0f) 1.0f else -1.0f
    }
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    val s = sinh(x)
    val c = cosh(x)
    return s / c
}

fun cbrt(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    if (doubleIsInfinite(x)) return if (x > 0.0) Double.POSITIVE_INFINITY else Double.NEGATIVE_INFINITY
    
    // Newton-Raphson method for cube root: guess = (2*guess + x/(guess*guess)) / 3
    var guess = if (x > 0.0) x else -x
    var prev = 0.0
    val epsilon = 1e-15
    val sign = if (x < 0.0) -1.0 else 1.0
    
    // Initial guess using bit manipulation
    val bits = x.toRawBits()
    val exp = ((bits ushr 52) and 0x7FF).toInt() - 1023
    val adjustedExp = exp / 3
    val initialBits = ((bits and 0x800FFFFFFFFFFFFFL) or ((adjustedExp + 1023).toLong() shl 52))
    guess = Double.fromBits(initialBits)
    if (guess == 0.0) guess = 1.0
    
    // Newton-Raphson iteration
    repeat(30) {
        prev = guess
        val guessSq = guess * guess
        guess = (2.0 * guess + sign * x / guessSq) / 3.0
        if (abs(guess - prev) < epsilon * abs(guess)) break
    }
    
    return sign * guess
}

fun cbrt(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    if (floatIsInfinite(x)) return if (x > 0.0f) Float.POSITIVE_INFINITY else Float.NEGATIVE_INFINITY
    
    // Newton-Raphson method for cube root
    var guess = if (x > 0.0f) x else -x
    var prev = 0.0f
    val epsilon = 1e-7f
    val sign = if (x < 0.0f) -1.0f else 1.0f
    
    // Initial guess using bit manipulation
    val bits = x.toRawBits()
    val exp = ((bits ushr 23) and 0xFF).toInt() - 127
    val adjustedExp = exp / 3
    val initialBits = ((bits and 0x807FFFFF) or ((adjustedExp + 127) shl 23))
    guess = Float.fromBits(initialBits)
    if (guess == 0.0f) guess = 1.0f
    
    // Newton-Raphson iteration
    repeat(15) {
        prev = guess
        val guessSq = guess * guess
        guess = (2.0f * guess + sign * x / guessSq) / 3.0f
        if (abs(guess - prev) < epsilon * abs(guess)) break
    }
    
    return sign * guess
}

fun acosh(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x < 1.0) return Double.NaN
    if (x == 1.0) return 0.0
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    
    // acosh(x) = ln(x + sqrt(x^2 - 1))
    val sqrtTerm = sqrt(x * x - 1.0)
    return ln(x + sqrtTerm)
}

fun acosh(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x < 1.0f) return Float.NaN
    if (x == 1.0f) return 0.0f
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    
    val sqrtTerm = sqrt(x * x - 1.0f)
    return ln(x + sqrtTerm)
}

fun asinh(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    if (doubleIsInfinite(x)) {
        return if (x > 0.0) Double.POSITIVE_INFINITY else Double.NEGATIVE_INFINITY
    }
    
    // asinh(x) = ln(x + sqrt(x^2 + 1))
    val sqrtTerm = sqrt(x * x + 1.0)
    return ln(x + sqrtTerm)
}

fun asinh(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    if (floatIsInfinite(x)) {
        return if (x > 0.0f) Float.POSITIVE_INFINITY else Float.NEGATIVE_INFINITY
    }
    
    val sqrtTerm = sqrt(x * x + 1.0f)
    return ln(x + sqrtTerm)
}

fun atanh(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (abs(x) >= 1.0) return Double.NaN
    if (x == 0.0) return if (x < 0.0) -0.0 else 0.0
    
    // atanh(x) = 0.5 * ln((1+x)/(1-x))
    return 0.5 * ln((1.0 + x) / (1.0 - x))
}

fun atanh(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (abs(x) >= 1.0f) return Float.NaN
    if (x == 0.0f) return if (x < 0.0f) -0.0f else 0.0f
    
    return 0.5f * ln((1.0f + x) / (1.0f - x))
}

fun sign(x: Double): Double =
    if (doubleIsNaN(x) || x == 0.0) x else if (x < 0.0) -1.0 else 1.0

fun sign(x: Float): Float =
    if (floatIsNaN(x) || x == 0.0f) x else if (x < 0.0f) -1.0f else 1.0f

fun hypot(x: Double, y: Double): Double {
    if (doubleIsNaN(x) || doubleIsNaN(y)) return Double.NaN
    if (doubleIsInfinite(x) || doubleIsInfinite(y)) return Double.POSITIVE_INFINITY
    if (x == 0.0 && y == 0.0) return 0.0
    
    // hypot(x, y) = sqrt(x^2 + y^2) with overflow protection
    val absX = abs(x)
    val absY = abs(y)
    
    if (absX < absY) {
        val temp = absX
        return absY * sqrt(1.0 + (temp / absY) * (temp / absY))
    } else {
        val temp = absY
        return absX * sqrt(1.0 + (temp / absX) * (temp / absX))
    }
}

fun hypot(x: Float, y: Float): Float {
    if (floatIsNaN(x) || floatIsNaN(y)) return Float.NaN
    if (floatIsInfinite(x) || floatIsInfinite(y)) return Float.POSITIVE_INFINITY
    if (x == 0.0f && y == 0.0f) return 0.0f
    
    val absX = abs(x)
    val absY = abs(y)
    
    if (absX < absY) {
        val temp = absX
        return absY * sqrt(1.0f + (temp / absY) * (temp / absY))
    } else {
        val temp = absY
        return absX * sqrt(1.0f + (temp / absX) * (temp / absX))
    }
}

fun ulp(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (doubleIsInfinite(x)) return Double.POSITIVE_INFINITY
    if (abs(x) == Double.MAX_VALUE) return x * 2.0
    
    val bits = x.toRawBits()
    val exp = ((bits ushr 52) and 0x7FF).toInt()
    
    if (exp == 0) {
        // Subnormal or zero
        val minNormal = Double.fromBits(0x0010000000000000L)
        return minNormal
    }
    
    val mantissaBits = bits and 0x000FFFFFFFFFFFFFL
    val expBits = (exp - 1023).toLong() shl 52
    return Double.fromBits(expBits)
}

fun ulp(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (floatIsInfinite(x)) return Float.POSITIVE_INFINITY
    if (abs(x) == Float.MAX_VALUE) return x * 2.0f
    
    val bits = x.toRawBits()
    val exp = ((bits ushr 23) and 0xFF).toInt()
    
    if (exp == 0) {
        val minNormal = Float.fromBits(0x00800000)
        return minNormal
    }
    
    val mantissaBits = bits and 0x007FFFFF
    val expBits = (exp - 127) shl 23
    return Float.fromBits(expBits)
}

fun nextUp(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x == Double.POSITIVE_INFINITY) return Double.POSITIVE_INFINITY
    if (x == Double.NEGATIVE_INFINITY) return -Double.MAX_VALUE
    
    if (x == 0.0 && x < 0.0) {
        // -0.0 -> smallest positive
        return Double.fromBits(1L)
    }
    
    val bits = x.toRawBits()
    if (x >= 0.0) {
        return Double.fromBits(bits + 1)
    } else {
        return Double.fromBits(bits - 1)
    }
}

fun nextUp(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x == Float.POSITIVE_INFINITY) return Float.POSITIVE_INFINITY
    if (x == Float.NEGATIVE_INFINITY) return -Float.MAX_VALUE
    
    if (x == 0.0f && x < 0.0f) {
        return Float.fromBits(1)
    }
    
    val bits = x.toRawBits()
    if (x >= 0.0f) {
        return Float.fromBits(bits + 1)
    } else {
        return Float.fromBits(bits - 1)
    }
}

fun nextDown(x: Double): Double {
    if (doubleIsNaN(x)) return Double.NaN
    if (x == Double.NEGATIVE_INFINITY) return Double.NEGATIVE_INFINITY
    if (x == Double.POSITIVE_INFINITY) return Double.MAX_VALUE
    
    if (x == 0.0 && x > 0.0) {
        // +0.0 -> smallest negative
        return Double.fromBits(0x8000000000000001L)
    }
    
    val bits = x.toRawBits()
    if (x > 0.0) {
        return Double.fromBits(bits - 1)
    } else {
        return Double.fromBits(bits + 1)
    }
}

fun nextDown(x: Float): Float {
    if (floatIsNaN(x)) return Float.NaN
    if (x == Float.NEGATIVE_INFINITY) return Float.NEGATIVE_INFINITY
    if (x == Float.POSITIVE_INFINITY) return Float.MAX_VALUE
    
    if (x == 0.0f && x > 0.0f) {
        return Float.fromBits(0x80000001)
    }
    
    val bits = x.toRawBits()
    if (x > 0.0f) {
        return Float.fromBits(bits - 1)
    } else {
        return Float.fromBits(bits + 1)
    }
}

fun roundToInt(x: Float): Int {
    if (floatIsNaN(x)) throw IllegalArgumentException("Cannot convert NaN to Int")
    if (floatIsInfinite(x)) throw IllegalArgumentException("Cannot convert Infinity to Int")
    return round(x).toInt()
}

fun roundToInt(x: Double): Int {
    if (doubleIsNaN(x)) throw IllegalArgumentException("Cannot convert NaN to Int")
    if (doubleIsInfinite(x)) throw IllegalArgumentException("Cannot convert Infinity to Int")
    return round(x).toInt()
}

fun roundToLong(x: Float): Long {
    if (floatIsNaN(x)) throw IllegalArgumentException("Cannot convert NaN to Long")
    if (floatIsInfinite(x)) throw IllegalArgumentException("Cannot convert Infinity to Long")
    return round(x).toLong()
}

fun roundToLong(x: Double): Long {
    if (doubleIsNaN(x)) throw IllegalArgumentException("Cannot convert NaN to Long")
    if (doubleIsInfinite(x)) throw IllegalArgumentException("Cannot convert Infinity to Long")
    return round(x).toLong()
}

fun max(a: Double, b: Double): Double {
    if (doubleIsNaN(a)) return b
    if (doubleIsNaN(b)) return a
    return if (a >= b) a else b
}

fun max(a: Float, b: Float): Float {
    if (floatIsNaN(a)) return b
    if (floatIsNaN(b)) return a
    return if (a >= b) a else b
}

fun max(a: Int, b: Int): Int = if (a >= b) a else b

fun max(a: Long, b: Long): Long = if (a >= b) a else b

fun min(a: Double, b: Double): Double {
    if (doubleIsNaN(a)) return b
    if (doubleIsNaN(b)) return a
    return if (a <= b) a else b
}

fun min(a: Float, b: Float): Float {
    if (floatIsNaN(a)) return b
    if (floatIsNaN(b)) return a
    return if (a <= b) a else b
}

fun min(a: Int, b: Int): Int = if (a <= b) a else b

fun min(a: Long, b: Long): Long = if (a <= b) a else b
