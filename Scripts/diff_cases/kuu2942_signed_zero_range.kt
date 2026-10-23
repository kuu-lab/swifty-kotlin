// KUU-2942: IEEE signed-zero semantics for floating-point range membership

val DOUBLE_RANGE = 0.0 .. -0.0
val FLOAT_RANGE = 0.0f .. -0.0f
val OPEN_RANGE = 0.0 ..< 1.0
val EMPTY_RANGE = 1.0 .. 0.0

class Holder { val r = 0.0 .. -0.0 }
object Obj { val r = 0.0 .. -0.0 }
class WithCompanion { companion object { val r = 0.0 .. -0.0 } }

fun makeRange() = 0.0 .. -0.0
fun makeFloatRange() = 0.0f .. -0.0f
fun paramCheck(r: ClosedFloatingPointRange<Double>) = 0.0 in r

// User-defined ClosedRange must keep interface dispatch
class Weird(val lo: Double, val hi: Double) : ClosedRange<Double> {
    override val start: Double get() = lo
    override val endInclusive: Double get() = hi
    override fun contains(value: Double): Boolean = false
    override fun isEmpty(): Boolean = false
}

fun main() {
    println("A1=" + (0.0 in DOUBLE_RANGE))
    println("A2=" + (-0.0 in DOUBLE_RANGE))
    println("A3=" + (0.0 !in DOUBLE_RANGE))
    println("A4=" + (1.0 in DOUBLE_RANGE))
    println("B1=" + (0.0f in FLOAT_RANGE))
    println("B2=" + (-0.0f in FLOAT_RANGE))
    println("B3=" + (1.0f in FLOAT_RANGE))
    println("C1=" + (0.5 in OPEN_RANGE))
    println("C2=" + (1.0 in OPEN_RANGE))
    println("D1=" + (0.5 in EMPTY_RANGE))
    println("E1=" + DOUBLE_RANGE.isEmpty())
    println("E2=" + EMPTY_RANGE.isEmpty())
    println("E3=" + DOUBLE_RANGE.contains(0.0))
    println("E4=" + DOUBLE_RANGE.contains(-0.0))
    println("E5=" + DOUBLE_RANGE.start)
    println("E6=" + DOUBLE_RANGE.endInclusive)
    println("F1=" + (0.0 in Holder().r))
    println("F2=" + (-0.0 in Obj.r))
    println("F3=" + (0.0 in WithCompanion.r))
    println("G1=" + (0.0 in makeRange()))
    println("G2=" + (-0.0 in makeRange()))
    println("G3=" + (0.0f in makeFloatRange()))
    println("H1=" + paramCheck(0.0..-0.0))
    println("I1=" + (0.0 in Weird(0.0, 1.0)))
    println("I2=" + Weird(0.0, 1.0).contains(0.0))
    println("I3=" + Weird(0.0, 1.0).isEmpty())
}
