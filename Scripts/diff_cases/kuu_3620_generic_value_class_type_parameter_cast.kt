// KUU-3620: casting an Any? backing property to a generic value-class type
// parameter must return the erased value without recursing at runtime.
@JvmInline
value class R<T>(val a: Any?) {
    fun typed(): T = a as T
}

fun main() {
    val r = R<Int>(19)
    println(r.typed() == 19)
}
