// EXPECT-ACCEPT
// KUU-4408: type parameters inferred from the receiver still bind without an
// expected function type.
fun <T> T.echo(): T = this
class Box<T>(val v: T) { fun get(): T = v }
fun main() {
    val a = 1::echo
    val b = Int::echo
    val box = Box(1)
    val c = box::get
    val d = Box<Int>::get
    println(a() + b(2) + c() + d(box))
}
