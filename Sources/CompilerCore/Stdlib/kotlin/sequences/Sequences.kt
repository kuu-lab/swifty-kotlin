package kotlin.sequences

// MIGRATION-SEQ-001 / KSP-441〜447
// Sequence factory functions and lightweight lazy pipeline building blocks.

internal fun requireOrThrow(value: Boolean, lazyMessage: () -> String) {
    if (!value) throw IllegalArgumentException(lazyMessage())
}

public fun <T> emptySequence(): Sequence<T> {
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> {
            return object : Iterator<T> {
                override fun hasNext(): Boolean = false
                override fun next(): T = throw NoSuchElementException()
            }
        }
    }
}

public fun <T> sequenceOf(vararg elements: T): Sequence<T> {
    val source = elements
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            var index = 0
            override fun hasNext(): Boolean = index < source.size
            override fun next(): T {
                if (index >= source.size) throw NoSuchElementException()
                val result = source[index]
                index = index + 1
                return result
            }
        }
    }
}

public fun <T : Any> generateSequence(nextFunction: () -> T?): Sequence<T> {
    return object : Sequence<T> {
        var iterated = false

        override fun iterator(): Iterator<T> {
            if (iterated) throw IllegalStateException("This sequence can be iterated only once.")
            iterated = true
            return object : Iterator<T> {
                var item: T? = null
                var state = 0

                override fun hasNext(): Boolean {
                    if (state == 0) {
                        item = nextFunction()
                        state = 1
                    }
                    return item != null
                }

                override fun next(): T {
                    if (state == 0) {
                        item = nextFunction()
                        state = 1
                    }
                    if (item == null) throw NoSuchElementException()
                    @Suppress("UNCHECKED_CAST")
                    val result = item as T
                    item = nextFunction()
                    return result
                }
            }
        }
    }
}

public fun <T> generateSequence(seed: T, nextFunction: (T) -> T?): Sequence<T> {
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            var item: T? = seed

            override fun hasNext(): Boolean = item != null

            override fun next(): T {
                if (item == null) throw NoSuchElementException()
                @Suppress("UNCHECKED_CAST")
                val result = item as T
                item = nextFunction(result)
                return result
            }
        }
    }
}

public fun <T> Iterable<T>.asSequence(): Sequence<T> {
    val list = this.toList()
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            var index = 0
            override fun hasNext(): Boolean = index < list.size
            override fun next(): T {
                if (index >= list.size) throw NoSuchElementException()
                val result = list[index]
                index = index + 1
                return result
            }
        }
    }
}

public fun <T> Sequence<T>.constrainOnce(): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        var iterated = false

        override fun iterator(): Iterator<T> {
            if (iterated) throw IllegalStateException("This sequence can be iterated only once.")
            iterated = true
            return source.iterator()
        }
    }
}

public fun <T> Sequence<T>?.orEmpty(): Sequence<T> {
    val source = this
    if (source == null) {
        return object : Sequence<T> {
            override fun iterator(): Iterator<T> = object : Iterator<T> {
                override fun hasNext(): Boolean = false
                override fun next(): T = throw NoSuchElementException()
            }
        }
    }
    return source!!
}

public fun <T> Sequence<T>.ifEmpty(defaultValue: () -> Sequence<T>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> = object : Iterator<T> {
            val sourceIterator = source.iterator()
            var fallbackIterator: Iterator<T>? = null
            var state: Int = -1

            private fun choose() {
                if (sourceIterator.hasNext()) {
                    state = 0
                } else {
                    fallbackIterator = defaultValue().iterator()
                    state = 1
                }
            }

            override fun next(): T {
                if (state == -1) choose()
                if (state == 0) return sourceIterator.next()
                val fallback = fallbackIterator ?: throw NoSuchElementException()
                return fallback.next()
            }

            override fun hasNext(): Boolean {
                if (state == -1) choose()
                return if (state == 0) sourceIterator.hasNext() else fallbackIterator!!.hasNext()
            }
        }
    }
}
