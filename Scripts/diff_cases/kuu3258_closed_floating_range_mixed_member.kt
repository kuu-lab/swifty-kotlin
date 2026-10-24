// KUU-3258: `x in r` / `r.contains(x)` resolving to the mixed-type
// `ClosedRange<Float>.contains(Double)` / `ClosedRange<Double>.contains(Float)`
// (and the other cross-type overloads) lowers an unqualified `contains(...)`
// member call on the implicit extension receiver inside the bundled extension
// body. That implicit member call dispatches through `.itableDynamic`; a
// runtime floating-point range box registers no Kotlin itable, so the call
// used to trap with "Virtual dispatch failed: method not found in
// vtable/itable" instead of probing the runtime representation first.

class CustomFloatRange : ClosedRange<Float> {
    override val start: Float get() = 1.0f
    override val endInclusive: Float get() = 10.0f
    override fun contains(value: Float): Boolean {
        println("custom contains $value")
        return value == 42.0f || (value >= start && value <= endInclusive)
    }
    override fun isEmpty(): Boolean = false
}

// Inherits the interface's compiled `contains`/`isEmpty` defaults from the
// stdlib artifact — dispatch must reach those bodies through the itable
// rather than trapping on a missing entry (KUU-3258).
class DefaultFloatRange : ClosedRange<Float> {
    override val start: Float get() = 4.0f
    override val endInclusive: Float get() = 8.0f
}

// An enum never runs a constructor when it is boxed into an interface, so
// its itable is populated at the box site — the same imported source-backed
// defaults must register there too (KUU-3258).
enum class Direction(override val start: Int, override val endInclusive: Int) : ClosedRange<Int> {
    LOW(1, 5), HIGH(10, 20);
}

fun inDoubleOnFloat(range: ClosedFloatingPointRange<Float>, value: Double): Boolean = value in range
fun memberDoubleOnFloat(range: ClosedFloatingPointRange<Float>, value: Double): Boolean = range.contains(value)
fun inFloatOnDouble(range: ClosedFloatingPointRange<Double>, value: Float): Boolean = value in range
fun memberFloatOnDouble(range: ClosedFloatingPointRange<Double>, value: Float): Boolean = range.contains(value)
fun inDoubleOnClosed(range: ClosedRange<Float>, value: Double): Boolean = value in range
fun inFloatOnClosed(range: ClosedRange<Double>, value: Float): Boolean = value in range

fun main() {
    val rf: ClosedFloatingPointRange<Float> = 1.0f..3.0f
    println(2.0 in rf)
    println(5.0 in rf)
    println(2.0f in rf)
    println(inDoubleOnFloat(rf, 2.5))
    println(memberDoubleOnFloat(rf, 9.5))
    println(rf.isEmpty())

    val rd: ClosedFloatingPointRange<Double> = 1.0..3.0
    println(2.0f in rd)
    println(5.0f in rd)
    println(inFloatOnDouble(rd, 2.5f))
    println(memberFloatOnDouble(rd, 9.5f))

    val crf: ClosedRange<Float> = 1.0f..3.0f
    println(2.0 in crf)
    println(9.0 in crf)
    println(inDoubleOnClosed(crf, 2.5))
    println(inDoubleOnClosed(crf, 9.5))

    val crd: ClosedRange<Double> = 1.0..3.0
    println(inFloatOnClosed(crd, 2.5f))
    println(inFloatOnClosed(crd, 9.5f))
    println(crd.isEmpty())

    val empty: ClosedFloatingPointRange<Double> = 3.0..1.0
    println(empty.isEmpty())
    println(2.0 in empty)

    val custom: ClosedRange<Float> = CustomFloatRange()
    println(5.0 in custom)
    println(42.0 in custom)
    println(custom.isEmpty())

    val dir: ClosedRange<Int> = Direction.LOW
    println(3 in dir)
    println(7 in dir)
    println(dir.isEmpty())

    val defaults: ClosedRange<Float> = DefaultFloatRange()
    println(5.0f in defaults)
    println(9.0f in defaults)
    println(5.0 in defaults)
    println(defaults.isEmpty())
}
