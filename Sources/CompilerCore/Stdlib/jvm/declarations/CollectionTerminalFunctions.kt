package kotlin.collections
fun <T> Iterable<T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String = null!!
fun <T> Iterable<T>.toList(): List<T> = null!!
fun <T> Iterable<T>.toMutableList(): MutableList<T> = null!!
fun <T> Iterable<T>.toSet(): Set<T> = null!!
fun <T> Iterable<T>.toMutableSet(): MutableSet<T> = null!!
fun <T> Iterable<T>.distinct(): List<T> = null!!
fun <T> Iterable<T>.reversed(): List<T> = null!!
fun <T: Comparable<T>> Iterable<T>.sorted(): List<T> = null!!
fun <T: Comparable<T>> Iterable<T>.sortedDescending(): List<T> = null!!
fun <T> Iterable<T>.take(n: Int): List<T> = null!!
fun <T> List<T>.takeLast(n: Int): List<T> = null!!
inline fun <T> Iterable<T>.takeWhile(predicate: (T) -> Boolean): List<T> = null!!
fun <T> Iterable<T>.drop(n: Int): List<T> = null!!
fun <T> List<T>.dropLast(n: Int): List<T> = null!!
inline fun <T> Iterable<T>.dropWhile(predicate: (T) -> Boolean): List<T> = null!!
fun <T> List<T>.dropLastWhile(predicate: (T) -> Boolean): List<T> = null!!
fun <K, V> Iterable<Pair<K, V>>.toMap(): Map<K, V> = null!!
fun <T> Iterable<T>.asSequence(): kotlin.sequences.Sequence<T> = null!!
