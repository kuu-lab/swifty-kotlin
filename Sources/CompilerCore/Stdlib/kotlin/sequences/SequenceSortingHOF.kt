package kotlin.sequences

// MIGRATION-SEQ-005
// Sequence sorting HOFs migrated to Kotlin source.
// Kept in a separate file with package kotlin.sequences to avoid FQ-name collisions
// with the List sorting extensions in kotlin.collections/ListSortingHOF.kt.
//
// Migration source:
//   Sources/Runtime/RuntimeSequence.swift
//
// Migrated: sorted, sortedBy, sortedByDescending, sortedDescending, sortedWith

public fun <T : Comparable<T>> Sequence<T>.sorted(): Sequence<T> {
    val elements = this.toList()
    val result = mutableListOf<T>()
    var i = 0
    while (i < elements.size) {
        val element = elements[i]
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result.asSequence()
}

public fun <T, R : Comparable<R>> Sequence<T>.sortedBy(selector: (T) -> R): Sequence<T> {
    val elements = this.toList()
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < elements.size) {
        val element = elements[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) > 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result.asSequence()
}

public fun <T, R : Comparable<R>> Sequence<T>.sortedByDescending(selector: (T) -> R): Sequence<T> {
    val elements = this.toList()
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < elements.size) {
        val element = elements[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) < 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result.asSequence()
}

public fun <T : Comparable<T>> Sequence<T>.sortedDescending(): Sequence<T> =
    sorted().reversed().asSequence()

public fun <T> Sequence<T>.sortedWith(comparator: Comparator<in T>): Sequence<T> {
    val source = this
    return object : Sequence<T> {
        override fun iterator(): Iterator<T> {
            val elements = source.toList()
            val result = mutableListOf<T>()
            var i = 0
            while (i < elements.size) {
                val element = elements[i]
                var insertAt = result.size
                while (insertAt > 0 && comparator.compare(result[insertAt - 1], element) > 0) {
                    insertAt--
                }
                result.add(insertAt, element)
                i++
            }
            return result.iterator()
        }
    }
}
