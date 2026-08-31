@file:Suppress("UNCHECKED_CAST")

package kotlin.comparisons

import kotlin.Comparator

// KSP-309 / KSP-461
// Comparator factory, composition, null-ordering and value-comparison functions
// are bundled Kotlin source. The only residual Swift entry point is the generic
// comparison core (`__kk_comparable_compareTo`), reached through `compareTo` on a
// `Comparable<*>` receiver.
//
// "thenComparing" in the MIGRATION-COMP-001 TODO corresponds to the KSwiftK-specific
// API surface: thenComparator (takes (T, T) -> Int) and thenDescending (takes (T, T) -> Int).

// --- Internal helpers --------------------------------------------------------

private fun compareNullable(a: Comparable<*>?, b: Comparable<*>?): Int {
    return compareValues(a, b)
}

// Natural-order comparison for values whose static type carries no `Comparable`
// bound (e.g. `Array<T>.binarySearch`). The comparison itself is performed by the
// generic comparison core, which panics for values that are not comparable.
internal fun <T> compareValuesUnchecked(a: T?, b: T?): Int {
    if (a == null) return if (b == null) 0 else -1
    if (b == null) return 1
    return (a as Comparable<Any>).compareTo(b)
}

// --- compareValues / compareValuesBy ----------------------------------------

public fun <T : Comparable<*>> compareValues(a: T?, b: T?): Int {
    if (a == null) return if (b == null) 0 else -1
    if (b == null) return 1
    return (a as Comparable<Any>).compareTo(b)
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

// --- compareBy ---------------------------------------------------------------

public fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b -> compareNullable(selector(a), selector(b)) }

public fun <T, K> compareBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    Comparator { a, b -> comparator.compare(selector(a), selector(b)) }

public fun <T> compareBy(
    selector1: (T) -> Comparable<*>?,
    selector2: (T) -> Comparable<*>?
): Comparator<T> = Comparator { a, b -> compareValuesBy(a, b, selector1, selector2) }

public fun <T> compareBy(
    selector1: (T) -> Comparable<*>?,
    selector2: (T) -> Comparable<*>?,
    selector3: (T) -> Comparable<*>?
): Comparator<T> = Comparator { a, b -> compareValuesBy(a, b, selector1, selector2, selector3) }

public fun <T> compareBy(vararg selectors: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b ->
        var result = 0
        for (selector in selectors) {
            val current = compareNullable(selector(a), selector(b))
            if (current != 0) {
                result = current
                break
            }
        }
        result
    }

// --- compareByDescending -----------------------------------------------------

public fun <T> compareByDescending(selector: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b -> compareNullable(selector(b), selector(a)) }

public fun <T, K> compareByDescending(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    Comparator { a, b -> comparator.compare(selector(b), selector(a)) }

// --- naturalOrder / reverseOrder --------------------------------------------

public fun <T : Comparable<T>> naturalOrder(): Comparator<T> =
    Comparator { a, b -> a.compareTo(b) }

public fun <T : Comparable<T>> reverseOrder(): Comparator<T> =
    Comparator { a, b -> b.compareTo(a) }

// --- nullsFirst / nullsLast --------------------------------------------------

public fun <T : Any> nullsFirst(comparator: Comparator<in T>): Comparator<T?> =
    Comparator { a, b ->
        if (a == null) {
            if (b == null) 0 else -1
        } else if (b == null) {
            1
        } else {
            comparator.compare(a, b)
        }
    }

public fun <T : Comparable<T>> nullsFirst(): Comparator<T?> = nullsFirst(naturalOrder<T>())

public fun <T : Any> nullsLast(comparator: Comparator<in T>): Comparator<T?> =
    Comparator { a, b ->
        if (a == null) {
            if (b == null) 0 else 1
        } else if (b == null) {
            -1
        } else {
            comparator.compare(a, b)
        }
    }

public fun <T : Comparable<T>> nullsLast(): Comparator<T?> = nullsLast(naturalOrder<T>())

// KSwiftK-specific receiver forms of the two wrappers above. Unlike the
// top-level functions these accept a nullable element type as well
// (`compareBy<Int?> { it }.nullsFirst()`), so the null handling is inlined
// instead of delegating to the `T : Any` overloads.

public fun <T> Comparator<in T>.nullsFirst(): Comparator<T?> {
    val self = this
    return Comparator { a, b ->
        if (a == null) {
            if (b == null) 0 else -1
        } else if (b == null) {
            1
        } else {
            self.compare(a, b)
        }
    }
}

public fun <T> Comparator<in T>.nullsLast(): Comparator<T?> {
    val self = this
    return Comparator { a, b ->
        if (a == null) {
            if (b == null) 0 else 1
        } else if (b == null) {
            -1
        } else {
            self.compare(a, b)
        }
    }
}

// --- Comparator<T>.reversed --------------------------------------------------

public fun <T> Comparator<T>.reversed(): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r == 0) 0 else -r
    }
}

// --- Comparator<T>.thenBy ----------------------------------------------------

public fun <T> Comparator<T>.thenBy(selector: (T) -> Comparable<*>?): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else compareNullable(selector(a), selector(b))
    }
}

public fun <T, K> Comparator<T>.thenBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else comparator.compare(selector(a), selector(b))
    }
}

// --- Comparator<T>.thenByDescending -----------------------------------------

public fun <T> Comparator<T>.thenByDescending(selector: (T) -> Comparable<*>?): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else compareNullable(selector(b), selector(a))
    }
}

public fun <T, K> Comparator<T>.thenByDescending(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else comparator.compare(selector(b), selector(a))
    }
}

// --- Comparator<T>.thenDescending / thenComparator ---------------------------

public fun <T> Comparator<T>.thenDescending(comparator: (T, T) -> Int): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else {
            val r2 = comparator(a, b)
            if (r2 == 0) 0 else -r2
        }
    }
}

public fun <T> Comparator<T>.thenComparator(comparison: (T, T) -> Int): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r != 0) r else comparison(a, b)
    }
}
