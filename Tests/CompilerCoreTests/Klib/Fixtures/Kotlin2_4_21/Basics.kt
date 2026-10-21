package kliblatest

const val MAGIC: Int = 42

fun add(a: Int, b: Int): Int = a + b

fun overloaded(value: Int): Int = value + 100

fun overloaded(value: Long): Long = value + 200L

fun choose(flag: Boolean, a: Int, b: Int): Int = if (flag) a else b

fun defaults(first: Int = 7, second: Int = first + 5): Int = first + second

fun callDefaults(): Int = defaults(second = 30)

fun Int.offset(delta: Int = 3): Int = this + delta

fun callOffset(): Int = 5.offset()

fun count(vararg values: Int): Int = values.size

fun callEmptyVararg(): Int = count()

fun callNonEmptyVararg(): Int = count(1, 2, 3)

class Counter(val start: Int = 10) {
    var value: Int = start

    fun increase(step: Int = 2): Int {
        value = value + step
        return value
    }
}

fun callCounterDefaults(): Int = Counter().increase()

open class Base {
    open fun number(value: Int = 13): Int = value
}

class Derived : Base() {
    override fun number(value: Int): Int = value + 1
    fun directSuper(): Int = super.number(20)
}

fun callVirtualDefault(): Int {
    val base: Base = Derived()
    return base.number()
}

fun callDerivedDefault(): Int = Derived().number()

fun keep(value: Any, spare: Int = 0): Any = value

fun callKeep(): Any = keep(42)

fun <T> genericKeep(value: T, spare: Int = 0): T = value

fun callGenericKeep(): Any = genericKeep(44)

fun Any.primitiveReceiver(spare: Int = 0): Boolean = this is Int

fun callPrimitiveReceiver(): Boolean = 42.primitiveReceiver()

class Held(val value: Any, spare: Int = 0)

fun callHeld(): Any = Held(45).value

private var defaultCount: Int = 0

private fun nextDefault(): Int {
    defaultCount = defaultCount + 1
    return defaultCount
}

fun once(value: Int = nextDefault()): Int = value

private fun hidden(): Int = 40

internal fun internalHelper(): Int = hidden() + 2

fun callInternal(): Int = internalHelper()

fun <T> identity(value: T): T = value

fun highSurrogate(): String = "\uD800"

fun lowSurrogate(): String = "\uDC00"

fun markers(): String = "\uE800\uE000"

fun supplementary(): String = "\uD83D\uDE00"

fun embeddedNull(): String = "A\u0000B"
