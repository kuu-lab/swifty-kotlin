package kotlin.collections

import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

@KsSymbolName("__kk_map_is_empty")
@PublishedApi
internal external fun <K, V> __kkMapIsEmpty(map: Map<out K, V>): Boolean

// MIGRATION-COL-015
// Map higher-order functions migrated from Swift Runtime
// Sources/Runtime/RuntimeCollectionHOF.swift (kk_map_* HOFs)
// Sources/Runtime/RuntimeSetAndMap.swift (kk_map_plus / kk_map_minus)

public inline fun <K, V> Map<out K, V>.isNotEmpty(): Boolean = !__kkMapIsEmpty(this)

@SinceKotlin("1.3")
@OptIn(ExperimentalContracts::class)
public inline fun <K, V> Map<out K, V>?.isNullOrEmpty(): Boolean {
    contract {
        returns(false) implies (this != null)
    }
    return this == null || __kkMapIsEmpty(this)
}

public inline fun <K, V> Map<out K, V>.asIterable(): Iterable<Map.Entry<K, V>> {
    return this.entries
}

public fun <K, V> Map<out K, V>.asSequence(): Sequence<Map.Entry<K, V>> {
    val source = this
    return object : Sequence<Map.Entry<K, V>> {
        override fun iterator(): Iterator<Map.Entry<K, V>> = source.entries.iterator()
    }
}

public inline fun <K, V> Map<K, V>.forEach(action: (Map.Entry<K, V>) -> Unit) {
    for (entry in this.entries) {
        action(entry)
    }
}

public inline fun <K, V> Map<K, V>.forEach(action: (K, V) -> Unit) {
    for (entry in this.entries) {
        action(entry.key, entry.value)
    }
}

public fun <K, V> Map<out K, V>.any(): Boolean {
    return !__kkMapIsEmpty(this)
}

public inline fun <K, V> Map<K, V>.any(predicate: (Map.Entry<K, V>) -> Boolean): Boolean {
    for (entry in this.entries) {
        if (predicate(entry)) return true
    }
    return false
}

public inline fun <K, V> Map<K, V>.all(predicate: (Map.Entry<K, V>) -> Boolean): Boolean {
    for (entry in this.entries) {
        if (!predicate(entry)) return false
    }
    return true
}

public fun <K, V> Map<out K, V>.none(): Boolean {
    return __kkMapIsEmpty(this)
}

public inline fun <K, V> Map<K, V>.none(predicate: (Map.Entry<K, V>) -> Boolean): Boolean {
    for (entry in this.entries) {
        if (predicate(entry)) return false
    }
    return true
}

@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.count(): Int {
    return size
}

public inline fun <K, V> Map<K, V>.count(predicate: (Map.Entry<K, V>) -> Boolean): Int {
    var count = 0
    for (entry in this.entries) {
        if (predicate(entry)) count++
    }
    return count
}

public inline fun <K, V, R : Any> Map<out K, V>.firstNotNullOf(
    transform: (Map.Entry<K, V>) -> R?
): R {
    for (entry in this.entries) {
        val result = transform(entry)
        if (result != null) return result
    }
    throw NoSuchElementException("No element of the map was transformed to a non-null value.")
}

public inline fun <K, V, R : Any> Map<out K, V>.firstNotNullOfOrNull(
    transform: (Map.Entry<K, V>) -> R?
): R? {
    for (entry in this.entries) {
        val result = transform(entry)
        if (result != null) return result
    }
    return null
}

public inline fun <K, V, R> Map<K, V>.map(transform: (Map.Entry<K, V>) -> R): List<R> {
    val result = mutableListOf<R>()
    for (entry in this.entries) {
        result.add(transform(entry))
    }
    return result
}

public fun <K, V, R : Any> Map<K, V>.mapNotNull(transform: (Map.Entry<K, V>) -> R?): List<R> {
    val result = mutableListOf<R>()
    for (entry in this.entries) {
        val value = transform(entry)
        if (value != null) result.add(value)
    }
    return result
}

public inline fun <K, V, R> Map<K, V>.flatMap(transform: (Map.Entry<K, V>) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (entry in this.entries) {
        for (element in transform(entry)) {
            result.add(element)
        }
    }
    return result
}

@IgnorableReturnValue
public inline fun <K, V, R, C : MutableCollection<in R>> Map<out K, V>.flatMapTo(
    destination: C,
    transform: (Map.Entry<K, V>) -> Iterable<R>
): C {
    for (entry in this.entries) {
        val list = transform(entry)
        destination.addAll(list)
    }
    return destination
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapSequenceTo")
@IgnorableReturnValue
public inline fun <K, V, R, C : MutableCollection<in R>> Map<out K, V>.flatMapTo(
    destination: C,
    transform: (Map.Entry<K, V>) -> Sequence<R>
): C {
    for (entry in this.entries) {
        val list = transform(entry)
        destination.addAll(list)
    }
    return destination
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filter(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}


@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filterNot(predicate: (Map.Entry<K, V>) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (!predicate(entry)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

@IgnorableReturnValue
public inline fun <K, V, M : MutableMap<in K, in V>> Map<out K, V>.filterTo(
    destination: M,
    predicate: (Map.Entry<K, V>) -> Boolean
): M {
    for (entry in this.entries) {
        if (predicate(entry)) {
            destination.put(entry.key, entry.value)
        }
    }
    return destination
}

@IgnorableReturnValue
public inline fun <K, V, M : MutableMap<in K, in V>> Map<out K, V>.filterNotTo(
    destination: M,
    predicate: (Map.Entry<K, V>) -> Boolean
): M {
    for (entry in this.entries) {
        if (!predicate(entry)) {
            destination.put(entry.key, entry.value)
        }
    }
    return destination
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filterKeys(predicate: (K) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry.key)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V> Map<K, V>.filterValues(predicate: (V) -> Boolean): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (predicate(entry.value)) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V, R> Map<K, V>.mapKeys(transform: (Map.Entry<K, V>) -> R): Map<R, V> {
    val result = mutableMapOf<R, V>()
    for (entry in this.entries) {
        result[transform(entry)] = entry.value
    }
    return result as Map<R, V>
}

@Suppress("UNCHECKED_CAST")
public inline fun <K, V, R> Map<K, V>.mapValues(transform: (Map.Entry<K, V>) -> R): Map<K, R> {
    val result = mutableMapOf<K, R>()
    for (entry in this.entries) {
        result[entry.key] = transform(entry)
    }
    return result as Map<K, R>
}

public inline fun <K, V, R, M : MutableMap<in R, in V>> Map<out K, V>.mapKeysTo(
    destination: M,
    transform: (Map.Entry<K, V>) -> R
): M {
    for (entry in this.entries) {
        destination.put(transform(entry), entry.value)
    }
    return destination
}

public inline fun <K, V, R, M : MutableMap<in K, in R>> Map<out K, V>.mapValuesTo(
    destination: M,
    transform: (Map.Entry<K, V>) -> R
): M {
    for (entry in this.entries) {
        destination.put(entry.key, transform(entry))
    }
    return destination
}

public inline fun <K, V, R, C : MutableCollection<in R>> Map<out K, V>.mapTo(
    destination: C,
    transform: (Map.Entry<K, V>) -> R
): C {
    for (entry in this.entries) {
        destination.add(transform(entry))
    }
    return destination
}

public inline fun <K, V, R : Any, C : MutableCollection<in R>> Map<out K, V>.mapNotNullTo(
    destination: C,
    transform: (Map.Entry<K, V>) -> R?
): C {
    for (entry in this.entries) {
        val value = transform(entry)
        if (value != null) destination.add(value)
    }
    return destination
}

/**
 * KSP-1011: named `__kspMapIterator` rather than `iterator` so this
 * declaration never enters the global by-simple-name candidate pool that
 * the generic `Iterable<T>.iterator()` call inside bundled source HOFs
 * (e.g. `reduce`, `reduceIndexed`) resolves against — a second source-backed
 * `iterator` there caused that call to bind here for every receiver,
 * including ranges. Sema binds `map.iterator()` straight to this symbol.
 */
public inline fun <K, V> Map<out K, V>.__kspMapIterator(): Iterator<Map.Entry<K, V>> = this.entries.iterator()

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxByOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
@kotlin.internal.InlineOnly
public inline fun <K, V, R : Comparable<R>> Map<out K, V>.maxBy(
    selector: (Map.Entry<K, V>) -> R
): Map.Entry<K, V> {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxEntry = iterator.next()
    if (!iterator.hasNext()) return maxEntry
    var maxValue = selector(maxEntry)
    while (iterator.hasNext()) {
        val entry = iterator.next()
        val value = selector(entry)
        if (maxValue < value) {
            maxEntry = entry
            maxValue = value
        }
    }
    return maxEntry
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("minByOrThrow")
@kotlin.internal.InlineOnly
@Suppress("CONFLICTING_OVERLOADS")
public inline fun <K, V, R : Comparable<R>> Map<out K, V>.minBy(
    selector: (Map.Entry<K, V>) -> R
): Map.Entry<K, V> {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var minEntry = iterator.next()
    if (!iterator.hasNext()) return minEntry
    var minValue = selector(minEntry)
    do {
        val entry = iterator.next()
        val value = selector(entry)
        if (minValue > value) {
            minEntry = entry
            minValue = value
        }
    } while (iterator.hasNext())
    return minEntry
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.maxOf(selector: (Map.Entry<K, V>) -> Double): Double {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = kk_unbox_double(selector(iterator.next()))
    while (iterator.hasNext()) {
        val value = kk_unbox_double(selector(iterator.next()))
        maxValue = kk_max_double(value, maxValue)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.maxOf(selector: (Map.Entry<K, V>) -> Float): Float {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = kk_unbox_float(selector(iterator.next()))
    while (iterator.hasNext()) {
        val value = kk_unbox_float(selector(iterator.next()))
        maxValue = kk_max_float(value, maxValue)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R : Comparable<R>> Map<out K, V>.maxOf(selector: (Map.Entry<K, V>) -> R): R {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (maxValue < value) maxValue = value
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.maxOfOrNull(selector: (Map.Entry<K, V>) -> Double): Double? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxValue = kk_unbox_double(selector(iterator.next()))
    while (iterator.hasNext()) {
        val value = kk_unbox_double(selector(iterator.next()))
        maxValue = kk_max_double(value, maxValue)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.maxOfOrNull(selector: (Map.Entry<K, V>) -> Float): Float? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxValue = kk_unbox_float(selector(iterator.next()))
    while (iterator.hasNext()) {
        val value = kk_unbox_float(selector(iterator.next()))
        maxValue = kk_max_float(value, maxValue)
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R : Comparable<R>> Map<out K, V>.maxOfOrNull(selector: (Map.Entry<K, V>) -> R): R? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (maxValue < value) maxValue = value
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R> Map<out K, V>.maxOfWith(
    comparator: Comparator<in R>,
    selector: (Map.Entry<K, V>) -> R
): R {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (comparator.compare(maxValue, value) < 0) maxValue = value
    }
    return maxValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R> Map<out K, V>.maxOfWithOrNull(
    comparator: Comparator<in R>,
    selector: (Map.Entry<K, V>) -> R
): R? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxValue = selector(iterator.next())
    while (iterator.hasNext()) {
        val value = selector(iterator.next())
        if (comparator.compare(maxValue, value) < 0) maxValue = value
    }
    return maxValue
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("maxWithOrThrow")
@Suppress("CONFLICTING_OVERLOADS")
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.maxWith(
    comparator: Comparator<in Map.Entry<K, V>>
): Map.Entry<K, V> {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var maxEntry = iterator.next()
    while (iterator.hasNext()) {
        val entry = iterator.next()
        if (comparator.compare(maxEntry, entry) < 0) maxEntry = entry
    }
    return maxEntry
}

@SinceKotlin("1.4")
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.maxWithOrNull(
    comparator: Comparator<in Map.Entry<K, V>>
): Map.Entry<K, V>? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxEntry = iterator.next()
    while (iterator.hasNext()) {
        val entry = iterator.next()
        if (comparator.compare(maxEntry, entry) < 0) maxEntry = entry
    }
    return maxEntry
}

public inline fun <K, V, R : Comparable<R>> Map<K, V>.maxByOrNull(
    selector: (Map.Entry<K, V>) -> R
): Map.Entry<K, V>? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var maxEntry = iterator.next()
    var maxValue = selector(maxEntry)
    while (iterator.hasNext()) {
        val entry = iterator.next()
        val value = selector(entry)
        if (maxValue < value) {
            maxEntry = entry
            maxValue = value
        }
    }
    return maxEntry
}

public inline fun <K, V, R : Comparable<R>> Map<K, V>.minByOrNull(
    selector: (Map.Entry<K, V>) -> R
): Map.Entry<K, V>? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var minEntry = iterator.next()
    var minValue = selector(minEntry)
    while (iterator.hasNext()) {
        val entry = iterator.next()
        val value = selector(entry)
        if (minValue > value) {
            minEntry = entry
            minValue = value
        }
    }
    return minEntry
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.minOf(selector: (Map.Entry<K, V>) -> Double): Double {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (value.isNaN()) {
            minValue = value
        } else if (!minValue.isNaN()) {
            if (minValue == 0.0 && value == 0.0) {
                minValue = if (minValue.toBits() < 0L || value.toBits() < 0L) -0.0 else 0.0
            } else if (value < minValue) {
                minValue = value
            }
        }
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.minOf(selector: (Map.Entry<K, V>) -> Float): Float {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (value.isNaN()) {
            minValue = value
        } else if (!minValue.isNaN()) {
            if (minValue == 0.0f && value == 0.0f) {
                minValue = if (minValue.toBits() < 0 || value.toBits() < 0) -0.0f else 0.0f
            } else if (value < minValue) {
                minValue = value
            }
        }
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R : Comparable<R>> Map<out K, V>.minOf(
    selector: (Map.Entry<K, V>) -> R
): R {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (minValue > value) minValue = value
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.minOfOrNull(selector: (Map.Entry<K, V>) -> Double): Double? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (value.isNaN()) {
            minValue = value
        } else if (!minValue.isNaN()) {
            if (minValue == 0.0 && value == 0.0) {
                minValue = if (minValue.toBits() < 0L || value.toBits() < 0L) -0.0 else 0.0
            } else if (value < minValue) {
                minValue = value
            }
        }
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.minOfOrNull(selector: (Map.Entry<K, V>) -> Float): Float? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (value.isNaN()) {
            minValue = value
        } else if (!minValue.isNaN()) {
            if (minValue == 0.0f && value == 0.0f) {
                minValue = if (minValue.toBits() < 0 || value.toBits() < 0) -0.0f else 0.0f
            } else if (value < minValue) {
                minValue = value
            }
        }
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R : Comparable<R>> Map<out K, V>.minOfOrNull(
    selector: (Map.Entry<K, V>) -> R
): R? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (minValue > value) minValue = value
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R> Map<out K, V>.minOfWith(
    comparator: Comparator<in R>,
    selector: (Map.Entry<K, V>) -> R
): R {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (comparator.compare(minValue, value) > 0) minValue = value
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.4")
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.internal.InlineOnly
public inline fun <K, V, R> Map<out K, V>.minOfWithOrNull(
    comparator: Comparator<in R>,
    selector: (Map.Entry<K, V>) -> R
): R? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    val firstEntry = iterator.next()
    if (!iterator.hasNext()) return selector(firstEntry)
    var minValue = selector(firstEntry)
    do {
        val value = selector(iterator.next())
        if (comparator.compare(minValue, value) > 0) minValue = value
    } while (iterator.hasNext())
    return minValue
}

@SinceKotlin("1.7")
@kotlin.jvm.JvmName("minWithOrThrow")
@kotlin.internal.InlineOnly
@Suppress("CONFLICTING_OVERLOADS")
public inline fun <K, V> Map<out K, V>.minWith(
    comparator: Comparator<in Map.Entry<K, V>>
): Map.Entry<K, V> {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) throw NoSuchElementException()
    var minEntry = iterator.next()
    while (iterator.hasNext()) {
        val entry = iterator.next()
        if (comparator.compare(minEntry, entry) > 0) minEntry = entry
    }
    return minEntry
}

@SinceKotlin("1.4")
@kotlin.internal.InlineOnly
public inline fun <K, V> Map<out K, V>.minWithOrNull(
    comparator: Comparator<in Map.Entry<K, V>>
): Map.Entry<K, V>? {
    val iterator = this.entries.iterator()
    if (!iterator.hasNext()) return null
    var minEntry = iterator.next()
    while (iterator.hasNext()) {
        val entry = iterator.next()
        if (comparator.compare(minEntry, entry) > 0) minEntry = entry
    }
    return minEntry
}

@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.plus(pair: Pair<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    result[pair.first] = pair.second
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.plus(map: Map<K, V>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    for (entry in map.entries) {
        result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public operator fun <K, V> Map<out K, V>.plus(pairs: Iterable<Pair<K, V>>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public operator fun <K, V> Map<out K, V>.plus(pairs: Sequence<Pair<K, V>>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public operator fun <K, V> Map<out K, V>.plus(pairs: Array<out Pair<K, V>>): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        result[entry.key] = entry.value
    }
    for (pair in pairs) {
        result[pair.first] = pair.second
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.minus(key: K): Map<K, V> {
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (entry.key != key) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public inline operator fun <K, V> Map<K, V>.minus(keys: Iterable<K>): Map<K, V> {
    val keySet = mutableSetOf<K>()
    for (k in keys) keySet.add(k)
    val result = mutableMapOf<K, V>()
    for (entry in this.entries) {
        if (entry.key !in keySet) result[entry.key] = entry.value
    }
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public operator fun <K, V> Map<out K, V>.minus(keys: Array<out K>): Map<K, V> {
    val result = this.toMutableMap()
    for (key in keys) result.remove(key)
    return result as Map<K, V>
}

@Suppress("UNCHECKED_CAST")
public operator fun <K, V> Map<out K, V>.minus(keys: Sequence<K>): Map<K, V> {
    val result = this.toMutableMap()
    for (key in keys) result.remove(key)
    return result as Map<K, V>
}
