package kotlin.collections

// KUU-1105: primitive-array overloads keep their exact element types.

public fun IntArray.toHashSet(): HashSet<Int> = asList().toHashSet()

public fun IntArray.toMutableSet(): MutableSet<Int> = asList().toMutableSet()

public fun IntArray.toSet(): Set<Int> = asList().toSet()

public fun <C : MutableCollection<in Int>> IntArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> IntArray.sortedBy(crossinline selector: (Int) -> R?): List<Int> =
    asList().sortedBy(selector)

public fun IntArray.sortedWith(comparator: Comparator<in Int>): List<Int> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> IntArray.mapTo(
    destination: C, transform: (Int) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Int>> IntArray.filterTo(
    destination: C, predicate: (Int) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun IntArray.partition(predicate: (Int) -> Boolean): Pair<List<Int>, List<Int>> {
    val matching = mutableListOf<Int>()
    val other = mutableListOf<Int>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> IntArray.groupBy(keySelector: (Int) -> K): Map<K, List<Int>> {
    val result = mutableMapOf<K, MutableList<Int>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Int>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Int>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> IntArray.groupBy(
    keySelector: (Int) -> K,
    valueTransform: (Int) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun IntArray.forEachIndexed(action: (Int, Int) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> IntArray.associate(transform: (Int) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> IntArray.associateBy(keySelector: (Int) -> K): Map<K, Int> {
    val result = mutableMapOf<K, Int>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> IntArray.associateBy(
    keySelector: (Int) -> K,
    valueTransform: (Int) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun IntArray.zip(other: IntArray): List<Pair<Int, Int>> {
    val result = mutableListOf<Pair<Int, Int>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> IntArray.zip(other: IntArray, transform: (Int, Int) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> IntArray.zip(other: Array<out R>): List<Pair<Int, R>> {
    val result = mutableListOf<Pair<Int, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> IntArray.zip(other: Array<out R>, transform: (Int, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> IntArray.zip(other: Iterable<R>): List<Pair<Int, R>> {
    val result = mutableListOf<Pair<Int, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> IntArray.zip(other: Iterable<R>, transform: (Int, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun LongArray.toHashSet(): HashSet<Long> = asList().toHashSet()

public fun LongArray.toMutableSet(): MutableSet<Long> = asList().toMutableSet()

public fun LongArray.toSet(): Set<Long> = asList().toSet()

public fun <C : MutableCollection<in Long>> LongArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> LongArray.sortedBy(crossinline selector: (Long) -> R?): List<Long> =
    asList().sortedBy(selector)

public fun LongArray.sortedWith(comparator: Comparator<in Long>): List<Long> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> LongArray.mapTo(
    destination: C, transform: (Long) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Long>> LongArray.filterTo(
    destination: C, predicate: (Long) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun LongArray.partition(predicate: (Long) -> Boolean): Pair<List<Long>, List<Long>> {
    val matching = mutableListOf<Long>()
    val other = mutableListOf<Long>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> LongArray.groupBy(keySelector: (Long) -> K): Map<K, List<Long>> {
    val result = mutableMapOf<K, MutableList<Long>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Long>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Long>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> LongArray.groupBy(
    keySelector: (Long) -> K,
    valueTransform: (Long) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun LongArray.forEachIndexed(action: (Int, Long) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> LongArray.associate(transform: (Long) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> LongArray.associateBy(keySelector: (Long) -> K): Map<K, Long> {
    val result = mutableMapOf<K, Long>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> LongArray.associateBy(
    keySelector: (Long) -> K,
    valueTransform: (Long) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun LongArray.zip(other: LongArray): List<Pair<Long, Long>> {
    val result = mutableListOf<Pair<Long, Long>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> LongArray.zip(other: LongArray, transform: (Long, Long) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> LongArray.zip(other: Array<out R>): List<Pair<Long, R>> {
    val result = mutableListOf<Pair<Long, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> LongArray.zip(other: Array<out R>, transform: (Long, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> LongArray.zip(other: Iterable<R>): List<Pair<Long, R>> {
    val result = mutableListOf<Pair<Long, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> LongArray.zip(other: Iterable<R>, transform: (Long, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun ByteArray.toHashSet(): HashSet<Byte> = asList().toHashSet()

public fun ByteArray.toMutableSet(): MutableSet<Byte> = asList().toMutableSet()

public fun ByteArray.toSet(): Set<Byte> = asList().toSet()

public fun <C : MutableCollection<in Byte>> ByteArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> ByteArray.sortedBy(crossinline selector: (Byte) -> R?): List<Byte> =
    asList().sortedBy(selector)

public fun ByteArray.sortedWith(comparator: Comparator<in Byte>): List<Byte> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> ByteArray.mapTo(
    destination: C, transform: (Byte) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Byte>> ByteArray.filterTo(
    destination: C, predicate: (Byte) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun ByteArray.partition(predicate: (Byte) -> Boolean): Pair<List<Byte>, List<Byte>> {
    val matching = mutableListOf<Byte>()
    val other = mutableListOf<Byte>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> ByteArray.groupBy(keySelector: (Byte) -> K): Map<K, List<Byte>> {
    val result = mutableMapOf<K, MutableList<Byte>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Byte>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Byte>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> ByteArray.groupBy(
    keySelector: (Byte) -> K,
    valueTransform: (Byte) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun ByteArray.forEachIndexed(action: (Int, Byte) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> ByteArray.associate(transform: (Byte) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> ByteArray.associateBy(keySelector: (Byte) -> K): Map<K, Byte> {
    val result = mutableMapOf<K, Byte>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> ByteArray.associateBy(
    keySelector: (Byte) -> K,
    valueTransform: (Byte) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun ByteArray.zip(other: ByteArray): List<Pair<Byte, Byte>> {
    val result = mutableListOf<Pair<Byte, Byte>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> ByteArray.zip(other: ByteArray, transform: (Byte, Byte) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> ByteArray.zip(other: Array<out R>): List<Pair<Byte, R>> {
    val result = mutableListOf<Pair<Byte, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> ByteArray.zip(other: Array<out R>, transform: (Byte, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> ByteArray.zip(other: Iterable<R>): List<Pair<Byte, R>> {
    val result = mutableListOf<Pair<Byte, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> ByteArray.zip(other: Iterable<R>, transform: (Byte, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun ShortArray.toHashSet(): HashSet<Short> = asList().toHashSet()

public fun ShortArray.toMutableSet(): MutableSet<Short> = asList().toMutableSet()

public fun ShortArray.toSet(): Set<Short> = asList().toSet()

public fun <C : MutableCollection<in Short>> ShortArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> ShortArray.sortedBy(crossinline selector: (Short) -> R?): List<Short> =
    asList().sortedBy(selector)

public fun ShortArray.sortedWith(comparator: Comparator<in Short>): List<Short> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> ShortArray.mapTo(
    destination: C, transform: (Short) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Short>> ShortArray.filterTo(
    destination: C, predicate: (Short) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun ShortArray.partition(predicate: (Short) -> Boolean): Pair<List<Short>, List<Short>> {
    val matching = mutableListOf<Short>()
    val other = mutableListOf<Short>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> ShortArray.groupBy(keySelector: (Short) -> K): Map<K, List<Short>> {
    val result = mutableMapOf<K, MutableList<Short>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Short>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Short>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> ShortArray.groupBy(
    keySelector: (Short) -> K,
    valueTransform: (Short) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun ShortArray.forEachIndexed(action: (Int, Short) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> ShortArray.associate(transform: (Short) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> ShortArray.associateBy(keySelector: (Short) -> K): Map<K, Short> {
    val result = mutableMapOf<K, Short>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> ShortArray.associateBy(
    keySelector: (Short) -> K,
    valueTransform: (Short) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun ShortArray.zip(other: ShortArray): List<Pair<Short, Short>> {
    val result = mutableListOf<Pair<Short, Short>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> ShortArray.zip(other: ShortArray, transform: (Short, Short) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> ShortArray.zip(other: Array<out R>): List<Pair<Short, R>> {
    val result = mutableListOf<Pair<Short, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> ShortArray.zip(other: Array<out R>, transform: (Short, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> ShortArray.zip(other: Iterable<R>): List<Pair<Short, R>> {
    val result = mutableListOf<Pair<Short, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> ShortArray.zip(other: Iterable<R>, transform: (Short, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun CharArray.toHashSet(): HashSet<Char> = asList().toHashSet()

public fun CharArray.toMutableSet(): MutableSet<Char> = asList().toMutableSet()

public fun CharArray.toSet(): Set<Char> = asList().toSet()

public fun <C : MutableCollection<in Char>> CharArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> CharArray.sortedBy(crossinline selector: (Char) -> R?): List<Char> =
    asList().sortedBy(selector)

public fun CharArray.sortedWith(comparator: Comparator<in Char>): List<Char> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> CharArray.mapTo(
    destination: C, transform: (Char) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Char>> CharArray.filterTo(
    destination: C, predicate: (Char) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun CharArray.partition(predicate: (Char) -> Boolean): Pair<List<Char>, List<Char>> {
    val matching = mutableListOf<Char>()
    val other = mutableListOf<Char>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> CharArray.groupBy(keySelector: (Char) -> K): Map<K, List<Char>> {
    val result = mutableMapOf<K, MutableList<Char>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Char>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Char>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> CharArray.groupBy(
    keySelector: (Char) -> K,
    valueTransform: (Char) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun CharArray.forEachIndexed(action: (Int, Char) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> CharArray.associate(transform: (Char) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> CharArray.associateBy(keySelector: (Char) -> K): Map<K, Char> {
    val result = mutableMapOf<K, Char>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> CharArray.associateBy(
    keySelector: (Char) -> K,
    valueTransform: (Char) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun CharArray.zip(other: CharArray): List<Pair<Char, Char>> {
    val result = mutableListOf<Pair<Char, Char>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> CharArray.zip(other: CharArray, transform: (Char, Char) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> CharArray.zip(other: Array<out R>): List<Pair<Char, R>> {
    val result = mutableListOf<Pair<Char, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> CharArray.zip(other: Array<out R>, transform: (Char, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> CharArray.zip(other: Iterable<R>): List<Pair<Char, R>> {
    val result = mutableListOf<Pair<Char, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> CharArray.zip(other: Iterable<R>, transform: (Char, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun BooleanArray.toHashSet(): HashSet<Boolean> = asList().toHashSet()

public fun BooleanArray.toMutableSet(): MutableSet<Boolean> = asList().toMutableSet()

public fun BooleanArray.toSet(): Set<Boolean> = asList().toSet()

public fun <C : MutableCollection<in Boolean>> BooleanArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> BooleanArray.sortedBy(crossinline selector: (Boolean) -> R?): List<Boolean> =
    asList().sortedBy(selector)

public fun BooleanArray.sortedWith(comparator: Comparator<in Boolean>): List<Boolean> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> BooleanArray.mapTo(
    destination: C, transform: (Boolean) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Boolean>> BooleanArray.filterTo(
    destination: C, predicate: (Boolean) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun BooleanArray.partition(predicate: (Boolean) -> Boolean): Pair<List<Boolean>, List<Boolean>> {
    val matching = mutableListOf<Boolean>()
    val other = mutableListOf<Boolean>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> BooleanArray.groupBy(keySelector: (Boolean) -> K): Map<K, List<Boolean>> {
    val result = mutableMapOf<K, MutableList<Boolean>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Boolean>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Boolean>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> BooleanArray.groupBy(
    keySelector: (Boolean) -> K,
    valueTransform: (Boolean) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun BooleanArray.forEachIndexed(action: (Int, Boolean) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> BooleanArray.associate(transform: (Boolean) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> BooleanArray.associateBy(keySelector: (Boolean) -> K): Map<K, Boolean> {
    val result = mutableMapOf<K, Boolean>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> BooleanArray.associateBy(
    keySelector: (Boolean) -> K,
    valueTransform: (Boolean) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun BooleanArray.zip(other: BooleanArray): List<Pair<Boolean, Boolean>> {
    val result = mutableListOf<Pair<Boolean, Boolean>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> BooleanArray.zip(other: BooleanArray, transform: (Boolean, Boolean) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> BooleanArray.zip(other: Array<out R>): List<Pair<Boolean, R>> {
    val result = mutableListOf<Pair<Boolean, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> BooleanArray.zip(other: Array<out R>, transform: (Boolean, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> BooleanArray.zip(other: Iterable<R>): List<Pair<Boolean, R>> {
    val result = mutableListOf<Pair<Boolean, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> BooleanArray.zip(other: Iterable<R>, transform: (Boolean, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun FloatArray.toHashSet(): HashSet<Float> = asList().toHashSet()

public fun FloatArray.toMutableSet(): MutableSet<Float> = asList().toMutableSet()

public fun FloatArray.toSet(): Set<Float> = asList().toSet()

public fun <C : MutableCollection<in Float>> FloatArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> FloatArray.sortedBy(crossinline selector: (Float) -> R?): List<Float> =
    asList().sortedBy(selector)

public fun FloatArray.sortedWith(comparator: Comparator<in Float>): List<Float> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> FloatArray.mapTo(
    destination: C, transform: (Float) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Float>> FloatArray.filterTo(
    destination: C, predicate: (Float) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun FloatArray.partition(predicate: (Float) -> Boolean): Pair<List<Float>, List<Float>> {
    val matching = mutableListOf<Float>()
    val other = mutableListOf<Float>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> FloatArray.groupBy(keySelector: (Float) -> K): Map<K, List<Float>> {
    val result = mutableMapOf<K, MutableList<Float>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Float>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Float>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> FloatArray.groupBy(
    keySelector: (Float) -> K,
    valueTransform: (Float) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun FloatArray.forEachIndexed(action: (Int, Float) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> FloatArray.associate(transform: (Float) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> FloatArray.associateBy(keySelector: (Float) -> K): Map<K, Float> {
    val result = mutableMapOf<K, Float>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> FloatArray.associateBy(
    keySelector: (Float) -> K,
    valueTransform: (Float) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun FloatArray.zip(other: FloatArray): List<Pair<Float, Float>> {
    val result = mutableListOf<Pair<Float, Float>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> FloatArray.zip(other: FloatArray, transform: (Float, Float) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> FloatArray.zip(other: Array<out R>): List<Pair<Float, R>> {
    val result = mutableListOf<Pair<Float, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> FloatArray.zip(other: Array<out R>, transform: (Float, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> FloatArray.zip(other: Iterable<R>): List<Pair<Float, R>> {
    val result = mutableListOf<Pair<Float, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> FloatArray.zip(other: Iterable<R>, transform: (Float, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}

public fun DoubleArray.toHashSet(): HashSet<Double> = asList().toHashSet()

public fun DoubleArray.toMutableSet(): MutableSet<Double> = asList().toMutableSet()

public fun DoubleArray.toSet(): Set<Double> = asList().toSet()

public fun <C : MutableCollection<in Double>> DoubleArray.toCollection(destination: C): C =
    asList().toCollection(destination)

public inline fun <R : Comparable<R>> DoubleArray.sortedBy(crossinline selector: (Double) -> R?): List<Double> =
    asList().sortedBy(selector)

public fun DoubleArray.sortedWith(comparator: Comparator<in Double>): List<Double> =
    asList().sortedWith(comparator)

public inline fun <R, C : MutableCollection<in R>> DoubleArray.mapTo(
    destination: C, transform: (Double) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <C : MutableCollection<in Double>> DoubleArray.filterTo(
    destination: C, predicate: (Double) -> Boolean
): C {
    for (element in this) if (predicate(element)) destination.add(element)
    return destination
}

public inline fun DoubleArray.partition(predicate: (Double) -> Boolean): Pair<List<Double>, List<Double>> {
    val matching = mutableListOf<Double>()
    val other = mutableListOf<Double>()
    for (element in this) {
        if (predicate(element)) matching.add(element) else other.add(element)
    }
    return Pair(matching, other)
}

@Suppress("UNCHECKED_CAST")
public inline fun <K> DoubleArray.groupBy(keySelector: (Double) -> K): Map<K, List<Double>> {
    val result = mutableMapOf<K, MutableList<Double>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<Double>()
            bucket.add(element)
            result[key] = bucket
        } else {
            existing.add(element)
        }
    }
    return result as Map<K, List<Double>>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> DoubleArray.groupBy(
    keySelector: (Double) -> K,
    valueTransform: (Double) -> V
): Map<K, List<V>> {
    val result = mutableMapOf<K, MutableList<V>>()
    for (element in this) {
        val key = keySelector(element)
        val existing = result[key]
        if (existing == null) {
            val bucket = mutableListOf<V>()
            bucket.add(valueTransform(element))
            result[key] = bucket
        } else {
            existing.add(valueTransform(element))
        }
    }
    return result as Map<K, List<V>>
}

public inline fun DoubleArray.forEachIndexed(action: (Int, Double) -> Unit) {
    var index = 0
    for (element in this) action(index++, element)
}

public inline fun <K, V> DoubleArray.associate(transform: (Double) -> Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) {
        val pair = transform(element)
        result[pair.first] = pair.second
    }
    return result
}

public inline fun <K> DoubleArray.associateBy(keySelector: (Double) -> K): Map<K, Double> {
    val result = mutableMapOf<K, Double>()
    for (element in this) result[keySelector(element)] = element
    return result
}

public inline fun <K, V> DoubleArray.associateBy(
    keySelector: (Double) -> K,
    valueTransform: (Double) -> V
): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (element in this) result[keySelector(element)] = valueTransform(element)
    return result
}

public infix fun DoubleArray.zip(other: DoubleArray): List<Pair<Double, Double>> {
    val result = mutableListOf<Pair<Double, Double>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <V> DoubleArray.zip(other: DoubleArray, transform: (Double, Double) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> DoubleArray.zip(other: Array<out R>): List<Pair<Double, R>> {
    val result = mutableListOf<Pair<Double, R>>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(Pair(this[index], other[index]))
        index++
    }
    return result
}

public inline fun <R, V> DoubleArray.zip(other: Array<out R>, transform: (Double, R) -> V): List<V> {
    val result = mutableListOf<V>()
    val length = if (size < other.size) size else other.size
    var index = 0
    while (index < length) {
        result.add(transform(this[index], other[index]))
        index++
    }
    return result
}

public infix fun <R> DoubleArray.zip(other: Iterable<R>): List<Pair<Double, R>> {
    val result = mutableListOf<Pair<Double, R>>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(Pair(this[index++], element))
    }
    return result
}

public inline fun <R, V> DoubleArray.zip(other: Iterable<R>, transform: (Double, R) -> V): List<V> {
    val result = mutableListOf<V>()
    var index = 0
    for (element in other) {
        if (index >= size) break
        result.add(transform(this[index++], element))
    }
    return result
}
