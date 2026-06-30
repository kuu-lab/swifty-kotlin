package golden.sema

class Container<T>(val item: T)

// Read-only access via star projection
fun readContainer(c: Container<*>): Any? = c.item

// Star projection in function parameter (type erasure)
fun eraseType(list: List<*>): Int = list.size

// Star projection: accepting any Container
fun acceptAny(c: Container<*>) {
    val v = c.item
}

// Declaration-site covariant (out T) + star projection: tests substituteArg(.out) path
class OutBox<out T>(val value: T)

fun readOutBox(b: OutBox<*>): Any? = b.value

// Use-site out in nested type arg + star: direct DEBT-SEMA-004 crash path
class Wrapper<T>(val items: List<out T>)

fun readWrapper(w: Wrapper<*>) {
    val x = w.items
}
