package kotlin.math

fun Double.pow(x: Double): Double {
    if (this == 1.0 || x == 0.0) return 1.0
    if (this == 0.0) {
        return if (x > 0.0) 0.0 else if (x < 0.0) Double.POSITIVE_INFINITY else 1.0
    }
    if (this < 0.0 && x != x.toLong().toDouble()) {
        return Double.NaN // Negative base with non-integer exponent
    }
    if (this.isNaN() || x.isNaN()) return Double.NaN
    if (this == Double.POSITIVE_INFINITY) {
        return if (x > 0.0) Double.POSITIVE_INFINITY else if (x < 0.0) 0.0 else 1.0
    }
    if (this == Double.NEGATIVE_INFINITY) {
        val isEvenInt = x.toLong().toInt() % 2 == 0
        return if (x > 0.0) if (isEvenInt) Double.POSITIVE_INFINITY else Double.NEGATIVE_INFINITY else 0.0
    }
    if (x == Double.POSITIVE_INFINITY) {
        return if (abs(this) > 1.0) Double.POSITIVE_INFINITY else if (abs(this) < 1.0) 0.0 else 1.0
    }
    if (x == Double.NEGATIVE_INFINITY) {
        return if (abs(this) > 1.0) 0.0 else if (abs(this) < 1.0) Double.POSITIVE_INFINITY else 1.0
    }
    
    // For negative base with integer exponent, use absolute value
    val absBase = if (this < 0.0) -this else this
    val result = exp(x * ln(absBase))
    
    // Apply sign if base is negative and exponent is odd integer
    if (this < 0.0 && x == x.toLong().toDouble() && x.toLong().toInt() % 2 != 0) {
        return -result
    }
    
    return result
}

fun Float.pow(x: Float): Float {
    if (this == 1.0f || x == 0.0f) return 1.0f
    if (this == 0.0f) {
        return if (x > 0.0f) 0.0f else if (x < 0.0f) Float.POSITIVE_INFINITY else 1.0f
    }
    if (this < 0.0f && x != x.toLong().toFloat()) {
        return Float.NaN
    }
    if (this.isNaN() || x.isNaN()) return Float.NaN
    if (this == Float.POSITIVE_INFINITY) {
        return if (x > 0.0f) Float.POSITIVE_INFINITY else if (x < 0.0f) 0.0f else 1.0f
    }
    if (this == Float.NEGATIVE_INFINITY) {
        val isEvenInt = x.toLong().toInt() % 2 == 0
        return if (x > 0.0f) if (isEvenInt) Float.POSITIVE_INFINITY else Float.NEGATIVE_INFINITY else 0.0f
    }
    if (x == Float.POSITIVE_INFINITY) {
        return if (abs(this) > 1.0f) Float.POSITIVE_INFINITY else if (abs(this) < 1.0f) 0.0f else 1.0f
    }
    if (x == Float.NEGATIVE_INFINITY) {
        return if (abs(this) > 1.0f) 0.0f else if (abs(this) < 1.0f) Float.POSITIVE_INFINITY else 1.0f
    }
    
    val absBase = if (this < 0.0f) -this else this
    val result = exp(x * ln(absBase))
    
    if (this < 0.0f && x == x.toLong().toFloat() && x.toLong().toInt() % 2 != 0) {
        return -result
    }
    
    return result
}

fun Double.pow(n: Int): Double {
    var exponent = if (n < 0) -(n.toLong()) else n.toLong()
    var base = if (n < 0) 1.0 / this else this
    var result = 1.0
    while (exponent > 0L) {
        if (exponent % 2L != 0L) {
            result = result * base
        }
        base = base * base
        exponent = exponent / 2L
    }
    return result
}

fun Float.pow(n: Int): Float {
    var exponent = if (n < 0) -(n.toLong()) else n.toLong()
    var base = if (n < 0) 1.0f / this else this
    var result = 1.0f
    while (exponent > 0L) {
        if (exponent % 2L != 0L) {
            result = result * base
        }
        base = base * base
        exponent = exponent / 2L
    }
    return result
}

fun Double.roundToInt(): Int = roundToInt(this)

fun Float.roundToInt(): Int = roundToInt(this)

fun Double.roundToLong(): Long = roundToLong(this)

fun Float.roundToLong(): Long = roundToLong(this)
