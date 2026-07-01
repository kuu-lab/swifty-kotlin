/// Residual bundled Kotlin source for stdlib functions not yet migrated to
/// standalone `.kt` files under `Sources/CompilerCore/Stdlib/`.
///
/// As functions are migrated to `.kt` files (auto-discovered by
/// `LoadSourcesPhase.injectBundledStdlib`), remove them from here.
enum BundledKotlinStdlib {
    // count / any / all / none / sumOf / maxByOrNull / minByOrNull are not yet
    // in standalone .kt files. The remaining collection HOFs (search, aggregate,
    // sorting, set) have been migrated to ListSearchHOF.kt, ListAggregateHOF.kt,
    // ListSortingHOF.kt, and SetHOF.kt respectively.
    static let kotlinCollectionsSource = """
package kotlin.collections

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
    if (length == 0) return null
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
    if (length == 0) return null
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
"""

    // repeat / reversed / padStart / padEnd are pure Kotlin but not yet in .kt files.
    // encodeToByteArray / decodeToString delegate to C-bridge primitives (__kk_*).
    // The case-conversion functions (lowercase, uppercase, capitalize, replaceFirstChar,
    // locale variants) have been migrated to StringCaseConversion.kt.
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

// MIGRATION-TEXT-006: indent & margin helpers

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
    val sb = StringBuilder()
    var i = 0
    while (i < length) {
        val c = this[i]
        if (c == '\\n') {
            result.add(sb.toString())
            sb.clear()
        } else if (c == '\\r') {
            result.add(sb.toString())
            sb.clear()
            if (i + 1 < length && this[i + 1] == '\\n') i++
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
    if (lines.size == 0) return ""
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
    if (lines.size == 0) return ""
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
    if (lines.size == 0) return this
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
    if (lines.size == 0) return ""
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
    if (lines.size == 0) return ""
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
    //
    // MIGRATION-TIME-001: absoluteValue, isNegative, isPositive, isInfinite have been
    // moved to Stdlib/kotlin/time/Duration.kt (auto-loaded by LoadSourcesPhase).
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
