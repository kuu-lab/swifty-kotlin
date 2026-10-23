@file:kotlin.jvm.JvmName("ComparisonsKt__ComparisonsKt")
package kotlin.comparisons

import kotlin.Comparator

private fun compareNullable(a: Comparable<*>?, b: Comparable<*>?): Int = compareValues(a, b)

private class ComparisonSelector<T>(
    private val selector: (T) -> Comparable<*>?,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int = if (descending) {
        compareNullable(selector(b), selector(a))
    } else {
        compareNullable(selector(a), selector(b))
    }
}

private class ComparisonSelectorWithComparator<T, K>(
    private val selector: (T) -> K,
    private val comparator: Comparator<in K>,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int = if (descending) {
        comparator.compare(selector(b), selector(a))
    } else {
        comparator.compare(selector(a), selector(b))
    }
}

private class ComparisonSelectorList<T>(
    private val selectors: Array<out (T) -> Comparable<*>?>,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int {
        for (selector in selectors) {
            val result = if (descending) {
                compareNullable(selector(b), selector(a))
            } else {
                compareNullable(selector(a), selector(b))
            }
            if (result != 0) return result
        }
        return 0
    }
}

private class NullableValuesComparator<T : Any>(
    private val comparator: Comparator<in T>,
    private val nullsFirst: Boolean
) : Comparator<T?> {
    override fun compare(a: T?, b: T?): Int {
        if (a == null) return if (b == null) 0 else if (nullsFirst) -1 else 1
        if (b == null) return if (nullsFirst) 1 else -1
        return comparator.compare(a, b)
    }
}

private class ReversedComparator<T>(private val comparator: Comparator<in T>) : Comparator<T> {
    override fun compare(a: T, b: T): Int = comparator.compare(b, a)
}

private class ThenByComparator<T>(
    private val first: Comparator<in T>,
    private val selector: (T) -> Comparable<*>?,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int {
        val result = first.compare(a, b)
        if (result != 0) return result
        return if (descending) compareNullable(selector(b), selector(a))
        else compareNullable(selector(a), selector(b))
    }
}

private class ThenByWithComparator<T, K>(
    private val first: Comparator<in T>,
    private val selector: (T) -> K,
    private val comparator: Comparator<in K>,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int {
        val result = first.compare(a, b)
        if (result != 0) return result
        return if (descending) comparator.compare(selector(b), selector(a))
        else comparator.compare(selector(a), selector(b))
    }
}

private class ThenComparator<T>(
    private val first: Comparator<in T>,
    private val second: Comparator<in T>,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int {
        val result = first.compare(a, b)
        if (result != 0) return result
        return if (descending) second.compare(b, a) else second.compare(a, b)
    }
}

private class ThenFunctionComparator<T>(
    private val first: Comparator<in T>,
    private val comparison: (T, T) -> Int,
    private val descending: Boolean = false
) : Comparator<T> {
    override fun compare(a: T, b: T): Int {
        val result = first.compare(a, b)
        if (result != 0) return result
        val next = comparison(a, b)
        return if (descending && next != 0) -next else next
    }
}

public fun <T> compareValuesBy(a: T, b: T, selector: (T) -> Comparable<*>?): Int =
    compareNullable(selector(a), selector(b))

public fun <T> compareValuesBy(
    a: T,
    b: T,
    selector1: (T) -> Comparable<*>?,
    selector2: (T) -> Comparable<*>?
): Int {
    val first = compareNullable(selector1(a), selector1(b))
    return if (first != 0) first else compareNullable(selector2(a), selector2(b))
}

public fun <T> compareValuesBy(
    a: T,
    b: T,
    selector1: (T) -> Comparable<*>?,
    selector2: (T) -> Comparable<*>?,
    selector3: (T) -> Comparable<*>?
): Int {
    val first = compareNullable(selector1(a), selector1(b))
    if (first != 0) return first
    val second = compareNullable(selector2(a), selector2(b))
    return if (second != 0) second else compareNullable(selector3(a), selector3(b))
}

public fun <T> compareValuesBy(a: T, b: T, vararg selectors: (T) -> Comparable<*>?): Int {
    for (selector in selectors) {
        val result = compareNullable(selector(a), selector(b))
        if (result != 0) return result
    }
    return 0
}

public fun <T, K> compareValuesBy(a: T, b: T, comparator: Comparator<in K>, selector: (T) -> K): Int =
    comparator.compare(selector(a), selector(b))

public fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> =
    ComparisonSelector(selector)

public fun <T, K> compareBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    ComparisonSelectorWithComparator(selector, comparator)

public fun <T> compareBy(
    selector1: (T) -> Comparable<*>?,
    selector2: (T) -> Comparable<*>?
): Comparator<T> = ComparisonSelectorList(arrayOf(selector1, selector2))

public fun <T> compareBy(
    selector1: (T) -> Comparable<*>?,
    selector2: (T) -> Comparable<*>?,
    selector3: (T) -> Comparable<*>?
): Comparator<T> = ComparisonSelectorList(arrayOf(selector1, selector2, selector3))

public fun <T> compareBy(vararg selectors: (T) -> Comparable<*>?): Comparator<T> =
    ComparisonSelectorList(selectors)

public fun <T> compareByDescending(selector: (T) -> Comparable<*>?): Comparator<T> =
    ComparisonSelector(selector, descending = true)

public fun <T, K> compareByDescending(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    ComparisonSelectorWithComparator(selector, comparator, descending = true)

public fun <T : Comparable<T>> naturalOrder(): Comparator<T> =
    ComparisonSelector<T>({ value -> value })

public fun <T : Comparable<T>> reverseOrder(): Comparator<T> =
    ComparisonSelector<T>({ value -> value }, descending = true)

public fun <T : Any> nullsFirst(comparator: Comparator<in T>): Comparator<T?> =
    NullableValuesComparator(comparator, nullsFirst = true)

public fun <T : Comparable<T>> nullsFirst(): Comparator<T?> = nullsFirst(naturalOrder<T>())

public fun <T : Any> nullsLast(comparator: Comparator<in T>): Comparator<T?> =
    NullableValuesComparator(comparator, nullsFirst = false)

public fun <T : Comparable<T>> nullsLast(): Comparator<T?> = nullsLast(naturalOrder<T>())

public fun <T> Comparator<T>.reversed(): Comparator<T> = ReversedComparator(this)

public fun <T> Comparator<T>.thenBy(selector: (T) -> Comparable<*>?): Comparator<T> =
    ThenByComparator(this, selector)

public fun <T, K> Comparator<T>.thenBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    ThenByWithComparator(this, selector, comparator)

public fun <T> Comparator<T>.thenByDescending(selector: (T) -> Comparable<*>?): Comparator<T> =
    ThenByComparator(this, selector, descending = true)

public fun <T, K> Comparator<T>.thenByDescending(
    comparator: Comparator<in K>,
    selector: (T) -> K
): Comparator<T> = ThenByWithComparator(this, selector, comparator, descending = true)

public fun <T> Comparator<T>.thenDescending(comparator: (T, T) -> Int): Comparator<T> =
    ThenFunctionComparator(this, comparator, descending = true)

public fun <T> Comparator<T>.thenComparator(comparison: (T, T) -> Int): Comparator<T> =
    ThenFunctionComparator(this, comparison)

public fun <T> Comparator<T>.thenComparing(comparison: (T, T) -> Int): Comparator<T> =
    thenComparator(comparison)

public fun <T> Comparator<T>.thenComparing(other: Comparator<in T>): Comparator<T> =
    this.then(other)

public infix fun <T> Comparator<T>.then(comparator: Comparator<in T>): Comparator<T> =
    ThenComparator(this, comparator)

public infix fun <T> Comparator<T>.thenDescending(comparator: Comparator<in T>): Comparator<T> =
    ThenComparator(this, comparator, descending = true)
