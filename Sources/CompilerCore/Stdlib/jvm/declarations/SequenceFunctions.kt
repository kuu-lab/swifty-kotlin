package kotlin.sequences
fun <T> emptySequence(): Sequence<T> = null!!
fun <T> sequenceOf(element: T): Sequence<T> = null!!
fun <T> sequenceOf(vararg elements: T): Sequence<T> = null!!
fun <T: Any> generateSequence(nextFunction: () -> T?): Sequence<T> = null!!
fun <T: Any> generateSequence(seed: T?, nextFunction: (T) -> T?): Sequence<T> = null!!
fun <T: Any> generateSequence(seedFunction: () -> T?, nextFunction: (T) -> T?): Sequence<T> = null!!
fun <T> Iterator<T>.asSequence(): Sequence<T> = null!!
fun <T> Sequence<T>.asIterable(): Iterable<T> = null!!
fun <T> Sequence<T>.constrainOnce(): Sequence<T> = null!!
operator fun <T> Sequence<T>.plus(element: T): Sequence<T> = null!!
operator fun <T> Sequence<T>.plus(elements: Array<out T>): Sequence<T> = null!!
operator fun <T> Sequence<T>.plus(elements: Iterable<T>): Sequence<T> = null!!
operator fun <T> Sequence<T>.plus(elements: Sequence<T>): Sequence<T> = null!!
fun <T, R> Sequence<T>.map(transform: (T) -> R): Sequence<R> = null!!
fun <T, R> Sequence<T>.mapIndexed(transform: (Int, T) -> R): Sequence<R> = null!!
fun <T, R: Any> Sequence<T>.mapNotNull(transform: (T) -> R?): Sequence<R> = null!!
fun <T, R: Any> Sequence<T>.mapIndexedNotNull(transform: (Int, T) -> R?): Sequence<R> = null!!
fun <T> Sequence<T>.filter(predicate: (T) -> Boolean): Sequence<T> = null!!
fun <T> Sequence<T>.filterNot(predicate: (T) -> Boolean): Sequence<T> = null!!
fun <T> Sequence<T>.filterIndexed(predicate: (Int, T) -> Boolean): Sequence<T> = null!!
fun <T: Any> Sequence<T?>.filterNotNull(): Sequence<T> = null!!
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
fun <T, R> Sequence<T>.flatMap(transform: (T) -> Sequence<R>): Sequence<R> = null!!
@OptIn(kotlin.experimental.ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
@kotlin.jvm.JvmName("flatMapIterable")
fun <T, R> Sequence<T>.flatMap(transform: (T) -> Iterable<R>): Sequence<R> = null!!
@kotlin.jvm.JvmName("flattenSequenceOfIterable")
fun <T> Sequence<Iterable<T>>.flatten(): Sequence<T> = null!!
fun <T> Sequence<Sequence<T>>.flatten(): Sequence<T> = null!!
fun <T> Sequence<T>.take(n: Int): Sequence<T> = null!!
fun <T> Sequence<T>.drop(n: Int): Sequence<T> = null!!
fun <T> Sequence<T>.takeWhile(predicate: (T) -> Boolean): Sequence<T> = null!!
fun <T> Sequence<T>.dropWhile(predicate: (T) -> Boolean): Sequence<T> = null!!
fun <T> Sequence<T>.distinct(): Sequence<T> = null!!
fun <T, K> Sequence<T>.distinctBy(selector: (T) -> K): Sequence<T> = null!!
fun <T> Sequence<T>.onEach(action: (T) -> Unit): Sequence<T> = null!!
fun <T> Sequence<T>.onEachIndexed(action: (Int, T) -> Unit): Sequence<T> = null!!
fun <T: Comparable<T>> Sequence<T>.sorted(): Sequence<T> = null!!
fun <T: Comparable<T>> Sequence<T>.sortedDescending(): Sequence<T> = null!!
inline fun <T, R: Comparable<R>> Sequence<T>.sortedBy(crossinline selector: (T) -> R?): Sequence<T> = null!!
inline fun <T, R: Comparable<R>> Sequence<T>.sortedByDescending(crossinline selector: (T) -> R?): Sequence<T> = null!!
infix fun <T, R> Sequence<T>.zip(other: Sequence<R>): Sequence<Pair<T, R>> = null!!
fun <T, R, V> Sequence<T>.zip(other: Sequence<R>, transform: (T, R) -> V): Sequence<V> = null!!
fun <T> Sequence<T>.zipWithNext(): Sequence<Pair<T, T>> = null!!
fun <T, R> Sequence<T>.zipWithNext(transform: (T, T) -> R): Sequence<R> = null!!
fun <T> Sequence<T>.chunked(size: Int): Sequence<List<T>> = null!!
fun <T, R> Sequence<T>.chunked(size: Int, transform: (List<T>) -> R): Sequence<R> = null!!
fun <T> Sequence<T>.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false): Sequence<List<T>> = null!!
fun <T, R> Sequence<T>.windowed(size: Int, step: Int = 1, partialWindows: Boolean = false, transform: (List<T>) -> R): Sequence<R> = null!!
fun <T> Sequence<T>.toList(): List<T> = null!!
fun <T> Sequence<T>.toMutableList(): MutableList<T> = null!!
fun <T> Sequence<T>.toSet(): Set<T> = null!!
fun <T> Sequence<T>.toMutableSet(): MutableSet<T> = null!!
fun <T> Sequence<T>.count(): Int = 0
fun <T> Sequence<T>.any(): Boolean = false
fun <T> Sequence<T>.none(): Boolean = false
fun <T> Sequence<T>.first(): T = null!!
fun <T> Sequence<T>.firstOrNull(): T? = null
fun <T> Sequence<T>.last(): T = null!!
fun <T> Sequence<T>.lastOrNull(): T? = null
fun <T> Sequence<T>.single(): T = null!!
fun <T> Sequence<T>.singleOrNull(): T? = null
fun <T> Sequence<T>.elementAt(index: Int): T = null!!
fun <T> Sequence<T>.elementAtOrNull(index: Int): T? = null
operator fun <T> Sequence<T>.contains(element: T): Boolean = false
fun Sequence<Double>.minOrNull(): Double? = null
fun Sequence<Float>.minOrNull(): Float? = null
fun Sequence<Double>.maxOrNull(): Double? = null
fun Sequence<Float>.maxOrNull(): Float? = null
fun <T: Comparable<T>> Sequence<T>.minOrNull(): T? = null
fun <T: Comparable<T>> Sequence<T>.maxOrNull(): T? = null
fun <K, V> Sequence<Pair<K, V>>.toMap(): Map<K, V> = null!!
fun <T> Sequence<T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String = null!!
