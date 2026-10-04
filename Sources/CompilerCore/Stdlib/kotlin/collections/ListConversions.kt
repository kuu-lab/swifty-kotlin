package kotlin.collections

// KSP-429: List conversion, nullability, destructuring and index APIs are
// ordinary Kotlin implementations. List storage and element access remain
// runtime primitives; these functions only compose those primitives.

public fun <T> List<T>?.orEmpty(): List<T> {
    if (this == null) return emptyList<T>()
    return this!!
}

public fun <T> List<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

@Suppress("UNCHECKED_CAST")
public fun <K, V> List<Pair<K, V>>.toMap(): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this) result[entry.first] = entry.second
    return result as Map<K, V>
}

public operator fun <T> List<T>.component1(): T = this[0]

public operator fun <T> List<T>.component2(): T = this[1]

public operator fun <T> List<T>.component3(): T = this[2]

public operator fun <T> List<T>.component4(): T = this[3]

public operator fun <T> List<T>.component5(): T = this[4]

// Extension properties with generic receivers are not accepted by the bundled
// parser. Zero-argument functions participate in property-style member lookup.
public fun <T> List<T>.lastIndex(): Int = size - 1

public fun <T> List<T>.indices(): IntRange = 0..lastIndex()
