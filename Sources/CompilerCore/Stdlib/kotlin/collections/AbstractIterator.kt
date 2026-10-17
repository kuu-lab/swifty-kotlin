/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/AbstractIterator.kt>.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

public interface Iterator<out T> {
    @KsSymbolName("kk_iterator_hasNext")
    public operator fun hasNext(): Boolean

    /**
     * Returns the next element in the iteration, or throws [NoSuchElementException]
     * if the iteration has no more elements.
     */
    @KsSymbolName("kk_iterator_next")
    public operator fun next(): T
}

public abstract class AbstractIterator<T> : Iterator<T> {
    private var state = State.NotReady
    private var nextValue: T? = null

    override fun hasNext(): Boolean {
        require(state != State.Failed)
        return when (state) {
            State.Done -> false
            State.Ready -> true
            else -> tryToComputeNext()
        }
    }

    override fun next(): T {
        if (!hasNext()) throw NoSuchElementException()
        state = State.NotReady
        @Suppress("UNCHECKED_CAST")
        val result = nextValue as T
        nextValue = null
        return result
    }

    private fun tryToComputeNext(): Boolean {
        state = State.Failed
        computeNext()
        return state == State.Ready
    }

    /**
     * This callback method should call one of these two methods:
     *
     * * [setNext] with the next value of the iteration
     * * [done] to indicate there are no more elements
     *
     * Failure to call either method will result in the iteration terminating with a failed state
     */
    protected abstract fun computeNext(): Unit

    protected fun setNext(value: T): Unit {
        nextValue = value
        state = State.Ready
    }

    protected fun done() {
        state = State.Done
    }
}

private enum class State {
    Ready,
    NotReady,
    Done,
    Failed
}
