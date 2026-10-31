// KUU-3785: a JVM checkcast never rejects null, so `null as T` to an
// unbounded type parameter returns the null sentinel instead of throwing.
// Parameters with a non-null upper bound still NPE on the erasure's
// null assertion, matching JVM.
@Suppress("UNCHECKED_CAST")
fun <T> uncheckedCastNull(): T = null as T

@Suppress("UNCHECKED_CAST")
fun <T : Any> uncheckedCastNullBounded(): T = null as T

interface Iface

@Suppress("UNCHECKED_CAST")
fun <T : Iface> uncheckedCastNullIface(): T = null as T

fun main() {
    val a: Int? = uncheckedCastNull<Int>()
    println("int:" + if (a == null) "OK" else "FAIL:$a")
    val b: String? = uncheckedCastNull<String>()
    println("str:" + if (b == null) "OK" else "FAIL:$b")
    try {
        uncheckedCastNullBounded<Any>()
        println("bounded:no-throw")
    } catch (e: NullPointerException) {
        println("bounded:NPE")
    } catch (e: Throwable) {
        println("bounded:other")
    }
    try {
        uncheckedCastNullIface<Iface>()
        println("iface:no-throw")
    } catch (e: NullPointerException) {
        println("iface:NPE")
    } catch (e: Throwable) {
        println("iface:other")
    }
}
