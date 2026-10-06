package kotlin.collections

import kotlin.random.Random

// Array is not an Iterable. Reuse the indexed List view without copying the
// receiver, so callbacks still observe changes to the original array.

public fun <T> Array<out T>.take(n: Int): List<T> = asList().take(n)

public fun <T> Array<out T>.takeLast(n: Int): List<T> = asList().takeLast(n)

public fun <T> Array<out T>.drop(n: Int): List<T> = asList().drop(n)

public fun <T> Array<out T>.dropLast(n: Int): List<T> = asList().dropLast(n)

public inline fun <T> Array<out T>.takeWhile(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (!predicate(element)) break
        result.add(element)
    }
    return result
}

public inline fun <T> Array<out T>.dropWhile(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    var dropping = true
    for (element in this) {
        if (dropping && predicate(element)) continue
        dropping = false
        result.add(element)
    }
    return result
}

public fun <T> Array<out T>.slice(indices: IntRange): List<T> = asList().slice(indices)

public fun <T> Array<out T>.slice(indices: Iterable<Int>): List<T> = asList().slice(indices)

public fun <T> Array<out T>.elementAt(index: Int): T = this[index]

public fun <T> Array<out T>.elementAtOrNull(index: Int): T? =
    if (index >= 0 && index < size) this[index] else null

public inline fun <T> Array<out T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T =
    getOrElse(index, defaultValue)

public inline fun <T> Array<out T>.getOrElse(index: Int, defaultValue: (Int) -> T): T =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun <T> Array<out T>.single(): T {
    if (size == 0) throw NoSuchElementException("Array is empty.")
    if (size != 1) throw IllegalArgumentException("Array has more than one element.")
    return this[0]
}

public fun <T> Array<out T>.singleOrNull(): T? = if (size == 1) this[0] else null

public inline fun <T> Array<out T>.single(predicate: (T) -> Boolean): T {
    var result: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) throw IllegalArgumentException("Array contains more than one matching element.")
            result = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Array contains no element matching the predicate.")
    @Suppress("UNCHECKED_CAST")
    return result as T
}

public inline fun <T> Array<out T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var result: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            if (found) return null
            result = element
            found = true
        }
    }
    return result
}

public fun <T> Array<out T>.random(): T = random(Random.Default)

public fun <T> Array<out T>.random(random: Random): T {
    if (size == 0) throw NoSuchElementException("Array is empty.")
    return this[random.nextInt(size)]
}

public fun <T> Array<out T>.randomOrNull(): T? = randomOrNull(Random.Default)

public fun <T> Array<out T>.randomOrNull(random: Random): T? {
    if (size == 0) return null
    return this[random.nextInt(size)]
}
