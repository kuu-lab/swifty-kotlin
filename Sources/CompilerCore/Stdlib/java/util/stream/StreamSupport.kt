package java.util.stream

internal fun <T> streamSequence(iteratorFactory: () -> Iterator<T>): Sequence<T> =
    Sequence(iteratorFactory)

internal fun <T> Sequence<T>.streamLimit(maxSize: Long): Sequence<T> {
    val source = this
    return streamSequence {
        val iterator = source.iterator()
        object : Iterator<T> {
            var remaining = maxSize

            override fun hasNext(): Boolean = remaining > 0 && iterator.hasNext()

            override fun next(): T {
                if (!hasNext()) throw NoSuchElementException()
                remaining--
                return iterator.next()
            }
        }
    }
}

internal fun <T> Sequence<T>.streamSkip(count: Long): Sequence<T> {
    val source = this
    return streamSequence {
        val iterator = source.iterator()
        object : Iterator<T> {
            var remaining = count

            private fun skipElements() {
                while (remaining > 0 && iterator.hasNext()) {
                    iterator.next()
                    remaining--
                }
            }

            override fun hasNext(): Boolean {
                skipElements()
                return iterator.hasNext()
            }

            override fun next(): T {
                skipElements()
                if (!iterator.hasNext()) throw NoSuchElementException()
                return iterator.next()
            }
        }
    }
}

internal fun <T> Sequence<T>.streamCount(): Long {
    val iterator = iterator()
    var count = 0L
    while (iterator.hasNext()) {
        iterator.next()
        count++
    }
    return count
}
