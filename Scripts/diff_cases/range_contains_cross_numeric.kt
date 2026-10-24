// KUU-3228: cross-type `in`/`!in` on numeric ranges. On the JVM a literal
// `x in a..b` lowers to the promoted-bound comparison
// `a <= x && x <= b`, while `x in r` / `r.contains(x)` on a range variable
// resolves the `ClosedRange<T>.contains(U)` extension (value.toT() first).

fun inInt(x: Long): Boolean = x in 1..2
fun notInInt(x: Long): Boolean = x !in 1..2
fun inLong(x: Int): Boolean = x in 1L..2L
fun notInLong(x: Int): Boolean = x !in 1L..2L
fun inIntB(x: Byte): Boolean = x in 1..2
fun inIntS(x: Short): Boolean = x in 1..2
fun inLongB(x: Byte): Boolean = x in 1L..2L
fun inChar(x: Char): Boolean = x in 'a'..'z'
fun inFloat(x: Double): Boolean = x in 1.0f..2.0f
fun notInFloat(x: Double): Boolean = x !in 1.0f..2.0f
fun inDouble(x: Float): Boolean = x in 1.0..2.0
fun notInDouble(x: Float): Boolean = x !in 1.0..2.0
fun inFloatNeg(x: Double): Boolean = x in (-2.0f)..(-1.0f)

fun main() {
    // Integral crossings: bounds promote, never truncate.
    println(inInt(1L))
    println(inInt(3L))
    println(inInt(3000000000L))
    println(notInInt(3L))
    println(inLong(1))
    println(inLong(3))
    println(notInLong(3))
    println(inIntB(1))
    println(inIntS(2))
    println(inLongB(2))
    println(inChar('b'))
    println(inChar('B'))
    // Double in a Float range literal: bounds promote to Double, so a
    // Double just past the last Float bound stays outside.
    println(inFloat(1.5))
    println(inFloat(2.0))
    println(inFloat(2.0000000000000004))
    println(inFloat(1.0000000000000002))
    println(inFloat(0.9999999999999999))
    println(inFloat(Double.NaN))
    println(notInFloat(3.0))
    println(notInFloat(1.5))
    println(inFloatNeg(-1.5))
    println(inFloatNeg(-2.5))
    // Float in a Double range literal: the operand widens to Double.
    println(inDouble(1.5f))
    println(inDouble(3.0f))
    println(notInDouble(3.0f))
    println(notInDouble(1.5f))
    // Range variables resolve the extension: value.toFloat() membership.
    val rf = 1.0f..2.0f
    val dv: Double = 2.0000000000000004
    println(dv in rf)
    println(rf.contains(dv))
    val rd = 1.0..2.0
    val fv: Float = 1.5f
    println(fv in rd)
    println(rd.contains(fv))
}
