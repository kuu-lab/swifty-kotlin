/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib native-wasm/src/kotlin/collections/AbstractMutableSet.kt.
 */

package kotlin.collections

/**
 * Provides a skeletal implementation of the [MutableSet] interface.
 */
public abstract class AbstractMutableSet<E> protected constructor() : AbstractMutableCollection<E>(), MutableSet<E> {
    abstract override val size: Int
    abstract override fun iterator(): MutableIterator<E>

    abstract override fun add(element: E): Boolean

    override fun addAll(elements: Collection<E>): Boolean {
        var changed = false
        for (element in elements) {
            if (add(element)) changed = true
        }
        return changed
    }

    override fun remove(element: E): Boolean {
        val iterator = iterator()
        while (iterator.hasNext()) {
            if (iterator.next() == element) {
                iterator.remove()
                return true
            }
        }
        return false
    }

    override fun removeAll(elements: Collection<E>): Boolean {
        var changed = false
        for (element in elements) {
            while (remove(element)) changed = true
        }
        return changed
    }

    override fun retainAll(elements: Collection<E>): Boolean {
        var changed = false
        val iterator = iterator()
        while (iterator.hasNext()) {
            if (!elements.contains(iterator.next())) {
                iterator.remove()
                changed = true
            }
        }
        return changed
    }

    override fun clear() {
        val iterator = iterator()
        while (iterator.hasNext()) {
            iterator.next()
            iterator.remove()
        }
    }

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
