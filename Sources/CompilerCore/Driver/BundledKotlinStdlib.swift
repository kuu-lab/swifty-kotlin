/// Kotlin source for stdlib functions that are compiled alongside user code.
///
/// Each file is injected as a virtual source file before the pipeline starts,
/// so these functions go through the full Lex → Parse → Sema → KIR → Codegen
/// pipeline and are available as internal LLVM functions at link time.
enum BundledKotlinStdlib {
    // MIGRATION-COL-004 / MIGRATION-COL-008: List aggregate HOF
    // count / any / all / none / fold / foldRight / reduce / reduceOrNull / scan / runningFold
    // are resolved to these bundled source definitions by Sema migration hooks.
    //
    // MIGRATION-COL-005: List search HOFs
    // These Kotlin-source definitions are injected as top-level extension functions.
    // Runtime ABI entry points remain registered as compatibility bridges while
    // member-dispatch lowering migrates incrementally.
    //
    // MIGRATION-COL-006: List sorting HOFs
    // sorted / sortedBy / sortedByDescending / sortedWith / reversed / shuffled are resolved
    // to these bundled source definitions by Sema migration hooks.
    // sumOf / maxByOrNull / minByOrNull — synthetic stubs exist in
    // HeaderHelpers+SyntheticListAggregateMembers.swift (member > extension in resolution
    // priority), so these serve as the migration-target definitions; stub removal and
    // dispatch wiring happen in the follow-up RF-LOWER tasks.
    // maxWith / minWith are omitted here because they call Comparator.compare, which is not
    // yet lowerable to a linkable symbol when bundled functions are codegen'd unconditionally.
    static let kotlinCollectionsSource = """
package kotlin.collections

// MIGRATION-COL-005

public fun <T> List<T>.first(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[0]
}

public fun <T> List<T>.first(predicate: (T) -> Boolean): T {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.firstOrNull(): T? {
    if (isEmpty()) return null
    return this[0]
}

public fun <T> List<T>.firstOrNull(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.find(predicate: (T) -> Boolean): T? {
    var i = 0
    val sz = size
    while (i < sz) {
        val element = this[i]
        if (predicate(element)) return element
        i++
    }
    return null
}

public fun <T> List<T>.last(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[size - 1]
}

public fun <T> List<T>.last(predicate: (T) -> Boolean): T {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.lastOrNull(): T? {
    if (isEmpty()) return null
    return this[size - 1]
}

public fun <T> List<T>.lastOrNull(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.findLast(predicate: (T) -> Boolean): T? {
    var i = size - 1
    while (i >= 0) {
        val element = this[i]
        if (predicate(element)) return element
        i--
    }
    return null
}

public fun <T> List<T>.single(): T {
    val sz = size
    if (sz == 1) return this[0]
    if (sz == 0) throw NoSuchElementException("Collection is empty.")
    throw IllegalArgumentException("Collection has more than one element.")
}

public fun <T> List<T>.single(predicate: (T) -> Boolean): T {
    var matchIndex = -1
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) {
                throw IllegalArgumentException("Collection contains more than one matching element.")
            }
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    throw NoSuchElementException("Collection contains no element matching the predicate.")
}

public fun <T> List<T>.singleOrNull(): T? {
    if (size == 1) return this[0]
    return null
}

public fun <T> List<T>.singleOrNull(predicate: (T) -> Boolean): T? {
    var matchIndex = -1
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) {
            if (matchIndex >= 0) return null
            matchIndex = i
        }
        i++
    }
    if (matchIndex >= 0) return this[matchIndex]
    return null
}

public fun <T> List<T>.indexOf(element: T): Int {
    var i = 0
    val sz = size
    while (i < sz) {
        if (this[i] == element) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfFirst(predicate: (T) -> Boolean): Int {
    var i = 0
    val sz = size
    while (i < sz) {
        if (predicate(this[i])) return i
        i++
    }
    return -1
}

public fun <T> List<T>.indexOfLast(predicate: (T) -> Boolean): Int {
    var i = size - 1
    while (i >= 0) {
        if (predicate(this[i])) return i
        i--
    }
    return -1
}

// MIGRATION-COL-008

public fun <T> List<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < size) { if (predicate(this[i])) count += 1; i += 1 }
    return count
}

public fun <T> List<T>.any(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (predicate(this[i])) return true; i += 1 }
    return false
}

public fun <T> List<T>.all(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (!predicate(this[i])) return false; i += 1 }
    return true
}

public fun <T> List<T>.none(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (predicate(this[i])) return false; i += 1 }
    return true
}

public fun <T, R> List<T>.fold(initial: R, operation: (R, T) -> R): R {
    var accumulator = initial
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public fun <T, R> List<T>.foldRight(initial: R, operation: (T, R) -> R): R {
    var accumulator = initial
    var i = size - 1
    while (i >= 0) {
        accumulator = operation(this[i], accumulator)
        i -= 1
    }
    return accumulator
}

public fun <T> List<T>.reduce(operation: (T, T) -> T): T {
    if (isEmpty()) throw UnsupportedOperationException("Empty collection can't be reduced.")
    var accumulator = this[0]
    var i = 1
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public fun <T> List<T>.reduceOrNull(operation: (T, T) -> T): T? {
    if (isEmpty()) return null
    var accumulator = this[0]
    var i = 1
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        i += 1
    }
    return accumulator
}

public fun <T, R> List<T>.scan(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}

public fun <T, R> List<T>.runningFold(initial: R, operation: (R, T) -> R): List<R> {
    val result = mutableListOf<R>()
    var accumulator = initial
    result.add(accumulator)
    var i = 0
    while (i < size) {
        accumulator = operation(accumulator, this[i])
        result.add(accumulator)
        i += 1
    }
    return result
}

public fun <T> List<T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < size) { sum += selector(this[i]); i += 1 }
    return sum
}

public fun <T, R : Comparable<R>> List<T>.maxByOrNull(selector: (T) -> R): T? {
    if (isEmpty()) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (key > bestKey) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T, R : Comparable<R>> List<T>.minByOrNull(selector: (T) -> R): T? {
    if (isEmpty()) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (key < bestKey) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T> List<T>.reversed(): List<T> {
    val result = mutableListOf<T>()
    var i = size - 1
    while (i >= 0) {
        result.add(this[i])
        i--
    }
    return result
}

public fun <T : Comparable<T>> List<T>.sorted(): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && result[insertAt - 1].compareTo(element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public fun <T, R : Comparable<R>> List<T>.sortedBy(selector: (T) -> R): List<T> {
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val element = this[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) > 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result
}

public fun <T, R : Comparable<R>> List<T>.sortedByDescending(selector: (T) -> R): List<T> {
    val result = mutableListOf<T>()
    val keys = mutableListOf<R>()
    var i = 0
    while (i < size) {
        val element = this[i]
        val key = selector(element)
        var insertAt = keys.size
        while (insertAt > 0 && keys[insertAt - 1].compareTo(key) < 0) {
            insertAt--
        }
        keys.add(insertAt, key)
        result.add(insertAt, element)
        i++
    }
    return result
}

public fun <T> List<T>.sortedWith(comparator: (T, T) -> Int): List<T> {
    val result = mutableListOf<T>()
    var i = 0
    while (i < size) {
        val element = this[i]
        var insertAt = result.size
        while (insertAt > 0 && comparator(result[insertAt - 1], element) > 0) {
            insertAt--
        }
        result.add(insertAt, element)
        i++
    }
    return result
}

public fun <T> List<T>.shuffled(): List<T> = shuffled(Random.Default)

public fun <T> List<T>.shuffled(random: Random): List<T> {
    val result = mutableListOf<T>()
    var copyIndex = 0
    while (copyIndex < size) {
        result.add(this[copyIndex])
        copyIndex++
    }

    var i = result.size - 1
    while (i > 0) {
        val j = random.nextInt(i + 1)
        val tmp = result[i]
        result[i] = result[j]
        result[j] = tmp
        i--
    }
    return result
}
"""

    static let kotlinTextSource = """
package kotlin.text

fun String.repeat(count: Int): String {
    if (count < 0) throw IllegalArgumentException("Count 'n' must be non-negative, but was $count.")
    val sb = StringBuilder()
    var i = 0
    while (i < count) { sb.append(this); i += 1 }
    return sb.toString()
}

fun String.reversed(): String {
    val len = this.length
    val sb = StringBuilder()
    var i = len - 1
    while (i >= 0) { sb.append(this[i]); i -= 1 }
    return sb.toString()
}

fun String.padStart(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    sb.append(this)
    return sb.toString()
}

fun String.padEnd(length: Int, padChar: Char = ' '): String {
    val padding = length - this.length
    if (padding <= 0) return this
    val sb = StringBuilder()
    sb.append(this)
    var i = 0
    while (i < padding) { sb.append(padChar); i += 1 }
    return sb.toString()
}

// MIGRATION-TEXT-005: String case conversion and locale wrappers

public fun String.lowercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        sb.append(this[i].lowercase())
        i += 1
    }
    return sb.toString()
}

public fun String.uppercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        sb.append(this[i].uppercase())
        i += 1
    }
    return sb.toString()
}

public fun String.capitalize(): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(this[0].uppercase())
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

public fun String.replaceFirstChar(transform: (Char) -> Char): String {
    if (isEmpty()) return this
    val sb = StringBuilder()
    sb.append(transform(this[0]))
    var i = 1
    while (i < length) {
        sb.append(this[i])
        i += 1
    }
    return sb.toString()
}

public fun String.lowercase(locale: java.util.Locale): String =
    this.__kk_lowercase_locale(locale)

public fun String.uppercase(locale: java.util.Locale): String =
    this.__kk_uppercase_locale(locale)


// MIGRATION-TEXT-007: String.encodeToByteArray — delegate to private C-bridge primitives

fun String.encodeToByteArray(): ByteArray = this.__kk_encodeToByteArray()

fun String.encodeToByteArray(startIndex: Int, endIndex: Int): ByteArray =
    this.__kk_encodeToByteArray_range(startIndex, endIndex)

fun String.encodeToByteArray(charset: Charset): ByteArray =
    this.__kk_encodeToByteArray_charset(charset)

// MIGRATION-TEXT-007: ByteArray.decodeToString — delegate to private C-bridge primitives

fun ByteArray.decodeToString(): String = this.__kk_decodeToString()

fun ByteArray.decodeToString(charset: Charset): String =
    this.__kk_decodeToString_charset(charset)

fun ByteArray.decodeToString(startIndex: Int, endIndex: Int): String =
    this.__kk_decodeToString_range(startIndex, endIndex)

fun ByteArray.decodeToString(startIndex: Int, endIndex: Int, throwOnInvalidSequence: Boolean): String =
    this.__kk_decodeToString_range_throw(startIndex, endIndex, throwOnInvalidSequence)
"""
}
