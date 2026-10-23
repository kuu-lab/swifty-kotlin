package kotlin.text

import kotlin.jvm.internal.__jvmUpperChar
import kotlin.jvm.internal.__jvmWhitespace
import kotlin.jvm.internal.__jvmSpaceChar

public fun Char.uppercaseChar(): Char = __jvmUpperChar(this)

public fun Char.isWhitespace(): Boolean = __jvmWhitespace(this) || __jvmSpaceChar(this)

public fun checkRadix(radix: Int): Int {
    if (radix < 2 || radix > 36) throw IllegalArgumentException("radix $radix was not in valid range 2..36")
    return radix
}
