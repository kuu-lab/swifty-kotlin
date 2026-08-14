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

// KSP-631: preserve the original iterator and expose it as a one-shot lazy sequence.
public fun <T> Iterator<T>.asSequence(): Sequence<T> {
    val source = this
    var used = false
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> {
            if (used) throw IllegalStateException("Sequence can be consumed only once.")
            used = true
            return source
        }
    }
}
