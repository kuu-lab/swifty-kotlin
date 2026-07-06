package kotlin.sequences

import kotlin.collections.IndexedValue

private external fun <T> kk_indexed_value_new(index: Int, value: T): IndexedValue<T>

// MIGRATION-SEQ-006 / KSP-441
// Sequence transform HOFs migrated to Kotlin source-backed lazy object pipelines.
// Migration source: Sources/Runtime/RuntimeSequence.swift
// Functions: map, mapIndexed, mapNotNull, mapIndexedNotNull, filter,
//            filterNot, filterIndexed, filterNotNull, filterIsInstance,
//            requireNoNulls, flatMap, flatMapIndexed, onEach, onEachIndexed,
//            withIndex

public fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (T) -> R = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (T) -> R = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (T) -> R = localTransform

                override fun hasNext(): Boolean = iterator.hasNext()
                override fun next(): R = (transform)(iterator.next())
            }
        }
    }
}

public fun <T, R> Sequence<T>.mapIndexed(transform: (index: Int, T) -> R): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (Int, T) -> R = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (Int, T) -> R = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (Int, T) -> R = localTransform
                var index = 0

                override fun hasNext(): Boolean = iterator.hasNext()

                override fun next(): R {
                    val currentIndex = index
                    index += 1
                    return (transform)(currentIndex, iterator.next())
                }
            }
        }
    }
}

public fun <T, R : Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (T) -> R? = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (T) -> R? = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (T) -> R? = localTransform
                var nextState = -1
                var nextItem: R? = null

                override fun hasNext(): Boolean {
                    if (nextState == -1) {
                        while (iterator.hasNext()) {
                            val mapped = (transform)(iterator.next())
                            if (mapped != null) {
                                nextItem = mapped
                                nextState = 1
                                return true
                            }
                        }
                        nextState = 0
                    }
                    return nextState == 1
                }

                override fun next(): R {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    val result = nextItem!!
                    nextItem = null
                    nextState = -1
                    return result
                }
            }
        }
    }
}

public fun <T, R : Any> Sequence<T>.mapIndexedNotNull(transform: (index: Int, T) -> R?): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (Int, T) -> R? = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (Int, T) -> R? = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (Int, T) -> R? = localTransform
                var index = 0
                var nextState = -1
                var nextItem: R? = null

                override fun hasNext(): Boolean {
                    if (nextState == -1) {
                        while (iterator.hasNext()) {
                            val currentIndex = index
                            index += 1
                            val mapped = (transform)(currentIndex, iterator.next())
                            if (mapped != null) {
                                nextItem = mapped
                                nextState = 1
                                return true
                            }
                        }
                        nextState = 0
                    }
                    return nextState == 1
                }

                override fun next(): R {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    val result = nextItem!!
                    nextItem = null
                    nextState = -1
                    return result
                }
            }
        }
    }
}

public fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T> {
    val capturedSource = this
    val capturedPredicate = predicate
    return object : Sequence<T> {
        val sourceSequence = capturedSource
        val predicateFunction: (T) -> Boolean = capturedPredicate

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            val localPredicate: (T) -> Boolean = predicateFunction
            return object : Iterator<T> {
                val iterator = sourceIterator
                val predicate: (T) -> Boolean = localPredicate
                var nextState = -1
                var nextItem: T? = null

                override fun hasNext(): Boolean {
                    if (nextState == -1) {
                        while (iterator.hasNext()) {
                            val item = iterator.next()
                            if ((predicate)(item)) {
                                nextItem = item
                                nextState = 1
                                return true
                            }
                        }
                        nextState = 0
                    }
                    return nextState == 1
                }

                override fun next(): T {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    val result = nextItem
                    nextItem = null
                    nextState = -1
                    return result as T
                }
            }
        }
    }
}

public fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T> {
    val capturedSource = this
    val capturedPredicate = predicate
    return object : Sequence<T> {
        val sourceSequence = capturedSource
        val predicateFunction: (T) -> Boolean = capturedPredicate

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            val localPredicate: (T) -> Boolean = predicateFunction
            return object : Iterator<T> {
                val iterator = sourceIterator
                val predicate: (T) -> Boolean = localPredicate
                var nextState = -1
                var nextItem: T? = null

                override fun hasNext(): Boolean {
                    if (nextState == -1) {
                        while (iterator.hasNext()) {
                            val item = iterator.next()
                            if (!(predicate)(item)) {
                                nextItem = item
                                nextState = 1
                                return true
                            }
                        }
                        nextState = 0
                    }
                    return nextState == 1
                }

                override fun next(): T {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    val result = nextItem
                    nextItem = null
                    nextState = -1
                    return result as T
                }
            }
        }
    }
}

public fun <T> Sequence<T>.filterIndexed(predicate: (index: Int, T) -> Boolean): Sequence<T> {
    val capturedSource = this
    val capturedPredicate = predicate
    return object : Sequence<T> {
        val sourceSequence = capturedSource
        val predicateFunction: (Int, T) -> Boolean = capturedPredicate

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            val localPredicate: (Int, T) -> Boolean = predicateFunction
            return object : Iterator<T> {
                val iterator = sourceIterator
                val predicate: (Int, T) -> Boolean = localPredicate
                var index = 0
                var nextState = -1
                var nextItem: T? = null

                override fun hasNext(): Boolean {
                    if (nextState == -1) {
                        while (iterator.hasNext()) {
                            val currentIndex = index
                            index += 1
                            val item = iterator.next()
                            if ((predicate)(currentIndex, item)) {
                                nextItem = item
                                nextState = 1
                                return true
                            }
                        }
                        nextState = 0
                    }
                    return nextState == 1
                }

                override fun next(): T {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    val result = nextItem
                    nextItem = null
                    nextState = -1
                    return result as T
                }
            }
        }
    }
}

public fun <T : Any> Sequence<T?>.filterNotNull(): Sequence<T> {
    val capturedSource = this
    return object : Sequence<T> {
        val sourceSequence = capturedSource

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            return object : Iterator<T> {
                val iterator = sourceIterator
                var nextState = -1
                var nextItem: T? = null

                override fun hasNext(): Boolean {
                    if (nextState == -1) {
                        while (iterator.hasNext()) {
                            val item = iterator.next()
                            if (item != null) {
                                nextItem = item
                                nextState = 1
                                return true
                            }
                        }
                        nextState = 0
                    }
                    return nextState == 1
                }

                override fun next(): T {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    val result = nextItem!!
                    nextItem = null
                    nextState = -1
                    return result
                }
            }
        }
    }
}

public inline fun <reified R> Sequence<*>.filterIsInstance(): Sequence<R> =
    this.filter { it is R }.map { it as R }

public fun <T : Any> Sequence<T?>.requireNoNulls(): Sequence<T> {
    val capturedSource = this
    return object : Sequence<T> {
        val sourceSequence = capturedSource

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            return object : Iterator<T> {
                val iterator = sourceIterator

                override fun hasNext(): Boolean = iterator.hasNext()

                override fun next(): T {
                    val item = iterator.next()
                    if (item == null) throw IllegalArgumentException("null element found in sequence.")
                    return item!!
                }
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (T) -> Iterable<R> = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (T) -> Iterable<R> = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (T) -> Iterable<R> = localTransform
                var itemIterator: Iterator<R>? = null

                override fun hasNext(): Boolean {
                    while (true) {
                        val current = itemIterator
                        if (current != null && current.hasNext()) return true
                        if (!iterator.hasNext()) return false
                        itemIterator = (transform)(iterator.next()).iterator()
                    }
                }

                override fun next(): R {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    return itemIterator!!.next()
                }
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Sequence<R>): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (T) -> Sequence<R> = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (T) -> Sequence<R> = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (T) -> Sequence<R> = localTransform
                var itemIterator: Iterator<R>? = null

                override fun hasNext(): Boolean {
                    while (true) {
                        val current = itemIterator
                        if (current != null && current.hasNext()) return true
                        if (!iterator.hasNext()) return false
                        itemIterator = (transform)(iterator.next()).iterator()
                    }
                }

                override fun next(): R {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    return itemIterator!!.next()
                }
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMapIndexed(transform: (index: Int, T) -> Iterable<R>): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (Int, T) -> Iterable<R> = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (Int, T) -> Iterable<R> = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (Int, T) -> Iterable<R> = localTransform
                var index = 0
                var itemIterator: Iterator<R>? = null

                override fun hasNext(): Boolean {
                    while (true) {
                        val current = itemIterator
                        if (current != null && current.hasNext()) return true
                        if (!iterator.hasNext()) return false
                        val currentIndex = index
                        index += 1
                        itemIterator = (transform)(currentIndex, iterator.next()).iterator()
                    }
                }

                override fun next(): R {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    return itemIterator!!.next()
                }
            }
        }
    }
}

public fun <T, R> Sequence<T>.flatMapIndexed(transform: (index: Int, T) -> Sequence<R>): Sequence<R> {
    val capturedSource = this
    val capturedTransform = transform
    return object : Sequence<R> {
        val sourceSequence = capturedSource
        val transformFunction: (Int, T) -> Sequence<R> = capturedTransform

        override fun iterator(): Iterator<R> {
            val sourceIterator = sourceSequence.iterator()
            val localTransform: (Int, T) -> Sequence<R> = transformFunction
            return object : Iterator<R> {
                val iterator = sourceIterator
                val transform: (Int, T) -> Sequence<R> = localTransform
                var index = 0
                var itemIterator: Iterator<R>? = null

                override fun hasNext(): Boolean {
                    while (true) {
                        val current = itemIterator
                        if (current != null && current.hasNext()) return true
                        if (!iterator.hasNext()) return false
                        val currentIndex = index
                        index += 1
                        itemIterator = (transform)(currentIndex, iterator.next()).iterator()
                    }
                }

                override fun next(): R {
                    if (!hasNext()) throw NoSuchElementException("Sequence contains no more elements.")
                    return itemIterator!!.next()
                }
            }
        }
    }
}

public fun <T> Sequence<T>.onEach(action: (T) -> Unit): Sequence<T> {
    val capturedSource = this
    val capturedAction = action
    return object : Sequence<T> {
        val sourceSequence = capturedSource
        val actionFunction: (T) -> Unit = capturedAction

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            val localAction: (T) -> Unit = actionFunction
            return object : Iterator<T> {
                val iterator = sourceIterator
                val action: (T) -> Unit = localAction

                override fun hasNext(): Boolean = iterator.hasNext()

                override fun next(): T {
                    val item = iterator.next()
                    (action)(item)
                    return item
                }
            }
        }
    }
}

public fun <T> Sequence<T>.onEachIndexed(action: (index: Int, T) -> Unit): Sequence<T> {
    val capturedSource = this
    val capturedAction = action
    return object : Sequence<T> {
        val sourceSequence = capturedSource
        val actionFunction: (Int, T) -> Unit = capturedAction

        override fun iterator(): Iterator<T> {
            val sourceIterator = sourceSequence.iterator()
            val localAction: (Int, T) -> Unit = actionFunction
            return object : Iterator<T> {
                val iterator = sourceIterator
                val action: (Int, T) -> Unit = localAction
                var index = 0

                override fun hasNext(): Boolean = iterator.hasNext()

                override fun next(): T {
                    val currentIndex = index
                    index += 1
                    val item = iterator.next()
                    (action)(currentIndex, item)
                    return item
                }
            }
        }
    }
}

public fun <T> Sequence<T>.withIndex(): Sequence<IndexedValue<T>> {
    val capturedSource = this
    return object : Sequence<IndexedValue<T>> {
        val sourceSequence = capturedSource

        override fun iterator(): Iterator<IndexedValue<T>> {
            val sourceIterator = sourceSequence.iterator()
            return object : Iterator<IndexedValue<T>> {
                val iterator = sourceIterator
                var index = 0

                override fun hasNext(): Boolean = iterator.hasNext()

                override fun next(): IndexedValue<T> {
                    val currentIndex = index
                    index += 1
                    return kk_indexed_value_new(currentIndex, iterator.next())
                }
            }
        }
    }
}
