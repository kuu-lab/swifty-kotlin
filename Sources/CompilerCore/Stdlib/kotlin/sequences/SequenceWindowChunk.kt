package kotlin.sequences

// MIGRATION-SEQ-005 / KSP-441
// Sequence window, limiting, and zip/distinct HOFs implemented as lazy
// object-expression pipelines.  This replaces the previous runtime-bridge
// based implementation so that source-backed Sequence objects can be chained.

public fun <T> Sequence<T>.take(n: Int): Sequence<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var remaining = n

            override fun hasNext(): Boolean = remaining > 0 && sourceIterator.hasNext()

            override fun next(): T {
                if (remaining == 0 || !sourceIterator.hasNext()) {
                    throw NoSuchElementException()
                }
                remaining = remaining - 1
                return sourceIterator.next()
            }
        }
    }
}

public fun <T> Sequence<T>.takeWhile(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                if (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (predicate(item)) {
                        nextItem = item
                        nextState = 0
                    } else {
                        nextState = -1
                    }
                } else {
                    nextState = -1
                }
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): T {
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.drop(n: Int): Sequence<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var remaining = n
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (remaining > 0 && sourceIterator.hasNext()) {
                    sourceIterator.next()
                    remaining = remaining - 1
                }
                if (sourceIterator.hasNext()) {
                    nextItem = sourceIterator.next()
                    nextState = 0
                } else {
                    nextState = -1
                }
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): T {
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.dropWhile(predicate: (T) -> Boolean): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var dropped = false
            var nextState = -2
            var nextItem: T? = null

            fun ensureNext() {
                if (nextState == 0 || nextState == -1) return
                if (dropped) {
                    if (sourceIterator.hasNext()) {
                        nextItem = sourceIterator.next()
                        nextState = 0
                    } else {
                        nextState = -1
                    }
                    return
                }
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    if (!predicate(item)) {
                        dropped = true
                        nextItem = item
                        nextState = 0
                        return
                    }
                }
                nextState = -1
            }

            override fun hasNext(): Boolean {
                ensureNext()
                return nextState == 0
            }

            override fun next(): T {
                ensureNext()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

internal fun checkWindowSizeStep(size: Int, step: Int) {
    if (size <= 0 || step <= 0) {
        val message = if (size != step) {
            "Both size $size and step $step must be greater than zero."
        } else {
            "size $size must be greater than zero."
        }
        throw IllegalArgumentException(message)
    }
}

public fun <T> Sequence<T>.chunked(size: Int): Sequence<List<T>> {
    require(size > 0) { "size must be positive, but was $size" }
    val source = this
    return object : Sequence<List<T>> {
        override fun iterator(): Iterator<List<T>> = object : Iterator<List<T>> {
            val sourceIterator = source.iterator()

            override fun hasNext(): Boolean = sourceIterator.hasNext()

            override fun next(): List<T> {
                if (!sourceIterator.hasNext()) throw NoSuchElementException()
                val chunk = mutableListOf<T>()
                var i = 0
                while (i < size && sourceIterator.hasNext()) {
                    chunk.add(sourceIterator.next())
                    i = i + 1
                }
                return chunk
            }
        }
    }
}

public fun <T, R> Sequence<T>.chunked(size: Int, transform: (List<T>) -> R): Sequence<R> {
    require(size > 0) { "size must be positive, but was $size" }
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()

            override fun hasNext(): Boolean = sourceIterator.hasNext()

            override fun next(): R {
                if (!sourceIterator.hasNext()) throw NoSuchElementException()
                val chunk = mutableListOf<T>()
                var i = 0
                while (i < size && sourceIterator.hasNext()) {
                    chunk.add(sourceIterator.next())
                    i = i + 1
                }
                return transform(chunk)
            }
        }
    }
}

public fun <T> Sequence<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): Sequence<List<T>> {
    checkWindowSizeStep(size, step)
    val source = this
    return object : Sequence<List<T>> {
        override fun iterator(): Iterator<List<T>> = object : Iterator<List<T>> {
            val sourceIterator = source.iterator()
            val buffer = mutableListOf<T>()
            var nextWindow: List<T>? = null
            var nextState = -2

            fun fill() {
                while (buffer.size < size && sourceIterator.hasNext()) {
                    buffer.add(sourceIterator.next())
                }
            }

            fun advanceStep() {
                var i = 0
                while (i < step && buffer.isNotEmpty()) {
                    buffer.removeAt(0)
                    i = i + 1
                }
            }

            fun makeWindow(): List<T> {
                val result = mutableListOf<T>()
                var i = 0
                while (i < buffer.size) {
                    result.add(buffer[i])
                    i = i + 1
                }
                return result
            }

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                fill()
                if (buffer.size == size) {
                    nextWindow = makeWindow()
                    advanceStep()
                    nextState = 0
                } else if (partialWindows && buffer.isNotEmpty()) {
                    nextWindow = makeWindow()
                    advanceStep()
                    nextState = 0
                } else {
                    nextState = -1
                }
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): List<T> {
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                val result = nextWindow!!
                nextWindow = null
                return result
            }
        }
    }
}

public fun <T, R> Sequence<T>.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (List<T>) -> R
): Sequence<R> {
    checkWindowSizeStep(size, step)
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            val buffer = mutableListOf<T>()
            var nextResult: R? = null
            var nextState = -2

            fun fill() {
                while (buffer.size < size && sourceIterator.hasNext()) {
                    buffer.add(sourceIterator.next())
                }
            }

            fun advanceStep() {
                var i = 0
                while (i < step && buffer.isNotEmpty()) {
                    buffer.removeAt(0)
                    i = i + 1
                }
            }

            fun makeWindow(): List<T> {
                val result = mutableListOf<T>()
                var i = 0
                while (i < buffer.size) {
                    result.add(buffer[i])
                    i = i + 1
                }
                return result
            }

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                fill()
                if (buffer.size == size) {
                    nextResult = transform(makeWindow())
                    advanceStep()
                    nextState = 0
                } else if (partialWindows && buffer.isNotEmpty()) {
                    nextResult = transform(makeWindow())
                    advanceStep()
                    nextState = 0
                } else {
                    nextState = -1
                }
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): R {
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                val result = nextResult!!
                nextResult = null
                return result
            }
        }
    }
}

public fun <T, R> Sequence<T>.zip(other: Sequence<R>): Sequence<Pair<T, R>> {
    val source = this
    return object : Sequence<Pair<T, R>> {
        override fun iterator(): Iterator<Pair<T, R>> = object : Iterator<Pair<T, R>> {
            val left = source.iterator()
            val right = other.iterator()

            override fun hasNext(): Boolean = left.hasNext() && right.hasNext()

            override fun next(): Pair<T, R> {
                if (!hasNext()) throw NoSuchElementException()
                return Pair(left.next(), right.next())
            }
        }
    }
}

public fun <T, R, V> Sequence<T>.zip(other: Sequence<R>, transform: (T, R) -> V): Sequence<V> {
    val source = this
    return object : Sequence<V> {
        override fun iterator(): Iterator<V> = object : Iterator<V> {
            val left = source.iterator()
            val right = other.iterator()

            override fun hasNext(): Boolean = left.hasNext() && right.hasNext()

            override fun next(): V {
                if (!hasNext()) throw NoSuchElementException()
                return transform(left.next(), right.next())
            }
        }
    }
}

public fun <T> Sequence<T>.zipWithNext(): Sequence<Pair<T, T>> {
    val source = this
    return object : Sequence<Pair<T, T>> {
        override fun iterator(): Iterator<Pair<T, T>> = object : Iterator<Pair<T, T>> {
            val sourceIterator = source.iterator()
            var first = true
            var previous: T? = null
            var nextPair: Pair<T, T>? = null
            var nextState = -2

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                if (first) {
                    if (sourceIterator.hasNext()) {
                        previous = sourceIterator.next()
                        first = false
                    } else {
                        nextState = -1
                        return
                    }
                }
                if (sourceIterator.hasNext()) {
                    val current = sourceIterator.next()
                    @Suppress("UNCHECKED_CAST")
                    val prev = previous as T
                    nextPair = Pair(prev, current)
                    previous = current
                    nextState = 0
                } else {
                    nextState = -1
                }
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): Pair<T, T> {
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                val result = nextPair!!
                nextPair = null
                return result
            }
        }
    }
}

public fun <T, R> Sequence<T>.zipWithNext(transform: (T, T) -> R): Sequence<R> {
    val source = this
    return object : Sequence<R> {
        override fun iterator(): Iterator<R> = object : Iterator<R> {
            val sourceIterator = source.iterator()
            var first = true
            var previous: T? = null
            var nextResult: R? = null
            var nextState = -2

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                if (first) {
                    if (sourceIterator.hasNext()) {
                        previous = sourceIterator.next()
                        first = false
                    } else {
                        nextState = -1
                        return
                    }
                }
                if (sourceIterator.hasNext()) {
                    val current = sourceIterator.next()
                    @Suppress("UNCHECKED_CAST")
                    val prev = previous as T
                    nextResult = transform(prev, current)
                    previous = current
                    nextState = 0
                } else {
                    nextState = -1
                }
            }

            override fun hasNext(): Boolean {
                compute()
                return nextState == 0
            }

            override fun next(): R {
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                val result = nextResult!!
                nextResult = null
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.distinct(): Sequence<T> {
    val source = this
    val seen = mutableListOf<Any?>()
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    val key = item as Any?
                    if (!seen.contains(key)) {
                        seen.add(key)
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
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}

public fun <T, K> Sequence<T>.distinctBy(selector: (T) -> K): Sequence<T> {
    val source = this
    val seen = mutableListOf<Any?>()
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var nextState = -2
            var nextItem: T? = null

            fun compute() {
                if (nextState == 0 || nextState == -1) return
                while (sourceIterator.hasNext()) {
                    val item = sourceIterator.next()
                    val key = selector(item) as Any?
                    if (!seen.contains(key)) {
                        seen.add(key)
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
                compute()
                if (nextState != 0) throw NoSuchElementException()
                nextState = -2
                @Suppress("UNCHECKED_CAST")
                val result = nextItem as T
                nextItem = null
                return result
            }
        }
    }
}
