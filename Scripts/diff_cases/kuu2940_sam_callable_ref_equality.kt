// KUU-2940: `fun interface` SAM adapters wrapping callable references get JVM
// FunctionAdapter equality — equal iff the other operand implements the same
// interface and holds an equal function delegate.

fun checkEqual(x: Any, y: Any) {
    if (x != y || y != x) throw AssertionError("$x and $y should be equal")
    if (x.hashCode() != y.hashCode()) throw AssertionError("$x and $y should have the same hash code")
}

fun checkNotEqual(x: Any, y: Any) {
    if (x == y || y == x) throw AssertionError("$x and $y should NOT be equal")
}

fun interface FunInterface {
    fun invoke()
}

fun interface OtherInterface {
    fun invoke()
}

private fun id(f: FunInterface): Any = f
private fun ido(f: OtherInterface): Any = f

fun topLevel() {}

fun box(): String {
    fun local1() {}
    fun local2() {}

    checkEqual(id(::local1), id(::local1))
    checkNotEqual(id(::local1), id(::local2))

    fun String.localExt() {}

    checkEqual(id("A"::localExt), id("A"::localExt))
    checkNotEqual(id("A"::localExt), id("B"::localExt))

    fun adapted(default: String? = "", vararg va: Int): Int = 0

    checkEqual(id(::adapted), id(::adapted))

    return "OK"
}

fun main() {
    println(box())

    val sam = id(::topLevel)
    val sam2 = id(::topLevel)
    val ref: Any = ::topLevel
    val objSam: Any = object : FunInterface { override fun invoke() {} }
    val otherSam = ido(::topLevel)

    // A SAM adapter is not itself a callable reference type on the JVM.
    println(sam is Function0<*>)
    println(sam is kotlin.reflect.KFunction<*>)
    println(sam == sam2)
    println(sam.hashCode() == sam2.hashCode())

    // The adapter is not equal to the raw reference it wraps, but shares its
    // delegate hash code.
    println(ref == sam)
    println(sam == ref)
    println(sam.hashCode() == ref.hashCode())

    // Adapters of a different fun interface, or hand-written implementations,
    // are never equal to a callable-reference adapter.
    println(sam == otherSam)
    println(sam == objSam)
    println(sam == 42)
}
