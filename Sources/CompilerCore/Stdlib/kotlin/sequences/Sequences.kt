package kotlin.sequences

// MIGRATION-SEQ-001 / KSP-441〜447
// Lightweight lazy pipeline building blocks.

internal fun requireOrThrow(value: Boolean, lazyMessage: () -> String) {
    if (!value) throw IllegalArgumentException(lazyMessage())
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

public fun <T> Sequence<T>.asSequence(): Sequence<T> = this

public fun <T> Sequence<T>.asIterable(): Iterable<T> {
    val source = this
    return object : Iterable<T> {
        override fun iterator(): Iterator<T> = source.iterator()
    }
}
