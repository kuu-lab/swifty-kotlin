/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

package kotlin.ranges

public val UIntRange.start: UInt
    get() = first

public val UIntRange.endInclusive: UInt
    get() = last

public val UIntRange.endExclusive: UInt
    get() {
        if (last == UInt.MAX_VALUE) {
            throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
        }
        return last + 1u
    }

public fun UIntRange.equals(other: Any?): Boolean =
    this == other

public fun UIntRange.hashCode(): Int =
    if (isEmpty()) -1 else 31 * first.toInt() + last.toInt()

public fun UIntRange.toString(): String = "$first..$last"
