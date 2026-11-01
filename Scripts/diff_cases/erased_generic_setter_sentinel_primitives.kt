// A virtual setter of a property declared as a type parameter must receive a
// boxed value: the override's bridge checkcasts it, and raw -0.0 or
// Long.MIN_VALUE bits equal the runtime null sentinel.
open class Slot<T>(initial: T) {
    open var value: T = initial
}

class DoubleSlot : Slot<Double>(0.5) {
    override var value: Double = 1.0
}

class LongSlot : Slot<Long>(1L) {
    override var value: Long = 2L
}

class FloatSlot : Slot<Float>(1.0f) {
    override var value: Float = 2.0f
}

fun main() {
    val d: Slot<Double> = DoubleSlot()
    d.value = -0.0
    println(d.value)
    println(1.0 / d.value)
    d.value += 1.5
    println(d.value)

    val l: Slot<Long> = LongSlot()
    l.value = Long.MIN_VALUE
    println(l.value)
    l.value -= 0L
    println(l.value == Long.MIN_VALUE)

    val f: Slot<Float> = FloatSlot()
    f.value = -0.0f
    println(f.value)
}
