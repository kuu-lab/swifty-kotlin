@file:kotlin.jvm.JvmName("ComparisonsKt__ComparisonsKt")
package kotlin.comparisons
private class ComparisonSelector<T>(private val selector: (T) -> Comparable<*>?): Comparator<T> {
    override fun compare(a: T, b: T): Int = compareValues(selector(a), selector(b))
}
internal fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> = ComparisonSelector(selector)
