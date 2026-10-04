@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
import kotlin.collections.arrayOfUninitializedElements

fun main() {
    val values: Array<String?> = arrayOfUninitializedElements(2)
    values[0] = "ready"
    values[1] = null
    println(values.size)
    println(values.toList())
    val empty: Array<Int> = arrayOfUninitializedElements(0)
    println(empty.size)
    try { arrayOfUninitializedElements<Any>(-1) } catch (e: IllegalArgumentException) { println(e.message) }
    println(arrayListOf<Int>())
    println(arrayListOf(3, 1, 3))
}
