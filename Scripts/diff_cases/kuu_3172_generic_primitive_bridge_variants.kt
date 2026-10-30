// KUU-3172: primitive parameters of generic-base overrides must checkcast
// the erased argument in the dispatch bridge; wrong types must throw
// ClassCastException while correct-type calls still dispatch.
open class Base<T> { open fun foo(x: T): Int = 42 }
open class LongB<T> { open fun foo(x: T): Long = 0L }
class DLong : LongB<Long>() { override fun foo(x: Long) = x }
class DBool : Base<Boolean>() { override fun foo(x: Boolean) = if (x) 1 else 0 }
class DDouble : Base<Double>() { override fun foo(x: Double) = x.toInt() }
class Data(val s: String)

fun box(): String {
    try {
        (DLong() as Base<Data>).foo(Data("a"))
        return "FAIL-long"
    } catch (e: ClassCastException) {}
    try {
        (DBool() as Base<Data>).foo(Data("b"))
        return "FAIL-bool"
    } catch (e: ClassCastException) {}
    try {
        (DDouble() as Base<Data>).foo(Data("c"))
        return "FAIL-double"
    } catch (e: ClassCastException) {}
    val l: LongB<Long> = DLong()
    if (l.foo(37L) != 37L) return "FAIL-dispatch-long"
    val b: Base<Boolean> = DBool()
    if (b.foo(true) != 1) return "FAIL-dispatch-bool"
    return "OK"
}

fun main() {
    println(box())
}
