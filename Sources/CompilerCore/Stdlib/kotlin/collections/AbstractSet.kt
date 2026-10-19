/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractSet.kt.
 */

package kotlin.collections

// Collection type fallbacks remain available for contexts without the bundled
// stdlib, but Set-specific synthetic shell registration is retired by KSP-704.

public abstract class AbstractSet<out E> protected constructor() : AbstractCollection<E>(), Set<E> {
    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Set<*>) return false
        var otherSize = 0
        for (element in other) {
            otherSize += 1
            var found = false
            for (ownElement in this) {
                if (ownElement == element) {
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return size == otherSize
    }

    override fun hashCode(): Int {
        var hashCode = 0
        for (element in this) {
            hashCode += element?.hashCode() ?: 0
        }
        return hashCode
    }
}
