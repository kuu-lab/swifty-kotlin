/// Kotlin source for stdlib functions that are compiled alongside user code.
///
/// Each file is injected as a virtual source file before the pipeline starts,
/// so these functions go through the full Lex → Parse → Sema → KIR → Codegen
/// pipeline and are available as internal LLVM functions at link time.
enum BundledKotlinStdlib {
    // MIGRATION-COL-005: List search HOFs
    // These Kotlin-source definitions are injected as top-level extension functions.
    // Runtime ABI entry points remain registered as compatibility bridges while
    // member-dispatch lowering migrates incrementally.
    //
    // MIGRATION-COL-008: List 集計 HOF
    // count / any / all / none — currently Sema-unresolved (no synthetic stub), so these
    // extension functions are the first resolved definitions and will be called directly.
    // sumOf / maxByOrNull / minByOrNull — synthetic stubs exist in
    // HeaderHelpers+SyntheticListAggregateMembers.swift (member > extension in resolution
    // priority), so these serve as the migration-target definitions; stub removal and
    // dispatch wiring happen in the follow-up RF-LOWER tasks.
    // maxWith / minWith are omitted here because they call Comparator.compare, which is not
    // yet lowerable to a linkable symbol when bundled functions are codegen'd unconditionally.
    //
    // MIGRATION-COL-013: Set HOF implementations in Kotlin source.
    // sorted/first/last are already routed to kk_set_* by CallLowerer+UnresolvedMemberCalls
    // for Set receivers, so they are excluded here to avoid duplicate resolution.
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

// MIGRATION-COL-013

internal fun <T> Set<T>.filter(predicate: (T) -> Boolean): List<T> {
    val result = mutableListOf<T>()
    for (element in this) {
        if (predicate(element)) result.add(element)
    }
    return result
}

internal fun <T, R> Set<T>.map(transform: (T) -> R): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        result.add(transform(element))
    }
    return result
}

internal fun <T, R> Set<T>.flatMap(transform: (T) -> Iterable<R>): List<R> {
    val result = mutableListOf<R>()
    for (element in this) {
        for (subElement in transform(element)) {
            result.add(subElement)
        }
    }
    return result
}

internal fun <T> Set<T>.forEach(action: (T) -> Unit) {
    for (element in this) {
        action(element)
    }
}

internal fun <T> Set<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    for (element in this) {
        if (predicate(element)) count++
    }
    return count
}

internal fun <T> Set<T>.any(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return true
    }
    return false
}

internal fun <T> Set<T>.all(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (!predicate(element)) return false
    }
    return true
}

internal fun <T> Set<T>.none(predicate: (T) -> Boolean): Boolean {
    for (element in this) {
        if (predicate(element)) return false
    }
    return true
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

// MIGRATION-TEXT-006: String indent and format functions

private fun String.kk_drop(n: Int): String {
    val sb = StringBuilder()
    var i = n
    while (i < length) { sb.append(this[i]); i++ }
    return sb.toString()
}

private fun String.hasPrefix(prefix: String): Boolean {
    if (prefix.length > length) return false
    var i = 0
    while (i < prefix.length) {
        if (this[i] != prefix[i]) return false
        i++
    }
    return true
}

private fun String.splitIntoLines(): List<String> {
    val result = mutableListOf<String>()
    var sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c == '\\r') {
            result.add(sb.toString())
            sb = StringBuilder()
            if (i + 1 < length && this[i + 1] == '\\n') {
                i++
            }
        } else if (c == '\\n') {
            result.add(sb.toString())
            sb = StringBuilder()
        } else {
            sb.append(c)
        }
        i++
    }
    result.add(sb.toString())
    return result
}

private fun String.leadingWhitespaceCount(): Int {
    var count = 0
    while (count < length) {
        val c = this[count]
        if (c != ' ' && c != '\\t') break
        count++
    }
    return count
}

private fun String.isBlankLine(): Boolean {
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c != ' ' && c != '\\t') return false
        i++
    }
    return true
}

private fun trimBlankEdges(lines: List<String>): List<String> {
    val n = lines.size
    var start = 0
    var end = n
    while (start < end && lines[start].isBlankLine()) start++
    while (end > start && lines[end - 1].isBlankLine()) end--
    val result = mutableListOf<String>()
    var i = start
    while (i < end) {
        result.add(lines[i])
        i++
    }
    return result
}

public fun String.trimIndent(): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.isEmpty()) return ""
    var minIndent = -1
    for (line in lines) {
        if (!line.isBlankLine()) {
            val cnt = line.leadingWhitespaceCount()
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        if (line.isBlankLine()) {
            sb.append("")
        } else {
            sb.append(line.kk_drop(minIndent))
        }
        first = false
    }
    return sb.toString()
}

public fun String.trimMargin(marginPrefix: String = "|"): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.isEmpty()) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        var i = 0
        while (i < line.length && (line[i] == ' ' || line[i] == '\\t')) i++
        val trimmedLeading = line.kk_drop(i)
        if (trimmedLeading.hasPrefix(marginPrefix)) {
            sb.append(trimmedLeading.kk_drop(marginPrefix.length))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

public fun String.indent(): String = indent(4)

public fun String.indent(n: Int): String {
    if (n == 0) return this
    val lines = splitIntoLines()
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\n')
        if (n > 0) {
            var j = 0
            while (j < n) { sb.append(' '); j++ }
            sb.append(line)
        } else {
            val remove = -n
            val leading = line.leadingWhitespaceCount()
            val drop = if (remove < leading) remove else leading
            sb.append(line.kk_drop(drop))
        }
        first = false
    }
    return sb.toString()
}

public fun String.prependIndent(indent: String = "    "): String {
    val lines = splitIntoLines()
    if (lines.isEmpty()) return this
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        sb.append(indent)
        sb.append(line)
        first = false
    }
    return sb.toString()
}

public fun String.replaceIndent(newIndent: String = ""): String {
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.isEmpty()) return ""
    var minIndent = -1
    for (line in lines) {
        if (!line.isBlankLine()) {
            val cnt = line.leadingWhitespaceCount()
            if (minIndent == -1 || cnt < minIndent) minIndent = cnt
        }
    }
    if (minIndent < 0) minIndent = 0
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        if (line.isBlankLine()) {
            sb.append("")
        } else {
            sb.append(newIndent)
            sb.append(line.kk_drop(minIndent))
        }
        first = false
    }
    return sb.toString()
}

public fun String.replaceIndentByMargin(newIndent: String = "", marginPrefix: String = "|"): String {
    if (marginPrefix.isBlankLine()) {
        throw IllegalArgumentException("marginPrefix must be non-blank string.")
    }
    val lines = trimBlankEdges(splitIntoLines())
    if (lines.isEmpty()) return ""
    val sb = StringBuilder()
    var first = true
    for (line in lines) {
        if (!first) sb.append('\\n')
        var i = 0
        while (i < line.length && (line[i] == ' ' || line[i] == '\\t')) i++
        val trimmedLeading = line.kk_drop(i)
        if (trimmedLeading.hasPrefix(marginPrefix)) {
            sb.append(newIndent)
            sb.append(trimmedLeading.kk_drop(marginPrefix.length))
        } else {
            sb.append(line)
        }
        first = false
    }
    return sb.toString()
}

"""

    // MIGRATION-TIME-002: Duration component and string conversion functions.
    // Migrated from Sources/Runtime/RuntimeDuration.swift.
    // Native bridges that remain:
    //   kk_duration_inWholeNanoseconds  (base primitive — accesses Swift object internals)
    //   kk_duration_toString            (overriding Any.toString() requires a class member,
    //                                    not an extension function; stays native)
    //   kk_duration_parse*              (complex parsing logic, stays native)
    static let kotlinTimeSource = """
package kotlin.time

val Duration.inWholeMilliseconds: Long get() = inWholeNanoseconds / 1_000_000L

val Duration.inWholeMicroseconds: Long get() = inWholeNanoseconds / 1_000L

val Duration.inWholeSeconds: Long get() = inWholeNanoseconds / 1_000_000_000L

val Duration.inWholeMinutes: Long get() = inWholeNanoseconds / 60_000_000_000L

val Duration.inWholeHours: Long get() = inWholeNanoseconds / 3_600_000_000_000L

val Duration.inWholeDays: Long get() = inWholeNanoseconds / 86_400_000_000_000L

fun Duration.toIsoString(): String {
    val ns = inWholeNanoseconds
    if (ns == Long.MAX_VALUE) return "PT9999999999999H"
    if (ns == Long.MIN_VALUE) return "-PT9999999999999H"
    val isNeg = ns < 0L
    var rem = if (isNeg) -ns else ns
    val hours = rem / 3_600_000_000_000L
    rem %= 3_600_000_000_000L
    val minutes = rem / 60_000_000_000L
    rem %= 60_000_000_000L
    val seconds = rem / 1_000_000_000L
    val nanos = rem % 1_000_000_000L
    val sb = StringBuilder()
    if (isNeg) sb.append('-')
    sb.append('P')
    sb.append('T')
    if (hours != 0L) { sb.append(hours); sb.append('H') }
    if (minutes != 0L || (hours != 0L && (seconds != 0L || nanos != 0L))) {
        sb.append(minutes)
        sb.append('M')
    }
    if (seconds != 0L || nanos != 0L || (hours == 0L && minutes == 0L)) {
        sb.append(seconds)
        if (nanos != 0L) {
            sb.append('.')
            var width = 9
            var divisor = 1L
            if (nanos % 1_000_000L == 0L) {
                width = 3
                divisor = 1_000_000L
            } else if (nanos % 1_000L == 0L) {
                width = 6
                divisor = 1_000L
            }
            val fractionValue = nanos / divisor
            val frac = fractionValue.toString()
            var pad = width - frac.length
            while (pad > 0) { sb.append('0'); pad -= 1 }
            var i = 0
            while (i < frac.length) { sb.append(frac[i]); i += 1 }
        }
        sb.append('S')
    }
    return sb.toString()
}

fun <T> Duration.toComponents(action: (Long, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0)
    }
    val s = totalNs / 1_000_000_000L
    val n = (totalNs % 1_000_000_000L).toInt()
    return action(s, n)
}

fun <T> Duration.toComponents(action: (Long, Int, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0, 0)
    }
    var rem = totalNs
    val m = rem / 60_000_000_000L
    rem %= 60_000_000_000L
    val s = (rem / 1_000_000_000L).toInt()
    val n = (rem % 1_000_000_000L).toInt()
    return action(m, s, n)
}

fun <T> Duration.toComponents(action: (Long, Int, Int, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0, 0, 0)
    }
    var rem = totalNs
    val h = rem / 3_600_000_000_000L
    rem %= 3_600_000_000_000L
    val m = (rem / 60_000_000_000L).toInt()
    rem %= 60_000_000_000L
    val s = (rem / 1_000_000_000L).toInt()
    val n = (rem % 1_000_000_000L).toInt()
    return action(h, m, s, n)
}

fun <T> Duration.toComponents(action: (Long, Int, Int, Int, Int) -> T): T {
    val totalNs = inWholeNanoseconds
    if (totalNs == Long.MAX_VALUE || totalNs == Long.MIN_VALUE) {
        return action(totalNs, 0, 0, 0, 0)
    }
    var rem = totalNs
    val d = rem / 86_400_000_000_000L
    rem %= 86_400_000_000_000L
    val h = (rem / 3_600_000_000_000L).toInt()
    rem %= 3_600_000_000_000L
    val m = (rem / 60_000_000_000L).toInt()
    rem %= 60_000_000_000L
    val s = (rem / 1_000_000_000L).toInt()
    val n = (rem % 1_000_000_000L).toInt()
    return action(d, h, m, s, n)
}

// MIGRATION-TIME-003: Duration factory extension properties
public val Int.nanoseconds: Duration get() = this.toDuration(DurationUnit.NANOSECONDS)
public val Int.microseconds: Duration get() = this.toDuration(DurationUnit.MICROSECONDS)
public val Int.milliseconds: Duration get() = this.toDuration(DurationUnit.MILLISECONDS)
public val Int.seconds: Duration get() = this.toDuration(DurationUnit.SECONDS)
public val Int.minutes: Duration get() = this.toDuration(DurationUnit.MINUTES)
public val Int.hours: Duration get() = this.toDuration(DurationUnit.HOURS)
public val Int.days: Duration get() = this.toDuration(DurationUnit.DAYS)

public val Long.nanoseconds: Duration get() = this.toDuration(DurationUnit.NANOSECONDS)
public val Long.microseconds: Duration get() = this.toDuration(DurationUnit.MICROSECONDS)
public val Long.milliseconds: Duration get() = this.toDuration(DurationUnit.MILLISECONDS)
public val Long.seconds: Duration get() = this.toDuration(DurationUnit.SECONDS)
public val Long.minutes: Duration get() = this.toDuration(DurationUnit.MINUTES)
public val Long.hours: Duration get() = this.toDuration(DurationUnit.HOURS)
public val Long.days: Duration get() = this.toDuration(DurationUnit.DAYS)

public val Double.nanoseconds: Duration get() = this.toDuration(DurationUnit.NANOSECONDS)
public val Double.microseconds: Duration get() = this.toDuration(DurationUnit.MICROSECONDS)
public val Double.milliseconds: Duration get() = this.toDuration(DurationUnit.MILLISECONDS)
public val Double.seconds: Duration get() = this.toDuration(DurationUnit.SECONDS)
public val Double.minutes: Duration get() = this.toDuration(DurationUnit.MINUTES)
public val Double.hours: Duration get() = this.toDuration(DurationUnit.HOURS)
public val Double.days: Duration get() = this.toDuration(DurationUnit.DAYS)
"""

    // MIGRATION-SEQ-003: Sequence collection-conversion HOFs
    // toList / toSet / toMutableList use forEach as the iteration primitive
    // (intercepted by CollectionLiteralLoweringPass to kk_sequence_forEach).
    //
    // Terminal HOFs (first, last, single, count, any, all, none, …) are resolved
    // via synthetic stubs (HeaderHelpers+SyntheticSequenceTerminalStubs.swift) to
    // the C-level kk_sequence_* entry points in RuntimeSequence.swift.  They are
    // NOT included here to avoid scope pollution that would break Sema resolution
    // for List / Collection / Set receivers with the same member names.
    static let kotlinSequencesSource = """
package kotlin.sequences

// MIGRATION-SEQ-003

public fun <T> Sequence<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) { result.add(element) }
    return result
}

public fun <T> Sequence<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) { result.add(element) }
    return result
}

public fun <T> Sequence<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) { result.add(element) }
    return result
}

"""
}
