/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache 2.0 license.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/ranges/Ranges.kt
 * and libraries/stdlib/common/src/generated/_Ranges.kt.
 */

package kotlin.ranges

// KSP-1281: package-top-level `kotlin.ranges` declarations.
//
// `ComparableRange`/`ComparableOpenEndRange` back the generic `rangeTo` /
// `rangeUntil` operators. Their member bodies follow upstream, but
// `ClosedRange` members use source interface dispatch, including itables
// registered by runtime-backed range factories. `OpenEndRange` interface
// members still use residual raw `__kk_range_*` handle bridges (KSP-451),
// which cannot read a generic heap range object.
// These overrides keep the members correct on the concrete classes
// themselves; interface-typed dispatch on generic open-ended ranges remains
// a residual limitation.
//
/** Returns false for null elements, otherwise delegates to the range member. */
@SinceKotlin("2.3")
@kotlin.internal.InlineOnly
public inline operator fun <T, R> R.contains(element: T?): Boolean where T : Comparable<T>, R : ClosedRange<T>, R : Iterable<T> {
    return element != null && contains(element)
}

@Deprecated("The signature violates type safety guarantees")
@DeprecatedSinceKotlin(hiddenSince = "2.3")
@Suppress(
    "UPPER_BOUND_VIOLATED_IN_TYPE_OPERATOR_OR_PARAMETER_BOUNDS_WARNING",
    "UPPER_BOUND_VIOLATED_IN_TYPE_OPERATOR_OR_PARAMETER_BOUNDS_ERROR"
)
@SinceKotlin("1.3")
@kotlin.internal.InlineOnly
public inline operator fun <T, R> R.contains(element: T?): Boolean where T : Any, R : ClosedRange<T>, R : Iterable<T> {
    return element != null && contains(element)
}

/** Returns false for null elements, otherwise delegates to the range member. */
@SinceKotlin("2.3")
@kotlin.internal.InlineOnly
public inline operator fun <T, R> R.contains(element: T?): Boolean where T : Comparable<T>, R : OpenEndRange<T>, R : Iterable<T> {
    return element != null && contains(element)
}

@Deprecated("The signature violates type safety guarantees")
@DeprecatedSinceKotlin(hiddenSince = "2.3")
@Suppress(
    "UPPER_BOUND_VIOLATED_IN_TYPE_OPERATOR_OR_PARAMETER_BOUNDS_WARNING",
    "UPPER_BOUND_VIOLATED_IN_TYPE_OPERATOR_OR_PARAMETER_BOUNDS_ERROR"
)
@SinceKotlin("1.9")
@kotlin.internal.InlineOnly
public inline operator fun <T, R> R.contains(element: T?): Boolean where T : Any, R : OpenEndRange<T>, R : Iterable<T> {
    return element != null && contains(element)
}

/**
 * Represents a range of [Comparable] values.
 */
private open class ComparableRange<T : Comparable<T>>(
    override val start: T,
    override val endInclusive: T
) : ClosedRange<T> {

    override fun contains(value: T): Boolean = value >= start && value <= endInclusive

    override fun isEmpty(): Boolean = start > endInclusive

    // `other` is only usable after an unchecked cast to the nominal T:
    // member access on the star projection fails the T : Comparable<T>
    // bound check in this sema.
    @Suppress("UNCHECKED_CAST")
    override fun equals(other: Any?): Boolean {
        if (other !is ComparableRange<*>) return false
        val o = other as ComparableRange<T>
        return isEmpty() && o.isEmpty() ||
                start == o.start && endInclusive == o.endInclusive
    }

    override fun hashCode(): Int {
        return if (isEmpty()) -1 else 31 * start.hashCode() + endInclusive.hashCode()
    }

    override fun toString(): String = "$start..$endInclusive"
}

/**
 * Creates a range from this [Comparable] value to the specified [that] value.
 *
 * This value needs to be smaller than or equal to [that] value, otherwise the returned range will be empty.
 */
public operator fun <T : Comparable<T>> T.rangeTo(that: T): ClosedRange<T> = ComparableRange(this, that)

/**
 * Represents a range of [Comparable] values.
 */
private open class ComparableOpenEndRange<T : Comparable<T>>(
    override val start: T,
    override val endExclusive: T
) : OpenEndRange<T> {

    override fun contains(value: T): Boolean = value >= start && value < endExclusive

    override fun isEmpty(): Boolean = !(start < endExclusive)

    @Suppress("UNCHECKED_CAST")
    override fun equals(other: Any?): Boolean {
        if (other !is ComparableOpenEndRange<*>) return false
        val o = other as ComparableOpenEndRange<T>
        return isEmpty() && o.isEmpty() ||
                start == o.start && endExclusive == o.endExclusive
    }

    override fun hashCode(): Int {
        return if (isEmpty()) -1 else 31 * start.hashCode() + endExclusive.hashCode()
    }

    override fun toString(): String = "$start..<$endExclusive"
}

/**
 * Creates an open-ended range from this [Comparable] value to the specified [that] value.
 *
 * This value needs to be smaller than [that] value, otherwise the returned range will be empty.
 */
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public operator fun <T : Comparable<T>> T.rangeUntil(that: T): OpenEndRange<T> = ComparableOpenEndRange(this, that)

/**
 * Ensures that this value is not less than the specified [minimumValue].
 *
 * @return this value if it's greater than or equal to the [minimumValue] or the [minimumValue] otherwise.
 */
public fun <T : Comparable<T>> T.coerceAtLeast(minimumValue: T): T {
    return if (this < minimumValue) minimumValue else this
}

/**
 * Ensures that this value is not greater than the specified [maximumValue].
 *
 * @return this value if it's less than or equal to the [maximumValue] or the [maximumValue] otherwise.
 */
public fun <T : Comparable<T>> T.coerceAtMost(maximumValue: T): T {
    return if (this > maximumValue) maximumValue else this
}

/**
 * Ensures that this value lies in the specified range.
 *
 * @return this value if it's in the range, or `range.start` if this value is less than `range.start`, or `range.endInclusive` if this value is greater than `range.endInclusive`.
 */
public fun <T : Comparable<T>> T.coerceIn(range: ClosedRange<T>): T {
    if (range is ClosedFloatingPointRange) {
        return this.coerceIn<T>(range)
    }
    if (range.isEmpty()) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: $range.")
    }
    if (this < range.start) return range.start
    if (this > range.endInclusive) return range.endInclusive
    return this
}
