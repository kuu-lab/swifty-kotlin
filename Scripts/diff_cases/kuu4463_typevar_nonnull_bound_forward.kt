// KUU-4463: a caller type variable `T : Any` forwarded to a callee type
// parameter with the same non-null bound must satisfy the bound check,
// for inferred, reified, and nullable-projection forwarding alike.
fun <T : Any> g(): T? = null
fun <T : Any> f(): T? = g()

inline fun <reified T : Any> gRei(): T? = null
inline fun <reified T : Any> fRei(): T? = gRei()

class Box<T>(val v: T?)
fun <T : Any> gBox(): Box<T?> = Box(null)
fun <T : Any> fBox(): Box<T?> = gBox()

fun main() {
    println(f<String>() == null)
    println(fRei<Int>() == null)
    println(fBox<Long>().v == null)
}
