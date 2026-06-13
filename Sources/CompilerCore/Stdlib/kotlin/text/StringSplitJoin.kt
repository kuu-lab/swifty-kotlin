// String split, join, chunked, windowed, zip functions migrated from Swift Runtime

package kotlin.text

/**
 * Splits this char sequence to a list of strings around occurrences of the specified [delimiters].
 */
public fun CharSequence.split(vararg delimiters: String, ignoreCase: Boolean = false, limit: Int = 0): List<String> {
    if (delimiters.isEmpty()) return listOf(this.toString())
    
    val result = mutableListOf<String>()
    var start = 0
    var count = 0
    
    while (start <= length && (limit <= 0 || count < limit - 1)) {
        var minIndex = -1
        var minDelimiter = ""
        
        for (delimiter in delimiters) {
            val index = if (ignoreCase) {
                this.toString().lowercase().indexOf(delimiter.lowercase(), start)
            } else {
                this.indexOf(delimiter, start)
            }
            if (index >= 0 && (minIndex < 0 || index < minIndex)) {
                minIndex = index
                minDelimiter = delimiter
            }
        }
        
        if (minIndex < 0) break
        
        result.add(substring(start, minIndex))
        start = minIndex + minDelimiter.length
        count++
    }
    
    if (start <= length) {
        result.add(substring(start, length))
    }
    
    return result
}

/**
 * Concatenates strings in [this] array using the specified [separator].
 */
public fun <T> Array<out T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String {
    val buffer = StringBuilder(prefix)
    var count = 0
    for (element in this) {
        if (count > 0) buffer.append(separator)
        if (limit >= 0 && count >= limit) {
            buffer.append(truncated)
            break
        }
        buffer.append(transform?.invoke(element) ?: element.toString())
        count++
    }
    buffer.append(postfix)
    return buffer.toString()
}

/**
 * Concatenates strings in [this] collection using the specified [separator].
 */
public fun <T> Iterable<T>.joinToString(separator: CharSequence = ", ", prefix: CharSequence = "", postfix: CharSequence = "", limit: Int = -1, truncated: CharSequence = "...", transform: ((T) -> CharSequence)? = null): String {
    val buffer = StringBuilder(prefix)
    var count = 0
    for (element in this) {
        if (count > 0) buffer.append(separator)
        if (limit >= 0 && count >= limit) {
            buffer.append(truncated)
            break
        }
        buffer.append(transform?.invoke(element) ?: element.toString())
        count++
    }
    buffer.append(postfix)
    return buffer.toString()
}

/**
 * Splits this char sequence into several char sequences each not exceeding the given [size].
 *
 * @param size The size of each chunk.
 * @return A list of chunks.
 */
public fun CharSequence.chunked(size: Int): List<String> {
    require(size > 0) { "size must be positive, but was $size" }
    val result = mutableListOf<String>()
    var i = 0
    while (i < length) {
        val end = (i + size).coerceAtMost(length)
        val chars = CharArray(end - i)
        for (j in i until end) {
            chars[j - i] = this[j]
        }
        result.add(String(chars))
        i += size
    }
    return result
}

/**
 * Splits this char sequence into several char sequences each not exceeding the given [size]
 * and applies the given [transform] function to each chunk.
 *
 * @param size The size of each chunk.
 * @param transform The function to apply to each chunk.
 * @return A list of results of applying the transform to each chunk.
 */
public fun <R> CharSequence.chunked(size: Int, transform: (CharSequence) -> R): List<R> {
    require(size > 0) { "size must be positive, but was $size" }
    val result = mutableListOf<R>()
    var i = 0
    while (i < length) {
        val end = (i + size).coerceAtMost(length)
        val chars = CharArray(end - i)
        for (j in i until end) {
            chars[j - i] = this[j]
        }
        result.add(transform(String(chars)))
        i += size
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
 * Returns a list of pairs built from the characters of `this` char sequence and the [other] char sequence
 * with the same index. The returned list has the length of the shortest char sequence.
 *
 * @param other The other char sequence to zip with.
 * @return A list of pairs of characters.
 */
public infix fun CharSequence.zip(other: CharSequence): List<Pair<Char, Char>> = zip(other) { a, b -> Pair(a, b) }

/**
 * Returns a list of values built from the characters of `this` char sequence and the [other] char sequence
 * with the same index using the provided [transform] function applied to each pair of characters.
 * The returned list has the length of the shortest char sequence.
 *
 * @param other The other char sequence to zip with.
 * @param transform The function to apply to each pair of characters.
 * @return A list of results of applying the transform to each pair.
 */
public fun <R> CharSequence.zip(other: CharSequence, transform: (Char, Char) -> R): List<R> {
    val minLength = minOf(length, other.length)
    val result = mutableListOf<R>()
    for (i in 0 until minLength) {
        result.add(transform(this[i], other[i]))
    }
    return result
}
