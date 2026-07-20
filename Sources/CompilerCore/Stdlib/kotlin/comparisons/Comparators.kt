package kotlin.comparisons

import kotlin.Comparator

// KSP-309
// Comparator factory and composition functions migrated to bundled Kotlin
// source. Residual Swift stubs still own Comparator itself, nullsFirst/nullsLast,
// compareValues*, and multi-selector compareBy overloads.
//
// "thenComparing" in the MIGRATION-COMP-001 TODO corresponds to the KSwiftK-specific
// API surface: thenComparator (takes (T, T) -> Int) and thenDescending (takes (T, T) -> Int).

// --- Internal helpers --------------------------------------------------------

private fun compareNullable(a: Comparable<*>?, b: Comparable<*>?): Int {
    return compareValues(a, b)
}

// --- compareBy ---------------------------------------------------------------

public fun <T> compareBy(selector: (T) -> Comparable<*>?): Comparator<T> =
    Comparator { a, b -> compareNullable(selector(a), selector(b)) }

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
