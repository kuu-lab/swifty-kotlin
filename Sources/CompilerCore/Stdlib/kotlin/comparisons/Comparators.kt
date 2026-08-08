package kotlin.comparisons

import kotlin.Comparator
import kotlin.internal.KsSymbolName

// KSP-309 / KSP-461
// The kotlin.comparisons surface (factories, composition, null wrappers and
// compareValues*) lives in this file. Only the erased comparison core stays in
// the runtime: comparing two `Comparable<*>` values requires the dynamic type
// of the boxed operand, which source Kotlin cannot express without an unchecked
// cast to `Comparable<Any>`.
//
// "thenComparing" in the MIGRATION-COMP-001 TODO corresponds to the KSwiftK-specific
// API surface: thenComparator (takes (T, T) -> Int) and thenDescending (takes (T, T) -> Int).

// --- Internal helpers --------------------------------------------------------

@KsSymbolName("__kk_comparable_compareTo")
private external fun __kkComparableCompareTo(a: Any, b: Any): Int

private fun compareNullable(a: Comparable<*>?, b: Comparable<*>?): Int {
    return compareValues(a, b)
}

// --- compareValues / compareValuesBy -----------------------------------------

// NOTE: kotlin-stdlib constrains this to `<T : Comparable<*>>`; the bound is
// omitted because star-projected upper bounds are not checkable yet
// (KSWIFTK-SEMA-BOUND rejects `Int` against `Comparable<*>`).
public fun <T> compareValues(a: T?, b: T?): Int {
    if (a == null) return if (b == null) 0 else -1
    if (b == null) return 1
    return __kkComparableCompareTo(a!!, b!!)
}

public fun <T> compareValuesBy(a: T, b: T, selector: (T) -> Any?): Int =
    compareValues(selector(a), selector(b))

public fun <T> compareValuesBy(a: T, b: T, vararg selectors: (T) -> Any?): Int {
    var i = 0
    while (i < selectors.size) {
        val selector = selectors[i]
        val diff = compareValues(selector(a), selector(b))
        if (diff != 0) return diff
        i += 1
    }
    return 0
}

public fun <T, K> compareValuesBy(a: T, b: T, comparator: Comparator<in K>, selector: (T) -> K): Int =
    comparator.compare(selector(a), selector(b))

// --- compareBy ---------------------------------------------------------------

public fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b -> compareNullable(selector(a), selector(b)) }

public fun <T> compareBy(vararg selectors: (T) -> Any?): Comparator<T> =
    Comparator { a, b ->
        var result = 0
        var i = 0
        while (i < selectors.size) {
            val selector = selectors[i]
            val diff = compareValues(selector(a), selector(b))
            if (diff != 0) {
                result = diff
                i = selectors.size
            } else {
                i += 1
            }
        }
        result
    }

public fun <T, K> compareBy(comparator: Comparator<in K>, selector: (T) -> K): Comparator<T> =
    Comparator { a, b -> comparator.compare(selector(a), selector(b)) }

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

// --- Comparator<T>.reversed --------------------------------------------------

public fun <T> Comparator<T>.reversed(): Comparator<T> {
    val self = this
    return Comparator { a, b ->
        val r = self.compare(a, b)
        if (r == 0) 0 else -r
    }
}

// --- nullsFirst / nullsLast --------------------------------------------------

public fun <T> nullsFirst(comparator: Comparator<in T>): Comparator<T?> =
    Comparator { a, b ->
        if (a == null) {
            if (b == null) 0 else -1
        } else if (b == null) {
            1
        } else {
            comparator.compare(a!!, b!!)
        }
    }

public fun <T : Comparable<T>> nullsFirst(): Comparator<T?> = nullsFirst(naturalOrder<T>())

public fun <T> nullsLast(comparator: Comparator<in T>): Comparator<T?> =
    Comparator { a, b ->
        if (a == null) {
            if (b == null) 0 else 1
        } else if (b == null) {
            -1
        } else {
            comparator.compare(a!!, b!!)
        }
    }

public fun <T : Comparable<T>> nullsLast(): Comparator<T?> = nullsLast(naturalOrder<T>())

// KSwiftK-specific receiver forms of the null wrappers (kotlin-stdlib only has
// the top-level ones). They used to be synthetic Comparator members backed by
// kk_comparator_nulls_first/last.
public fun <T> Comparator<T>.nullsFirst(): Comparator<T?> = nullsFirst<T>(this)

public fun <T> Comparator<T>.nullsLast(): Comparator<T?> = nullsLast<T>(this)

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
