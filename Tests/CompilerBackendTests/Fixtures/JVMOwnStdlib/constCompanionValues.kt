class Limits {
    companion object {
        const val MIN: Long = Long.MIN_VALUE
        const val MAX: Long = Long.MAX_VALUE
    }
}

object First { const val CODE: Int = Later.CODE + 1 }
object Later { const val CODE: Int = 65 }
object Copy { const val CODE: Int = First.CODE }

const val SHIFTED: Int = 0xFF ushr 4
const val UNSIGNED_SHIFT: Int = -1 ushr 1
const val INT_MASKED: Int = 1 shl 32
const val INT_NEGATIVE: Int = 1 shl -1
const val INT_SIGNED: Int = Int.MIN_VALUE shr 31
const val BITS: Int = (0xF0 or 0x0F) xor (0xFF and 0x0F)
const val LONG_BASE: Long = 1
const val LONG_SHIFT: Long = LONG_BASE shl 63
const val LONG_MASKED: Long = -1L ushr 64
const val LONG_UNSIGNED: Long = -1L ushr 1
const val LONG_SIGNED: Long = Long.MIN_VALUE shr 63
const val LONG_BITS: Long = (0xF0L or 0x0FL) xor (0xFFL and 0x0FL)
const val DOT: Int = 255.ushr(4)
const val NESTED: Int = (Copy.CODE shl 1) + SHIFTED
const val MIN_DIVIDED: Long = Limits.MIN / 10L
const val TEXT: String = "const" + "-of-const"
object TextCopy { const val VALUE: String = TEXT }

fun main() {
    println(Limits.MIN)
    println(Limits.MAX)
    println(First.CODE)
    println(Copy.CODE)
    println(SHIFTED)
    println(UNSIGNED_SHIFT)
    println(INT_MASKED)
    println(INT_NEGATIVE)
    println(INT_SIGNED)
    println(BITS)
    println(LONG_SHIFT)
    println(LONG_MASKED)
    println(LONG_UNSIGNED)
    println(LONG_SIGNED)
    println(LONG_BITS)
    println(DOT)
    println(NESTED)
    println(MIN_DIVIDED)
    println(TextCopy.VALUE)
}
