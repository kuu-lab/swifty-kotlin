// KSP-673: inferring a generic type argument from a lambda whose body mixes a
// non-null branch (String) with a nullable receiver slot (String?) must widen to
// the shared nullable base (String?), not all the way to Any?. A wrong lub of
// [String, String?] -> Any? produced "Conflicting bounds for type variable:
// inferred Any? is not a subtype of String?" and blocked source-backed
// AtomicArray<T> CAS loops.
class Box<T>(val tag: Int)

fun <T> Box<T>.load(): T? = null

fun <T> Box<T>.transformOnce(transform: (T?) -> T?): T? {
    val old = load()
    return transform(old)
}

fun main() {
    val box = Box<String?>(1)
    val result = box.transformOnce { (it ?: "x") + "y" }
    println(result)

    val ints = Box<Int?>(2)
    val summed = ints.transformOnce { (it ?: 7) + 1 }
    println(summed)
}
