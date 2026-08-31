package kotlin.collections

import kotlin.internal.__valuesEqual

// KSP-435
// Generic Iterable<T> surface migrated from the Swift runtime `kk_iterable_*`
// bridges. Every implementation only relies on `iterator()` virtual dispatch,
// so it works for List, Set and any user-defined Iterable alike.

// KSP-963: Kotlin's Iterable.asIterable() is an identity conversion.
public inline fun <T> Iterable<T>.asIterable(): Iterable<T> = this

public fun <T> Iterable<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.drop(n: Int): List<T> {
    require(n >= 0) { "Requested element count $n is less than zero." }
    if (n == 0) return toList()

    val result = mutableListOf<T>()
    var count = 0
    for (element in this) {
        if (count >= n) result.add(element) else count += 1
    }
    return result
}

public inline fun <T> Iterable<T>.dropWhile(predicate: (T) -> Boolean): List<T> {
    var yielding = false
    val result = mutableListOf<T>()
    for (element in this) {
        if (yielding) {
            result.add(element)
        } else if (!predicate(element)) {
            result.add(element)
            yielding = true
        }
    }
    return result
}

public fun <T> Iterable<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) result.add(element)
    return result
}

// KSP-997: Split each pair from a generic Iterable in encounter order.
public fun <T, R> Iterable<Pair<T, R>>.unzip(): Pair<List<T>, List<R>> {
    val first = mutableListOf<T>()
    val second = mutableListOf<R>()
    val iterator = iterator()
    while (iterator.hasNext()) {
        val pair = iterator.next()
        first.add(pair.first)
        second.add(pair.second)
    }
    return Pair(first, second)
}

public fun <T> Iterable<T>.toMutableSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T> Iterable<T>.toHashSet(): MutableSet<T> {
    val result = mutableSetOf<T>()
    for (element in this) result.add(element)
    return result
}

public fun <T, C : MutableCollection<in T>> Iterable<T>.toCollection(destination: C): C {
    for (element in this) destination.add(element)
    return destination
}

// KSP-974: Iterable flat-map transformations are source-backed. Keep the
// Iterable and Sequence inner-result overloads distinct so lambda-return-type
// overload resolution selects the same public API as the Kotlin stdlib.
public inline fun <T, R> Iterable<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapSequence")
public inline fun <T, R> Iterable<T>.flatMap(transform: (T) -> Sequence<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedIterable")
@kotlin.internal.InlineOnly
public inline fun <T, R> Iterable<T>.flatMapIndexed(transform: (index: Int, T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedSequence")
@kotlin.internal.InlineOnly
public inline fun <T, R> Iterable<T>.flatMapIndexed(transform: (index: Int, T) -> Sequence<R>): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) result.add(nestedIterator.next())
    }
    return result
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedIterableTo")
@IgnorableReturnValue
@kotlin.internal.InlineOnly
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapIndexedTo(
    destination: C,
    transform: (index: Int, T) -> Iterable<R>
): C {
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIndexedSequenceTo")
@IgnorableReturnValue
@kotlin.internal.InlineOnly
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapIndexedTo(
    destination: C,
    transform: (index: Int, T) -> Sequence<R>
): C {
    var index = 0
    for (element in this) {
        val currentIndex = index
        if (currentIndex < 0) throw ArithmeticException("Index overflow has happened.")
        index += 1
        val nestedIterator = transform(currentIndex, element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapTo(
    destination: C,
    transform: (T) -> Iterable<R>
): C {
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapSequenceTo")
@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.flatMapTo(
    destination: C,
    transform: (T) -> Sequence<R>
): C {
    for (element in this) {
        val nestedIterator = transform(element).iterator()
        while (nestedIterator.hasNext()) destination.add(nestedIterator.next())
    }
    return destination
}

public fun <T> Collection<T>.isNotEmpty(): Boolean = !isEmpty()

@Suppress("UNCHECKED_CAST")
public fun <T> Iterable<T>.last(): T {
    var found = false
    var last: T? = null
    for (element in this) {
        last = element
        found = true
    }
    if (!found) throw NoSuchElementException("Collection is empty.")
    return last as T
}

@Suppress("UNCHECKED_CAST")
public inline fun <T> Iterable<T>.last(predicate: (T) -> Boolean): T {
    var last: T? = null
    var found = false
    for (element in this) {
        if (predicate(element)) {
            last = element
            found = true
        }
    }
    if (!found) throw NoSuchElementException("Collection contains no element matching the predicate.")
    return last as T
}

public fun <T> Iterable<T>.lastIndexOf(element: T): Int {
    var lastIndex = -1
    var index = 0
    for (item in this) {
        if (__valuesEqual(element, item)) lastIndex = index
        index++
    }
    return lastIndex
}

public fun <T> Iterable<T>.lastOrNull(): T? {
    var last: T? = null
    for (element in this) last = element
    return last
}

public inline fun <T> Iterable<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var last: T? = null
    for (element in this) {
        if (predicate(element)) last = element
    }
    return last
}

// KSP-701: generic Iterable HOFs formerly registered by the compiler-side
// synthetic member registry now use bundled Kotlin source bodies.
public fun <T> Iterable<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

// KSP-982: source-backed Iterable map-family implementations. Keep these
// overloads independent from concrete List/Array/Set/Sequence receivers so
// virtual iterator dispatch also covers custom and one-shot Iterables.
public inline fun <T, R> Iterable<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) result.add(transform(element))
    return result
}

public inline fun <T, R> Iterable<T>.mapIndexed(transform: (Int, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        result.add(transform(index, element))
        index += 1
    }
    return result
}

public inline fun <T, R : Any> Iterable<T>.mapIndexedNotNull(transform: (Int, T) -> R?): List<R> {
    val result = mutableListOf<R>()
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        transform(index, element)?.let { result.add(it) }
        index += 1
    }
    return result
}

@IgnorableReturnValue
public inline fun <T, R : Any, C : MutableCollection<in R>> Iterable<T>.mapIndexedNotNullTo(
    destination: C,
    transform: (Int, T) -> R?
): C {
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        transform(index, element)?.let { destination.add(it) }
        index += 1
    }
    return destination
}

@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.mapIndexedTo(
    destination: C,
    transform: (Int, T) -> R
): C {
    var index = 0
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        destination.add(transform(index, element))
        index += 1
    }
    return destination
}

public inline fun <T, R : Any> Iterable<T>.mapNotNull(transform: (T) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (element in this) transform(element)?.let { result.add(it) }
    return result
}

@IgnorableReturnValue
public inline fun <T, R : Any, C : MutableCollection<in R>> Iterable<T>.mapNotNullTo(
    destination: C,
    transform: (T) -> R?
): C {
    for (element in this) transform(element)?.let { destination.add(it) }
    return destination
}

@IgnorableReturnValue
public inline fun <T, R, C : MutableCollection<in R>> Iterable<T>.mapTo(
    destination: C,
    transform: (T) -> R
): C {
    for (element in this) destination.add(transform(element))
    return destination
}

public inline fun <S, T : S> Iterable<T>.reduce(operation: (acc: S, T) -> S): S {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator: S = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public inline fun <S, T : S> Iterable<T>.reduceIndexed(operation: (index: Int, acc: S, T) -> S): S {
    val iterator = iterator()
    if (!iterator.hasNext()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator: S = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index += 1
    }
    return accumulator
}

public inline fun <S, T : S> Iterable<T>.reduceOrNull(operation: (acc: S, T) -> S): S? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var accumulator: S = iterator.next()
    while (iterator.hasNext()) {
        accumulator = operation(accumulator, iterator.next())
    }
    return accumulator
}

public inline fun <S, T : S> Iterable<T>.reduceIndexedOrNull(operation: (index: Int, acc: S, T) -> S): S? {
    val iterator = iterator()
    if (!iterator.hasNext()) return null
    var accumulator: S = iterator.next()
    var index = 1
    while (iterator.hasNext()) {
        accumulator = operation(index, accumulator, iterator.next())
        index += 1
    }
    return accumulator
}

public fun <T> Iterable<T>.any(): Boolean {
    for (element in this) return true
    return false
}

public fun <T> Iterable<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

public fun <T> Iterable<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

public fun <T> Iterable<T>.count(): Int {
    if (this is Collection<*>) return (this as Collection<*>).size

    var count = 0
    for (element in this) {
        count += 1
        if (count < 0) throw ArithmeticException("Count overflow has happened.")
    }
    return count
}

public inline fun <T> Iterable<T>.count(predicate: (T) -> Boolean): Int {
    if (this is Collection<*> && (this as Collection<*>).isEmpty()) return 0

    var count = 0
    for (element in this) {
        if (predicate(element)) {
            count += 1
            if (count < 0) throw ArithmeticException("Count overflow has happened.")
        }
    }
    return count
}

public fun <T, R : Any> Iterable<T>.firstNotNullOfOrNull(transform: (T) -> R?): R? {
    for (element in this) {
        val result = transform(element)
        if (result != null) return result
    }
    return null
}

public fun <T, R : Any> Iterable<T>.firstNotNullOf(transform: (T) -> R?): R {
    for (element in this) {
        val result = transform(element)
        if (result != null) return result
    }
    throw NoSuchElementException("No element of the collection was transformed to a non-null value.")
}

@Suppress("UNCHECKED_CAST")
public fun <T : Any> Iterable<T?>.requireNoNulls(): Iterable<T> {
    for (element in this) {
        if (element == null) {
            throw IllegalArgumentException("null element found in $this.")
        }
    }
    return this as Iterable<T>
}

// Shared by Iterable.joinTo/joinToString (below) and Sequence.joinTo/joinToString
// (SequenceAggregateHOF.kt, kotlin.sequences) — both only need iterator(), so a
// single implementation keyed on Iterator<T> covers both receiver types (KSP-621).
internal fun <T> appendJoinToPlain(
    iterator: Iterator<T>,
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder {
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(element.toString())
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer
}

internal fun <T> appendJoinToTransform(
    iterator: Iterator<T>,
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder {
    buffer.append(prefix)
    var count = 0
    var hasMore = false
    while (iterator.hasNext()) {
        val element = iterator.next()
        if (limit >= 0 && count >= limit) {
            hasMore = true
            break
        }
        if (count > 0) buffer.append(separator)
        buffer.append(transform(element).toString())
        count++
    }
    if (hasMore) {
        if (count > 0) buffer.append(separator)
        buffer.append(truncated)
    }
    buffer.append(postfix)
    return buffer
}

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): StringBuilder = appendJoinToPlain(this.iterator(), buffer, separator, prefix, postfix, -1, "...")

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): StringBuilder = appendJoinToPlain(this.iterator(), buffer, separator, prefix, postfix, limit, truncated)

public fun <T> Iterable<T>.joinTo(
    buffer: StringBuilder,
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): StringBuilder = appendJoinToTransform(this.iterator(), buffer, separator, prefix, postfix, limit, truncated, transform)

public fun <T> Iterable<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String = appendJoinToPlain(this.iterator(), StringBuilder(), separator, prefix, postfix, -1, "...").toString()

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String
): String = appendJoinToPlain(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated).toString()

// The `transform` overloads are spelled per arity because a trailing lambda
// cannot be bound to the defaulted `String` parameters above.
public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    transform: (T) -> Any
): String {
    return appendJoinToTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, -1, "...", transform).toString()
}

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    transform: (T) -> Any
): String = joinToString(separator, prefix, "", transform)

public fun <T> Iterable<T>.joinToString(
    separator: String,
    transform: (T) -> Any
): String = joinToString(separator, "", "", transform)

public fun <T> Iterable<T>.joinToString(
    separator: String,
    prefix: String,
    postfix: String,
    limit: Int,
    truncated: String,
    transform: (T) -> Any
): String = appendJoinToTransform(this.iterator(), StringBuilder(), separator, prefix, postfix, limit, truncated, transform).toString()

// KSP-632: remaining Iterable HOFs migrated from the Swift runtime `kk_list_*`
// bridges. These implementations rely only on `iterator()` / `toMutableList()`,
// so they work for List, Set and any other Iterable.

public fun <T> Iterable<T>.reduceRight(operation: (T, T) -> T): T {
    val list = this.toMutableList()
    if (list.size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightIndexed(operation: (Int, T, T) -> T): T {
    val list = this.toMutableList()
    if (list.size == 0) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(i, list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightOrNull(operation: (T, T) -> T): T? {
    val list = this.toMutableList()
    if (list.size == 0) return null
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.reduceRightIndexedOrNull(operation: (Int, T, T) -> T): T? {
    val list = this.toMutableList()
    if (list.size == 0) return null
    var accumulator = list[list.size - 1]
    var i = list.size - 2
    while (i >= 0) {
        accumulator = operation(i, list[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> Iterable<T>.joinToString(
    transform: (T) -> Any
): String = appendJoinToTransform(this.iterator(), StringBuilder(), ", ", "", "", -1, "...", transform).toString()

// Char.toString() is represented by its numeric code in the generic path;
// keep the List<Char> overload aligned with Kotlin's character rendering.
public fun List<Char>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String {
    val buffer = StringBuilder()
    buffer.append(prefix)
    var first = true
    for (element in this) {
        if (!first) buffer.append(separator)
        buffer.append(element)
        first = false
    }
    buffer.append(postfix)
    return buffer.toString()
}

// KSP-976: Iterable fold-family source bodies preserve the generic accumulator
// type while traversing every receiver through its iterator exactly once.
public inline fun <T, R> Iterable<T>.fold(initial: R, operation: (acc: R, T) -> R): R {
    var accumulator = initial
    for (element in this) accumulator = operation(accumulator, element)
    return accumulator
}

public inline fun <T, R> Iterable<T>.foldIndexed(initial: R, operation: (index: Int, acc: R, T) -> R): R {
    var index = 0
    var accumulator = initial
    for (element in this) {
        if (index < 0) throw ArithmeticException("Index overflow has happened.")
        accumulator = operation(index, accumulator, element)
        index += 1
    }
    return accumulator
}
