package kotlin.sequences
inline fun <T, K> Sequence<T>.groupBy(keySelector: (T) -> K): Map<K, List<T>> { val result = mutableMapOf<K, MutableList<T>>(); for (item in this) { val key = keySelector(item); val list = result[key]; if (list == null) { val created = mutableListOf<T>(); result[key] = created; created.add(item) } else list.add(item) }; return result }
inline fun <T, K, V> Sequence<T>.groupBy(keySelector: (T) -> K, valueTransform: (T) -> V): Map<K, List<V>> { val result = mutableMapOf<K, MutableList<V>>(); for (item in this) { val key = keySelector(item); var list = result[key]; if (list == null) { list = mutableListOf<V>(); result[key] = list }; list.add(valueTransform(item)) }; return result }
inline fun <T, K, V> Sequence<T>.associate(transform: (T) -> Pair<K, V>): Map<K, V> { val result = mutableMapOf<K, V>(); for (item in this) { val pair = transform(item); result[pair.first] = pair.second }; return result }
inline fun <T, K> Sequence<T>.associateBy(keySelector: (T) -> K): Map<K, T> { val result = mutableMapOf<K, T>(); for (item in this) result[keySelector(item)] = item; return result }
inline fun <T, K, V> Sequence<T>.associateBy(keySelector: (T) -> K, valueTransform: (T) -> V): Map<K, V> { val result = mutableMapOf<K, V>(); for (item in this) { val key = keySelector(item); result[key] = valueTransform(item) }; return result }
inline fun <T, V> Sequence<T>.associateWith(valueSelector: (T) -> V): Map<T, V> { val result = mutableMapOf<T, V>(); for (item in this) result[item] = valueSelector(item); return result }
inline fun <T> Sequence<T>.partition(predicate: (T) -> Boolean): Pair<List<T>, List<T>> { val yes = mutableListOf<T>(); val no = mutableListOf<T>(); for (item in this) { if (predicate(item)) yes.add(item) else no.add(item) }; return Pair(yes, no) }
inline fun <T> Sequence<T>.forEach(action: (T) -> Unit): Unit { for (item in this) action(item) }
inline fun <T, R> Sequence<T>.fold(initial: R, operation: (R, T) -> R): R { var result = initial; for (item in this) result = operation(result, item); return result }

inline fun <T> Sequence<T>.any(predicate: (T) -> Boolean): Boolean { for (item in this) if (predicate(item)) return true; return false }
inline fun <T> Sequence<T>.all(predicate: (T) -> Boolean): Boolean { for (item in this) if (!predicate(item)) return false; return true }
inline fun <T> Sequence<T>.none(predicate: (T) -> Boolean): Boolean { for (item in this) if (predicate(item)) return false; return true }
inline fun <T> Sequence<T>.count(predicate: (T) -> Boolean): Int { var n = 0; for (item in this) if (predicate(item)) n++; return n }
inline fun <T> Sequence<T>.first(predicate: (T) -> Boolean): T { for (item in this) if (predicate(item)) return item; throw NoSuchElementException("Sequence contains no element matching the predicate.") }
inline fun <T> Sequence<T>.firstOrNull(predicate: (T) -> Boolean): T? { for (item in this) if (predicate(item)) return item; return null }