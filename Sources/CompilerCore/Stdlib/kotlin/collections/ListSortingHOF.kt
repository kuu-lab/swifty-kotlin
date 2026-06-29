package kotlin.collections

import kotlin.random.Random

// MIGRATION-COL-006
// List sorting/comparison HOFs migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeCollectionHOF.swift
//   Sources/Runtime/RuntimeCollectionHOFMaxMin.swift
//
// NOTE: Synthetic List members still route user call sites to kk_list_* ABI
// functions. These bodies are the source migration target for the follow-up
// wiring/removal step.

public fun <T> List<T>.reversed(): List<T> {
    val result = mutableListOf<T>()
    var i = size - 1
    while (i >= 0) {
        result.add(this[i])
        i--
    }
    return result
}

public fun <T : Comparable<T>> List<T>.sorted(): List<T> {
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

public fun <T, R : Comparable<R>> List<T>.sortedBy(selector: (T) -> R): List<T> {
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

public fun <T, R : Comparable<R>> List<T>.sortedByDescending(selector: (T) -> R): List<T> {
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

public fun <T> List<T>.sortedWith(comparator: (T, T) -> Int): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && comparator(result[insertAt - 1], element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
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
