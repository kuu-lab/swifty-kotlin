package kotlin.collections
inline fun <T, R: Comparable<R>> Iterable<T>.sortedBy(crossinline selector: (T) -> R?): List<T> = null!!
inline fun <T, R: Comparable<R>> Iterable<T>.sortedByDescending(crossinline selector: (T) -> R?): List<T> = null!!
fun <T> Iterable<T>.sortedWith(comparator: Comparator<in T>): List<T> = null!!
fun <T> Iterable<T>.chunked(size: Int): List<List<T>> = null!!
fun <T, R> Iterable<T>.chunked(size: Int, transform: (List<T>) -> R): List<R> = null!!
fun <T> Iterable<T>.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): List<List<T>> = null!!
