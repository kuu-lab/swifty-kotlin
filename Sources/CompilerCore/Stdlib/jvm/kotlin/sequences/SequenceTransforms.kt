@file:kotlin.jvm.JvmName("SequencesKt")
package kotlin.sequences


// Shared implementation adapted from Stdlib/kotlin/sequences/SequenceTransformHOF.kt.
// MIGRATION-SEQ-002 / KSP-441
// Core higher-order transform functions for source-backed Sequence pipelines.

private class TransformingSequence<T, R>(
    private val source: Sequence<T>,
    private val transform: (T) -> R
) : Sequence<R> {
    override fun iterator(): Iterator<R> = object : Iterator<R> {
        private val sourceIterator = source.iterator()

        override fun hasNext(): Boolean = sourceIterator.hasNext()
        override fun next(): R = transform(sourceIterator.next())
    }
}

public fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R> {
    return TransformingSequence(this, transform)
}

public fun <T, R> Sequence<T>.mapIndexed(transform: (Int, T) -> R): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): R {
                val currentIndex = index
                index = index + 1
                return transform(currentIndex, sourceIterator.next())
            }
        }
    }
}

public fun <T, R : Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: R? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    val transformed = transform(item)
                    if (transformed != null) {
                        nextItem = transformed
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
            }

            override fun next(): R {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                val result = nextItem as R
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (predicate(item)) {
                        nextItem = item
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (!predicate(item)) {
                        nextItem = item
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.filterIndexed(predicate: (Int, T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var index = 0
            var nextState = -2
            var nextItem: T? = null

            override fun hasNext(): Boolean {
                if (nextState == -1) return false
                if (nextState == 0) return true
                while (sourceIterator.hasNext()) {
                    val currentIndex = index
                    index = index + 1
                    val item = sourceIterator.next()
                    if (predicate(currentIndex, item)) {
                        nextItem = item
                        nextState = 0
                        return true
                    }
                }
                nextState = -1
                return false
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.onEach(action: (T) -> Unit): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): T {
                val item = sourceIterator.next()
                action(item)
                return item
            }
        }
    }
}

public fun <T> Sequence<T>.onEachIndexed(action: (Int, T) -> Unit): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var index = 0
            override fun hasNext(): Boolean = sourceIterator.hasNext()
            override fun next(): T {
                val currentIndex = index
                index = index + 1
                val item = sourceIterator.next()
                action(currentIndex, item)
                return item
            }
        }
    }
}

public fun <T, R : Any> Sequence<T>.mapIndexedNotNull(transform: (Int, T) -> R?): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            var nextState = -2
            var nextItem: R? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val currentIndex = index
                    index = index + 1
                    val item = sourceIterator.next()
                    val transformed = transform(currentIndex, item)
                    if (transformed != null) {
                        nextItem = transformed
                        nextState = 0
                        return
                    }
                }
                nextState = -1
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): R {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                val result = nextItem as R
                nextItem = null
                return result
            }
        }
    }
}

@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Sequence<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(sourceIterator.next()).iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

@kotlin.jvm.JvmName("flatMapIterable")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(sourceIterator.next()).iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public fun <T, R> Sequence<T>.flatMapIndexed(transform: (Int, T) -> Sequence<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(index, sourceIterator.next()).iterator()
                    index = index + 1
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

@kotlin.jvm.JvmName("flatMapIndexedIterable")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public fun <T, R> Sequence<T>.flatMapIndexed(transform: (Int, T) -> Iterable<R>): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var index = 0
            var currentIterator: Iterator<R> = emptySequence<R>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = transform(index, sourceIterator.next()).iterator()
                    index = index + 1
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): R {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

public fun <T> Sequence<Sequence<T>>.flatten(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<T> = emptySequence<T>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = sourceIterator.next().iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): T {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}

@kotlin.jvm.JvmName("flattenSequenceOfIterable")
public fun <T> Sequence<Iterable<T>>.flatten(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var currentIterator: Iterator<T> = emptySequence<T>().iterator()

            fun ensureNext() {
                while (!currentIterator.hasNext()) {
                    if (!sourceIterator.hasNext()) return
                    currentIterator = sourceIterator.next().iterator()
                }
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return currentIterator.hasNext()
            }

            override fun next(): T {
                ensureNext()
                if (!currentIterator.hasNext()) throw NoSuchElementException()
                return currentIterator.next()
            }
        }
    }
}


public fun <T : Any> Sequence<T?>.filterNotNull(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (item != null) {
                        nextItem = item
                        nextState = 0
                        return
                    }
                }
                nextState = -1
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                nextState = -2
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T : Any> Sequence<T?>.requireNoNulls(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()

            override fun hasNext(): Boolean = sourceIterator.hasNext()

            override fun next(): T {
                val item = sourceIterator.next()
                if (item == null) throw IllegalArgumentException("null element found in sequence")
                return item as T
            }
        }
    }
}

public operator fun <T> Sequence<T>.plus(element: T): Sequence<T> =
    sequenceOf(this, sequenceOf(element)).flatten()

public operator fun <T> Sequence<T>.plus(elements: Array<out T>): Sequence<T> =
    sequenceOf(this, elements.asSequence()).flatten()

public operator fun <T> Sequence<T>.plus(elements: Iterable<T>): Sequence<T> =
    sequenceOf(this, elements.asSequence()).flatten()

public operator fun <T> Sequence<T>.plus(elements: Sequence<T>): Sequence<T> =
    sequenceOf(this, elements).flatten()
