@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

operator fun <T> List<T>.component1(): T = null!!
operator fun <T> List<T>.component2(): T = null!!
operator fun <T> List<T>.component3(): T = null!!
operator fun <T> List<T>.component4(): T = null!!
operator fun <T> List<T>.component5(): T = null!!

fun <T> Iterable<T>.first(): T = null!!
fun <T> List<T>.first(): T = null!!
fun <T> Iterable<T>.last(): T = null!!
fun <T> List<T>.last(): T = null!!
fun <T> Iterable<T>.firstOrNull(): T? = null!!
fun <T> List<T>.firstOrNull(): T? = null!!
fun <T> Iterable<T>.lastOrNull(): T? = null!!
fun <T> List<T>.lastOrNull(): T? = null!!
fun <T> Iterable<T>.single(): T = null!!
fun <T> List<T>.single(): T = null!!
// Inline predicate extensions need their real bodies for caller-side expansion.
inline fun <T> Iterable<T>.single(predicate: (T) -> Boolean): T {
    var single: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) throw IllegalArgumentException("Collection contains more than one matching element.")
            single = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return single as T
}
fun <T> List<T>.single(predicate: (T) -> Boolean): T = null!!
fun <T> Iterable<T>.singleOrNull(): T? = null!!
fun <T> List<T>.singleOrNull(): T? = null!!
inline fun <T> Iterable<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var single: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) return null
            single = element
            found = true
        }
    }
    return if (found) single else null
}
fun <T> List<T>.singleOrNull(predicate: (T) -> Boolean): T? = null
fun <T> Iterable<T>.elementAt(index: Int): T = null!!
fun <T> Iterable<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T = null!!
fun <T> Iterable<T>.elementAtOrNull(index: Int): T? = null!!
