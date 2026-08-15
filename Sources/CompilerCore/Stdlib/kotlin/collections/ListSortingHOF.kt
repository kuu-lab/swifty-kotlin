package kotlin.collections

import kotlin.random.Random

// MIGRATION-COL-006
// List sorting/comparison HOFs migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//
// These inline implementations are used by bundled List call sites. Legacy
// synthetic ABI registrations remain only as compatibility fallbacks outside
// the bundled source path.

public inline fun <T : Comparable<T>> List<T>.sorted(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T, R : Comparable<R>> List<T>.sortedBy(selector: (T) -> R): List<T> {
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val element = this[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) > 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T, R : Comparable<R>> List<T>.sortedByDescending(selector: (T) -> R): List<T> {
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val element = this[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) < 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T> List<T>.sortedWith(comparator: Comparator<T>): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && comparator.compare(result[insertAt - 1], element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T : Comparable<T>> List<T>.sortedDescending(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) < 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T : Comparable<T>> MutableList<T>.sort() {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (this[j + 1] < this[j]) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T : Comparable<T>> MutableList<T>.sortDescending() {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (this[j + 1] > this[j]) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T, R : Comparable<R>> MutableList<T>.sortBy(selector: (T) -> R) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (selector(this[j + 1]) < selector(this[j])) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T, R : Comparable<R>> MutableList<T>.sortByDescending(selector: (T) -> R) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (selector(this[j + 1]) > selector(this[j])) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T> MutableList<T>.sortWith(comparator: Comparator<T>) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (comparator.compare(this[j + 1], this[j]) < 0) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public inline fun <T> List<T>.sortedWith(comparison: (T, T) -> Int): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && comparison(result[insertAt - 1], element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public inline fun <T> MutableList<T>.sortWith(comparison: (T, T) -> Int) {
    if (size <= 1) return
    var i = 0
    while (i < size - 1) {
        var j = 0
        while (j < size - i - 1) {
            if (comparison(this[j + 1], this[j]) < 0) {
                val tmp = this[j]
                this[j] = this[j + 1]
                this[j + 1] = tmp
            }
            j++
        }
        i++
    }
}

public fun <T> List<T>.shuffled(): List<T> = shuffled(Random.Default)

public fun <T> List<T>.shuffled(random: Random): List<T> {
    val result = mutableListOf<T>()
    var copyIndex = 0
    while (copyIndex < size) {
        result.add(this[copyIndex])
        copyIndex++
    }

    var i = result.size - 1
    while (i > 0) {
        val j = random.nextInt(i + 1)
        val tmp = result[i]
        result[i] = result[j]
        result[j] = tmp
        i--
    }
    return result
}
