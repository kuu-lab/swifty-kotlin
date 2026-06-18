package kotlin.text

// String split, join, chunked, windowed, zip functions migrated from Swift Runtime
// MIGRATION-TEXT-004

/**
 * Splits this char sequence around occurrences of the specified [delimiters].
 *
 * @param delimiters One or more strings to be used as delimiters.
 * @param ignoreCase `true` to ignore character case when matching a delimiter. By default `false`.
 * @param limit The maximum number of substrings to return. Zero by default means no limit.
 * @return A list of strings split by the specified delimiters.
 */
@kotlin.internal.InlineOnly
public inline fun CharSequence.split(
    vararg delimiters: String,
    ignoreCase: Boolean = false,
    limit: Int = 0
): List<String> {
    // Delegate to the existing bridge implementation
    if (delimiters.isEmpty()) {
        return listOf(this.toString())
    }
    // For single delimiter, use the bridge
    if (delimiters.size == 1) {
        // Note: This will be dispatched to kk_string_split_limit via the compiler's synthetic stubs
        // The actual bridge call is handled by the compiler's lowering
        return if (ignoreCase || limit != 0) {
            // Use the limit variant when ignoreCase or limit is specified
            // This is a placeholder - the compiler will route this to kk_string_split_limit
            splitByDelimiter(delimiters[0], ignoreCase, limit)
        } else {
            // Use the simple split variant
            splitByDelimiter(delimiters[0], false, 0)
        }
    }
    // For multiple delimiters, split at whichever delimiter matches first at each position
    return splitByDelimiters(delimiters.toList(), ignoreCase, limit)
}

// Internal helper for single-delimiter split - this will be replaced by compiler lowering
private fun CharSequence.splitByDelimiter(delimiter: String, ignoreCase: Boolean, limit: Int): List<String> =
    splitByDelimiters(listOf(delimiter), ignoreCase, limit)

// Internal helper for multi-delimiter split supporting trailing-empty semantics
private fun CharSequence.splitByDelimiters(delimiters: List<String>, ignoreCase: Boolean, limit: Int): List<String> {
    val result = mutableListOf<String>()
    var current = 0
    val source = this.toString()
    var count = 0

    while (current <= source.length) {
        if (limit > 0 && count >= limit - 1) {
            result.add(source.substring(current))
            return result
        }

        // Find the earliest match among all delimiters
        var bestIndex = -1
        var bestDelimiter = ""
        for (delimiter in delimiters) {
            if (delimiter.isEmpty()) continue
            val idx = source.indexOf(delimiter, current, ignoreCase = ignoreCase)
            if (idx != -1 && (bestIndex == -1 || idx < bestIndex)) {
                bestIndex = idx
                bestDelimiter = delimiter
            }
        }

        if (bestIndex == -1) {
            result.add(source.substring(current))
            return result
        }

        result.add(source.substring(current, bestIndex))
        current = bestIndex + bestDelimiter.length
        count++
    }

    return result
}

/**
 * Splits this char sequence around occurrences of the specified [delimiters] to a sequence.
 *
 * @param delimiters One or more strings to be used as delimiters.
 * @param ignoreCase `true` to ignore character case when matching a delimiter. By default `false`.
 * @param limit The maximum number of substrings to return. Zero by default means no limit.
 * @return A sequence of strings split by the specified delimiters.
 */
@kotlin.internal.InlineOnly
public inline fun CharSequence.splitToSequence(
    vararg delimiters: String,
    ignoreCase: Boolean = false,
    limit: Int = 0
): Sequence<String> = split(*delimiters, ignoreCase = ignoreCase, limit = limit).asSequence()

/**
 * Appends the string from all the elements separated using the [separator] and using the given [prefix] and [postfix] if supplied.
 *
 * If the collection could be huge, you can specify a non-negative value of [limit], in which case only the first [limit]
 * elements will be appended, followed by the [truncated] string (which defaults to "...").
 *
 * @param separator The string to be inserted between elements.
 * @param prefix The string to be prepended to the output.
 * @param postfix The string to be appended to the output.
 * @param limit The maximum number of elements to append. -1 by default means no limit.
 * @param truncated The string to append when the limit is reached.
 * @param transform The function to transform each element before appending.
 * @return The resulting string.
 */
public fun <T> Iterable<T>.joinToString(
    separator: CharSequence = ", ",
    prefix: CharSequence = "",
    postfix: CharSequence = "",
    limit: Int = -1,
    truncated: CharSequence = "...",
    transform: ((T) -> CharSequence)? = null
): String {
    val sb = StringBuilder()
    sb.append(prefix)
    
    var count = 0
    for (element in this) {
        if (limit >= 0 && count >= limit) {
            sb.append(truncated)
            break
        }
        if (count > 0) {
            sb.append(separator)
        }
        sb.append(transform?.invoke(element) ?: element.toString())
        count++
    }
    
    sb.append(postfix)
    return sb.toString()
}

/**
 * Splits this char sequence into several char sequences each not exceeding the given [size].
 *
 * @param size The size of each chunk.
 * @return A list of chunks.
 */
public fun CharSequence.chunked(size: Int): List<String> =
    windowed(size, size, partialWindows = true)

/**
 * Splits this char sequence into several char sequences each not exceeding the given [size]
 * and applies the given [transform] function to each chunk.
 *
 * @param size The size of each chunk.
 * @param transform The function to apply to each chunk.
 * @return A list of results of applying the transform to each chunk.
 */
public fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> =
    windowed(size, size, partialWindows = true, transform = transform)

/**
 * Returns a list of snapshots of the window of the given [size] sliding along this char sequence
 * with the given [step], where each snapshot is a string.
 *
 * @param size The size of the window.
 * @param step The number of characters to move the window forward. By default 1.
 * @param partialWindows Whether to include partial windows at the end. By default false.
 * @return A list of windows.
 */
public fun CharSequence.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false
): List<String> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    
    val result = mutableListOf<String>()
    var i = 0
    while (i < length) {
        val end = (i + size).coerceAtMost(length)
        if (end - i == size || partialWindows) {
            result.add(substring(i, end))
        }
        i += step
        if (i >= length && !partialWindows) break
    }
    return result
}

/**
 * Returns a list of results of applying the given [transform] function to
 * each window of the given [size] sliding along this char sequence with the given [step].
 *
 * @param size The size of the window.
 * @param step The number of characters to move the window forward. By default 1.
 * @param partialWindows Whether to include partial windows at the end. By default false.
 * @param transform The function to apply to each window.
 * @return A list of results of applying the transform to each window.
 */
public fun <R> CharSequence.windowed(
    size: Int,
    step: Int = 1,
    partialWindows: Boolean = false,
    transform: (CharSequence) -> R
): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    require(step > 0) { "step must be positive, but was $step" }
    
    val result = mutableListOf<R>()
    var i = 0
    while (i < length) {
        val end = (i + size).coerceAtMost(length)
        if (end - i == size || partialWindows) {
            result.add(transform(substring(i, end)))
        }
        i += step
        if (i >= length && !partialWindows) break
    }
    return result
}

/**
 * Returns a list of pairs of each two adjacent characters in this char sequence.
 *
 * @return A list of pairs of adjacent characters.
 */
public fun CharSequence.zipWithNext(): List<Pair<Char, Char>> = zipWithNext { a, b -> Pair(a, b) }

/**
 * Returns a list containing the results of applying the given [transform] function
 * to each pair of two adjacent characters in this char sequence.
 *
 * @param transform The function to apply to each pair of adjacent characters.
 * @return A list of results of applying the transform to each pair.
 */
public fun <R> CharSequence.zipWithNext(transform: (Char, Char) -> R): List<R> {
    if (length < 2) return emptyList()
    val result = mutableListOf<R>()
    for (i in 0 until length - 1) {
        result.add(transform(this[i], this[i + 1]))
    }
    return result
}

/**
 * Returns an iterable of [IndexedValue] for each character in this char sequence.
 *
 * @return An iterable of indexed characters.
 */
public fun CharSequence.withIndex(): Iterable<IndexedValue<Char>> {
    val result = mutableListOf<IndexedValue<Char>>()
    for (i in 0 until length) {
        result.add(IndexedValue(i, this[i]))
    }
    return result
}

/**
 * Returns a list of pairs built from the characters of `this` char sequence and the [other] char sequence
 * with the same index. The returned list has the length of the shortest char sequence.
 *
 * @param other The other char sequence to zip with.
 * @return A list of pairs of characters with the same index.
 */
public fun CharSequence.zip(other: CharSequence): List<Pair<Char, Char>> {
    val size = minOf(length, other.length)
    val result = mutableListOf<Pair<Char, Char>>()
    for (i in 0 until size) {
        result.add(Pair(this[i], other[i]))
    }
    return result
}

/**
 * Returns a list of values built from the characters of `this` char sequence and the [other] char sequence
 * with the same index using the provided [transform] function applied to each pair of characters.
 * The returned list has the length of the shortest char sequence.
 *
 * @param other The other char sequence to zip with.
 * @param transform The function to apply to each pair of characters.
 * @return A list of results of applying the transform to each pair.
 */
public fun <V> CharSequence.zip(other: CharSequence, transform: (Char, Char) -> V): List<V> {
    val size = minOf(length, other.length)
    val result = mutableListOf<V>()
    for (i in 0 until size) {
        result.add(transform(this[i], other[i]))
    }
    return result
}
