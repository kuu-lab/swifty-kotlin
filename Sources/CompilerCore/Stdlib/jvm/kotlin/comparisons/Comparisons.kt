@file:kotlin.jvm.JvmName("ComparisonsKt")
package kotlin.comparisons
fun <T: Comparable<*>> compareValues(a: T?, b: T?): Int {
    if (a === b) return 0
    if (a == null) return -1
    if (b == null) return 1
    return (a as Comparable<Any?>).compareTo(b)
}
